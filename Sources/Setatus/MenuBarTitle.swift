import Foundation

/// Everything the status item needs, so the title can be built without touching a store.
struct MenuBarSnapshot {
    var cpu: Double
    var ramPercent: Double
    var gpuUsage: Double?
    var fanActual: Double?
    var netDown: Double
    var netUp: Double
    var powerWatts: Double?
    var limitPercent: Double?
    var temperatures: [TempReading]
}

enum MenuBarTitle {
    static func text(metrics: Set<MenuMetric>, details: [MenuMetric: MetricDetail],
                     snapshot: MenuBarSnapshot) -> String {
        let parts = MenuMetric.allCases.filter { metrics.contains($0) }.map { metric in
            let value = value(for: metric, details: details, snapshot: snapshot)
            return metric.tag.isEmpty ? value : metric.tag + " " + value
        }
        return parts.isEmpty ? "Setatus" : parts.joined(separator: " ")
    }

    private static func value(for metric: MenuMetric, details: [MenuMetric: MetricDetail],
                              snapshot: MenuBarSnapshot) -> String {
        switch metric {
        case .limit:
            return snapshot.limitPercent.map { String(format: "%2.0f%%", $0) } ?? "--%"
        case .cpu:
            return reading(snapshot.cpu, label: "CPU",
                           detail: details[.cpu] ?? .percent, temperatures: snapshot.temperatures)
        case .gpu:
            return reading(snapshot.gpuUsage, label: "GPU",
                           detail: details[.gpu] ?? .percent, temperatures: snapshot.temperatures)
        case .ram:
            return String(format: "%2.0f%%", snapshot.ramPercent)
        case .fan:
            return snapshot.fanActual.map { Fmt.pad(Fmt.fanCompact($0), 4) } ?? "   -"
        case .net:
            return "↓\(Fmt.pad(Fmt.rate(snapshot.netDown), 4)) ↑\(Fmt.pad(Fmt.rate(snapshot.netUp), 4))"
        case .power:
            return snapshot.powerWatts.map { Fmt.pad(Fmt.wattsCompact($0), 4) } ?? "  -W"
        }
    }

    /// Percent, or the sensor reading for that group when the menu bar asks for it.
    /// Falls back to percent when SMC has no reading, so the item never goes blank.
    private static func reading(_ value: Double?, label: String, detail: MetricDetail,
                                temperatures: [TempReading]) -> String {
        if detail == .temperature, let celsius = temperatures.first(where: { $0.label == label })?.celsius {
            return String(format: "%2.0f°", celsius)
        }
        return value.map { String(format: "%2.0f%%", $0) } ?? "--%"
    }
}
