import Foundation
import Darwin

struct FanRequest: Codable {
    var fan: Int
    var rpm: Int
    var updated: TimeInterval
}

enum FanControl {
    static let staleAfter: TimeInterval = 30

    static func requestURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/setatus/fan.json")
    }

    static func send(fan: Int, rpm: Int, home: String = NSHomeDirectory()) {
        let request = FanRequest(fan: fan, rpm: max(0, rpm), updated: Date().timeIntervalSince1970)
        let url = requestURL(home: home)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(request) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func helperRunning() -> Bool {
        guard let output = Shell.run("/usr/bin/pgrep", ["-f", "--", "--fan-hold"]) else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One admin prompt, then the helper keeps control until the request goes stale or auto is requested.
    static func startHelper(home: String = NSHomeDirectory()) -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let command = "'\(executable)' --fan-hold '\(home)'"
        let script = "do shell script \"\(command) >/dev/null 2>&1 &\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Privileged helper

    static func hold(home: String) -> Never {
        guard geteuid() == 0, let smc = SMC() else { exit(2) }

        var stopping = false
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { stopping = true }
            source.resume()
            sources.append(source)
        }

        let url = requestURL(home: home)
        let expectedDirectory = URL(fileURLWithPath: home)
            .appendingPathComponent(".config/setatus")
            .resolvingSymlinksInPath()
        var engaged = false
        var announcedRPM = -1
        var lastModeCheck = Date.distantPast

        while true {
            if stopping {
                restore(smc)
                exit(0)
            }

            let now = Date().timeIntervalSince1970
            guard isSafeFile(url, directory: expectedDirectory),
                  let data = try? Data(contentsOf: url),
                  let request = try? JSONDecoder().decode(FanRequest.self, from: data),
                  now - request.updated < staleAfter,
                  request.rpm > 0,
                  validFan(smc, request.fan) else {
                restore(smc)
                exit(0)
            }

            if !engaged {
                engaged = engage(smc, fan: request.fan)
            }

            if engaged, Date().timeIntervalSince(lastModeCheck) > 3 {
                lastModeCheck = Date()
                if let key = modeKey(smc, fan: request.fan), smc.readUInt8(key) != 1 {
                    engaged = false
                }
            }

            if engaged {
                let target = clamp(smc: smc, fan: request.fan, rpm: request.rpm)
                if target != announcedRPM {
                    // 0x87 (size mismatch) is returned by firmware on some Macs even though the value applies.
                    let result = smc.writeFloat("F\(request.fan)Tg", Float(target))
                    if result == nil || result == 0 || result == 0x87 {
                        announcedRPM = target
                    } else {
                        engaged = false
                    }
                }
            }

            usleep(1_000_000)
        }
    }

    private static func validFan(_ smc: SMC, _ index: Int) -> Bool {
        index >= 0 && index < 4 && smc.meta("F\(index)Ac") != nil
    }

    /// The root helper only trusts a regular file in the expected directory, never a symlink.
    private static func isSafeFile(_ url: URL, directory: URL) -> Bool {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory,
              let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        else { return false }
        return values.isSymbolicLink != true && values.isRegularFile == true
    }

    private static func engage(_ smc: SMC, fan: Int) -> Bool {
        if let key = modeKey(smc, fan: fan), smc.readUInt8(key) == 1 { return true }

        _ = smc.writeUInt8("Ftst", 1)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let key = modeKey(smc, fan: fan), smc.writeUInt8(key, 1) == 0 {
                return true
            }
            usleep(100_000)
        }
        return modeKey(smc, fan: fan).flatMap { smc.readUInt8($0) } == 1
    }

    private static func restore(_ smc: SMC) {
        for fan in 0..<4 {
            if let key = modeKey(smc, fan: fan), smc.readUInt8(key) == 1 {
                _ = smc.writeUInt8(key, 0)
            }
        }
        if smc.readUInt8("Ftst") == 1 {
            _ = smc.writeUInt8("Ftst", 0)
        }
    }

    private static func modeKey(_ smc: SMC, fan: Int) -> String? {
        for key in ["F\(fan)Md", "F\(fan)md"] where smc.meta(key) != nil {
            return key
        }
        return nil
    }

    private static func clamp(smc: SMC, fan: Int, rpm: Int) -> Int {
        let minimum = smc.readFloat("F\(fan)Mn") ?? 0
        let maximum = smc.readFloat("F\(fan)Mx") ?? 0
        guard maximum > minimum, maximum > 0 else { return rpm }
        return Int(min(max(Double(rpm), minimum), maximum))
    }
}
