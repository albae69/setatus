import Foundation

enum MetricDetail: String, CaseIterable, Identifiable {
    case percent, temperature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percent: return "Percent"
        case .temperature: return "Temperature"
        }
    }
}

enum MenuMetric: String, CaseIterable, Identifiable {
    case limit, cpu, gpu, ram, fan, net, power

    var id: String { rawValue }

    /// Metrics that can show a sensor reading instead of a percentage.
    var hasDetail: Bool { self == .cpu || self == .gpu }

    /// Short menu bar prefix; empty where the value speaks for itself (rpm, arrows, W).
    var tag: String {
        switch self {
        case .limit: return "OC"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .fan, .net, .power: return ""
        }
    }

    var title: String {
        switch self {
        case .limit: return "OpenCode limit"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        case .fan: return "Fan speed"
        case .net: return "Internet speed"
        case .power: return "Power input"
        }
    }

    static let storageKey = "menuMetrics"
    static let defaults: [MenuMetric] = [.limit, .cpu, .gpu, .ram, .fan, .net]
}

/// Which metrics the status item shows, and in which unit, persisted across launches.
struct MenuBarPrefs {
    private static let detailsKey = "menuDetails"

    private let store: UserDefaults
    private(set) var metrics: Set<MenuMetric>
    private(set) var details: [MenuMetric: MetricDetail]

    init(store: UserDefaults = .standard) {
        self.store = store

        let stored = store.stringArray(forKey: MenuMetric.storageKey)
        let parsed = Set((stored ?? MenuMetric.defaults.map(\.rawValue)).compactMap(MenuMetric.init(rawValue:)))
        metrics = parsed.isEmpty ? Set(MenuMetric.defaults) : parsed

        let storedDetails = store.dictionary(forKey: Self.detailsKey) as? [String: String] ?? [:]
        details = storedDetails.reduce(into: [:]) { result, pair in
            guard let metric = MenuMetric(rawValue: pair.key),
                  let detail = MetricDetail(rawValue: pair.value) else { return }
            result[metric] = detail
        }
    }

    func detail(for metric: MenuMetric) -> MetricDetail {
        details[metric] ?? .percent
    }

    mutating func toggle(_ metric: MenuMetric) {
        if metrics.contains(metric) {
            guard metrics.count > 1 else { return }
            metrics.remove(metric)
        } else {
            metrics.insert(metric)
        }
        store.set(metrics.map(\.rawValue), forKey: MenuMetric.storageKey)
    }

    mutating func setDetail(_ detail: MetricDetail, for metric: MenuMetric) {
        details[metric] = detail
        store.set(details.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue },
                  forKey: Self.detailsKey)
    }

    mutating func reset() {
        metrics = Set(MenuMetric.defaults)
        details = [:]
        store.set(metrics.map(\.rawValue), forKey: MenuMetric.storageKey)
        store.removeObject(forKey: Self.detailsKey)
    }
}
