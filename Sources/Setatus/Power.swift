import Foundation
import IOKit.ps

struct PowerSnapshot {
    var inputWatts: Double?
    var adapterWatts: Double?
    var externalPower: Bool = false
    var batteryPercent: Double?
    var charging: Bool = false
}

enum Power {
    /// SystemPowerIn is in mW; adapter Watts is the negotiated adapter rating.
    static func sample() -> PowerSnapshot? {
        guard let output = Shell.run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery", "-d", "1"]) else {
            return nil
        }
        var snapshot = PowerSnapshot()
        snapshot.inputWatts = number(after: "\"SystemPowerIn\"=", in: output).map { $0 / 1000 }
        snapshot.adapterWatts = number(after: "\"Watts\"=", in: output)
        snapshot.externalPower = output.contains("\"ExternalConnected\" = Yes")
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let description = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {
            let current = description[kIOPSCurrentCapacityKey] as? Double
            let maximum = description[kIOPSMaxCapacityKey] as? Double
            if let current, let maximum, maximum > 0 {
                snapshot.batteryPercent = current / maximum * 100
            }
            snapshot.charging = (description[kIOPSIsChargingKey] as? Bool) == true
        }
        return snapshot
    }

    private static func number(after marker: String, in text: String) -> Double? {
        guard let range = text.range(of: marker) else { return nil }
        let digits = text[range.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }
}
