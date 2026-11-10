import Foundation

enum GPU {
    static func utilization() -> Double? {
        guard let output = Shell.run("/usr/sbin/ioreg",
                                     ["-r", "-c", "IOAccelerator", "-d", "1", "-k", "PerformanceStatistics"])
        else { return nil }
        let marker = "\"Device Utilization %\"="
        guard let range = output.range(of: marker) else { return nil }
        let digits = output[range.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : Double(digits)
    }
}
