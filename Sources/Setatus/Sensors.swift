import Foundation
import IOKit

// SMC param struct. Keep the size at 80 bytes: dataAttributes is widened to
// UInt32 on purpose so Swift's layout matches the kernel's SMCKeyData_t.
private struct SMCVers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
private struct SMCPLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
private struct SMCKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt32 = 0 }
private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVers()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMC {
    struct Fan {
        let index: Int
        let actual: Double
        let minimum: Double
        let maximum: Double
        let target: Double
    }

    struct KeyMeta {
        let size: UInt32
        let type: String
        let writable: Bool
    }

    private var conn: io_connect_t = 0
    private var tempKeys: [String] = []
    private var scanned = false

    private enum Selector: UInt32 { case readKey = 5, keyFromIndex = 8, keyInfo = 9 }

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(conn) }

    func temperatures() -> [(label: String, celsius: Double)] {
        if !scanned { scan() }
        var best: [String: Double] = [:]
        for key in tempKeys {
            guard let value = readFloat(key), value > 5, value < 115 else { continue }
            let label = Self.label(for: key)
            best[label] = max(best[label] ?? 0, value)
        }
        return best.sorted { $0.value > $1.value }.map { (label: $0.key, celsius: $0.value) }
    }

    func fans() -> [Fan] {
        var result: [Fan] = []
        for index in 0..<4 {
            guard readRaw("F\(index)Ac") != nil else { continue }
            result.append(Fan(index: index,
                             actual: readFloat("F\(index)Ac") ?? 0,
                             minimum: readFloat("F\(index)Mn") ?? 0,
                             maximum: readFloat("F\(index)Mx") ?? 0,
                             target: readFloat("F\(index)Tg") ?? 0))
        }
        return result
    }

    func meta(_ key: String) -> KeyMeta? {
        var input = SMCKeyData()
        input.key = Self.fourCC(key)
        input.data8 = UInt8(Selector.keyInfo.rawValue)
        guard let out = kernelCall(&input), out.result == 0 else { return nil }
        return KeyMeta(size: out.keyInfo.dataSize,
                       type: Self.fourCC(out.keyInfo.dataType).trimmingCharacters(in: .whitespaces),
                       writable: out.keyInfo.dataAttributes & 0x40 != 0)
    }

    func readUInt8(_ key: String) -> UInt8? {
        guard let out = readRaw(key) else { return nil }
        return withUnsafeBytes(of: out.bytes) { Array($0).first }
    }

    func writeUInt8(_ key: String, _ value: UInt8) -> UInt8? {
        write(key, bytes: [value])
    }

    func writeFloat(_ key: String, _ value: Float) -> UInt8? {
        let bits = value.bitPattern.littleEndian
        let bytes = withUnsafeBytes(of: bits) { Array($0) }
        return write(key, bytes: bytes)
    }

    private func write(_ key: String, bytes: [UInt8]) -> UInt8? {
        var infoInput = SMCKeyData()
        infoInput.key = Self.fourCC(key)
        infoInput.data8 = UInt8(Selector.keyInfo.rawValue)
        guard let info = kernelCall(&infoInput), info.result == 0 else { return nil }

        var input = SMCKeyData()
        input.key = Self.fourCC(key)
        input.data8 = 6
        input.keyInfo = info.keyInfo
        withUnsafeMutableBytes(of: &input.bytes) { destination in
            for (index, byte) in bytes.prefix(32).enumerated() {
                destination[index] = byte
            }
        }
        guard let out = kernelCall(&input) else { return nil }
        return out.result
    }

    // MARK: - SMC plumbing

    private func kernelCall(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.stride
        let kr = withUnsafePointer(to: &input) { inputPtr in
            withUnsafeMutablePointer(to: &output) { outputPtr in
                IOConnectCallStructMethod(conn, 2, inputPtr, size, outputPtr, &size)
            }
        }
        return kr == KERN_SUCCESS ? output : nil
    }

    private func scan() {
        // Only mark the scan done once the key count is readable; a Mac where AppleSMC
        // is not ready yet must retry on the next tick instead of going permanently blank.
        guard let count = readUInt32("#KEY"), count > 0 else { return }
        scanned = true

        var seen = Set<String>()
        for index in 0..<min(count, 2000) {
            var input = SMCKeyData()
            input.data8 = UInt8(Selector.keyFromIndex.rawValue)
            input.data32 = index
            guard let key = kernelCall(&input)?.key else { continue }

            var infoInput = SMCKeyData()
            infoInput.key = key
            infoInput.data8 = UInt8(Selector.keyInfo.rawValue)
            guard let info = kernelCall(&infoInput),
                  Self.fourCC(info.keyInfo.dataType).trimmingCharacters(in: .whitespaces) == "flt",
                  info.keyInfo.dataSize == 4 else { continue }

            let name = Self.fourCC(key)
            guard Self.isTemperatureKey(name) else { continue }
            if seen.insert(name).inserted { tempKeys.append(name) }
        }
    }

    func readFloat(_ key: String) -> Double? {
        guard let out = readRaw(key) else { return nil }
        let b = withUnsafeBytes(of: out.bytes) { Array($0) }
        guard b.count >= 4 else { return nil }
        let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        return Double(Float(bitPattern: bits))
    }

    private func readRaw(_ key: String) -> SMCKeyData? {
        var infoInput = SMCKeyData()
        infoInput.key = Self.fourCC(key)
        infoInput.data8 = UInt8(Selector.keyInfo.rawValue)
        guard let info = kernelCall(&infoInput) else { return nil }

        var input = SMCKeyData()
        input.key = Self.fourCC(key)
        input.data8 = UInt8(Selector.readKey.rawValue)
        input.keyInfo = info.keyInfo
        guard let out = kernelCall(&input), out.result == 0 else { return nil }
        return out
    }

    private func readUInt32(_ key: String) -> UInt32? {
        guard let out = readRaw(key) else { return nil }
        let b = withUnsafeBytes(of: out.bytes) { Array($0) }
        guard b.count >= 4 else { return nil }
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }

    private static func fourCC(_ value: UInt32) -> String {
        String(bytes: [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                       UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)], encoding: .ascii) ?? ""
    }

    private static func fourCC(_ value: String) -> UInt32 {
        let c = Array(value.utf8)
        guard c.count == 4 else { return 0 }
        return UInt32(c[0]) << 24 | UInt32(c[1]) << 16 | UInt32(c[2]) << 8 | UInt32(c[3])
    }

    private static func isTemperatureKey(_ key: String) -> Bool {
        let groups = ["Tp", "Tg", "TB", "Ts", "Te", "Tf", "TC", "TD", "Ta"]
        return groups.contains { key.hasPrefix($0) } || key == "TCHP" || key == "TCMb" || key == "TCMz"
    }

    private static func label(for key: String) -> String {
        if key.hasPrefix("Tp") || key.hasPrefix("TC") || key.hasPrefix("TD") || key.hasPrefix("Te") { return "CPU" }
        if key.hasPrefix("Tg") || key.hasPrefix("Tf") { return "GPU" }
        if key.hasPrefix("TB") { return "Battery" }
        if key.hasPrefix("Ts") { return "Skin" }
        if key.hasPrefix("Ta") { return "Ambient" }
        return key
    }
}
