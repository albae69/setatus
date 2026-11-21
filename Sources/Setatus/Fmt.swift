import Foundation

/// Adaptive number formatting with fixed-width fields for the menu bar.
enum Fmt {
    static func pad(_ value: String, _ width: Int) -> String {
        String(repeating: " ", count: max(0, width - value.count)) + value
    }

    /// Memory: MB under 1 GB, GB with one decimal under 10 GB, whole GB above.
    static func memory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0fG", gb) }
        if gb >= 1 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(bytes) / 1_048_576)
    }

    /// Byte rate per second, compact: 1.2M.
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1000 { return "0" }
        let units = ["K", "M", "G"]
        var scaled = value / 1024
        var unit = 0
        while scaled >= 1024, unit < units.count - 1 {
            scaled /= 1024
            unit += 1
        }
        return (scaled >= 10 ? String(format: "%.0f", scaled) : String(format: "%.1f", scaled)) + units[unit]
    }

    /// Fan speed in the menu bar: 2400 rpm reads as 2.4k.
    static func fanCompact(_ rpm: Double) -> String {
        rpm >= 1000 ? String(format: "%.1fk", rpm / 1000) : String(format: "%.0f", rpm)
    }

    static func watts(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f W", value) : String(format: "%.1f W", value)
    }

    static func wattsCompact(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0fW", value) : String(format: "%.1fW", value)
    }

    /// Compact uptime: 3d 4h 12m, 4h 12m, 12m.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Reset time in words: in 2d 4h, in 3h 12m, in 41m, now.
    static func countdown(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    /// Token counts: 1.2M, 34.5k, 812.
    static func compact(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000)
            : value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000)
            : "\(value)"
    }
}
