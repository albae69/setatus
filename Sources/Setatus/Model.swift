import Foundation
import SwiftUI

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

@MainActor
final class Model: ObservableObject {
    @Published var cpu: Double = 0
    @Published var ramUsed: UInt64 = 0
    @Published var ramTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var uptime: TimeInterval = 0
    @Published var temps: [(label: String, celsius: Double)] = []
    @Published var fans: [SMC.Fan] = []
    @Published var fanTarget: Double = 0
    @Published var fanEditing = false
    @Published var fanRunning = false
    @Published var fanMessage: String?
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0
    @Published var netTotalIn: UInt64 = 0
    @Published var netTotalOut: UInt64 = 0
    @Published var localIP: String?
    @Published var speedTest: (down: Double, up: Double)?
    @Published var speedTesting = false
    @Published var speedTestError: String?
    @Published var chargeLimit: Int = 100
    @Published var chargeState: ChargeState?
    @Published var chargeMessage: String?
    @Published var gpuUsage: Double?
    @Published var power: PowerSnapshot?
    @Published private(set) var metrics: Set<MenuMetric> = Set(MenuMetric.defaults)
    @Published private(set) var details: [MenuMetric: MetricDetail] = [:]
    @Published var processes: [ProcessRow] = []
    @Published var killError: String?
    @Published var ports: [PortListener] = []
    @Published var portError: String?
    @Published var usage: Usage?
    @Published var today: TodayStats?
    @Published var usageError: String?
    @Published var updatedAt: Date?

    private static let detailKey = "menuDetails"
    private static let chargeKey = "chargeLimit"

    private var metricsTimer: Timer?
    private var tickPending = false
    private var processPending = false
    private var portPending = false
    private var usageTimer: Timer?
    private var processTimer: Timer?
    private var started = false
    private var fanInitialized = false
    private var desiredFanRPM = 0

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: MenuMetric.storageKey)
        let parsed = Set((stored ?? MenuMetric.defaults.map(\.rawValue)).compactMap(MenuMetric.init(rawValue:)))
        metrics = parsed.isEmpty ? Set(MenuMetric.defaults) : parsed

        let storedDetails = UserDefaults.standard.dictionary(forKey: Self.detailKey) as? [String: String] ?? [:]
        details = storedDetails.reduce(into: [:]) { result, pair in
            guard let metric = MenuMetric(rawValue: pair.key),
                  let detail = MetricDetail(rawValue: pair.value) else { return }
            result[metric] = detail
        }

        let storedLimit = UserDefaults.standard.object(forKey: Self.chargeKey) as? Int
        chargeLimit = storedLimit.map { min(100, max(50, $0)) } ?? 100
    }

    var ramPercent: Double {
        ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) * 100 : 0
    }

    var menuTitle: String {
        let parts = MenuMetric.allCases.filter { metrics.contains($0) }.map(metricTitle)
        return parts.isEmpty ? "Setatus" : parts.joined(separator: " ")
    }

    private func metricTitle(_ metric: MenuMetric) -> String {
        let value = metricValue(metric)
        return metric.tag.isEmpty ? value : metric.tag + " " + value
    }

    private func metricValue(_ metric: MenuMetric) -> String {
        switch metric {
        case .limit:
            return usage.map { String(format: "%2.0f%%", $0.rolling.percent) } ?? "--%"
        case .cpu:
            return reading(cpu, label: "CPU", detail: detail(.cpu))
        case .gpu:
            return reading(gpuUsage, label: "GPU", detail: detail(.gpu))
        case .ram:
            return String(format: "%2.0f%%", ramPercent)
        case .fan:
            return fans.first.map { Fmt.pad(Fmt.fanCompact($0.actual), 4) } ?? "   -"
        case .net:
            return "↓\(Fmt.pad(Fmt.rate(netDown), 4)) ↑\(Fmt.pad(Fmt.rate(netUp), 4))"
        case .power:
            return power?.inputWatts.map { Fmt.pad(Fmt.wattsCompact($0), 4) } ?? "  -W"
        }
    }

    /// Percent, or the sensor reading for that group when the menu bar asks for it.
    /// Falls back to percent when SMC has no reading, so the item never goes blank.
    private func reading(_ value: Double?, label: String, detail: MetricDetail) -> String {
        if detail == .temperature, let celsius = temps.first(where: { $0.label == label })?.celsius {
            return String(format: "%2.0f°", celsius)
        }
        return value.map { String(format: "%2.0f%%", $0) } ?? "--%"
    }

    func detail(_ metric: MenuMetric) -> MetricDetail { details[metric] ?? .percent }

    func setDetail(_ detail: MetricDetail, for metric: MenuMetric) {
        details[metric] = detail
        UserDefaults.standard.set(details.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue },
                                  forKey: Self.detailKey)
    }

    func resetMenuMetrics() {
        metrics = Set(MenuMetric.defaults)
        details = [:]
        UserDefaults.standard.set(metrics.map(\.rawValue), forKey: MenuMetric.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.detailKey)
    }

    func toggleMetric(_ metric: MenuMetric) {
        if metrics.contains(metric) {
            guard metrics.count > 1 else { return }
            metrics.remove(metric)
        } else {
            metrics.insert(metric)
        }
        UserDefaults.standard.set(metrics.map(\.rawValue), forKey: MenuMetric.storageKey)
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await tickMetrics() }
        // Re-arm a saved limit without a prompt; installing the helper stays a user action.
        if chargeLimit < 100, FanControl.installed, FanControl.helperRunning() {
            ChargeControl.send(limit: chargeLimit)
        }
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tickMetrics() }
        }
        Task { await refreshUsage() }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshUsage() }
        }
        refreshProcesses()
        processTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshProcesses() }
        }
    }

    private func tickMetrics() async {
        guard !tickPending else { return }
        tickPending = true
        defer { tickPending = false }

        // SMC key scan alone costs ~0.6 s and ioreg spawns tens of ms; sample off-main.
        let snapshot = await Task.detached { Sampler.read() }.value

        cpu = snapshot.cpu
        ramUsed = snapshot.ramUsed
        ramTotal = snapshot.ramTotal
        uptime = snapshot.uptime
        temps = snapshot.temps
        fans = snapshot.fans
        gpuUsage = snapshot.gpuUsage
        power = snapshot.power
        netDown = snapshot.down
        netUp = snapshot.up
        netTotalIn = snapshot.totalIn
        netTotalOut = snapshot.totalOut
        localIP = snapshot.localIP
        chargeState = await Task.detached { ChargeControl.state() }.value
        // The helper treats requests older than 30 s as abandoned, so a live limit has to
        // be re-sent while the slider is below 100.
        if chargeLimit < 100 {
            ChargeControl.send(limit: chargeLimit)
        }

        if !fanInitialized, let fan = fans.first {
            fanTarget = fan.target > 0 ? fan.target : max(fan.actual, fan.minimum)
            fanInitialized = true
        }
        if !fanEditing, desiredFanRPM == 0, let fan = fans.first {
            fanTarget = fan.actual > 0 ? fan.actual : fan.minimum
        }
        await heartbeatFan()
    }

    private func heartbeatFan() async {
        guard desiredFanRPM > 0 else { return }
        if let fan = fans.first {
            FanControl.send(fan: fan.index, rpm: desiredFanRPM)
        }
        let running = await Task.detached { FanControl.helperRunning() }.value
        if running != fanRunning {
            fanRunning = running
            fanMessage = running ? "manual \(desiredFanRPM) rpm" : "manual control lost"
        }
    }

    func applyFan(_ rpm: Int) async {
        guard let fan = fans.first else { return }
        if rpm <= 0 {
            desiredFanRPM = 0
            fanRunning = false
            fanMessage = "auto"
            FanControl.send(fan: fan.index, rpm: 0)
            fanTarget = fan.actual > 0 ? fan.actual : fan.minimum
            return
        }

        let target = Int(min(max(Double(rpm), fan.minimum), fan.maximum))
        if !FanControl.installed || !FanControl.helperRunning() {
            let installed = await Task.detached { FanControl.install() }.value
            guard installed else {
                desiredFanRPM = 0
                fanRunning = false
                fanMessage = "fan helper install cancelled"
                return
            }
        }

        desiredFanRPM = target
        fanTarget = Double(target)
        fanMessage = "manual \(target) rpm"
        FanControl.send(fan: fan.index, rpm: target)

        var running = false
        for _ in 0..<40 {
            if await Task.detached(operation: { FanControl.helperRunning() }).value {
                running = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        fanRunning = running
        if !running {
            fanMessage = "helper failed — see ~/.config/setatus/helper.log"
        }
    }

    func restoreFan() {
        desiredFanRPM = 0
        fanRunning = false
        if let fan = fans.first {
            FanControl.send(fan: fan.index, rpm: 0)
        }
    }

    func refreshProcesses() {
        guard !processPending else { return }
        processPending = true
        let work = Task.detached { Processes.top(limit: 20) }
        Task { [weak self] in
            let rows = await work.value
            self?.processes = rows
            self?.processPending = false
        }
    }

    func kill(_ row: ProcessRow) async {
        let sent = await Task.detached { Processes.kill(row) }.value
        if sent {
            killError = nil
            try? await Task.sleep(nanoseconds: 300_000_000)
        } else {
            killError = "Cannot kill \(row.name) (pid \(row.pid)) — process changed or permission denied"
        }
        refreshProcesses()
    }

    /// 100 means no limit. Below that the root helper holds the battery at the set percent.
    func applyChargeLimit(_ limit: Int) async {
        chargeLimit = min(100, max(50, limit))
        UserDefaults.standard.set(chargeLimit, forKey: Self.chargeKey)
        chargeMessage = nil

        // Always make sure the helper is current: an older build ignores charge.json, so a
        // limit it set earlier would never be released by turning the slider off.
        if !FanControl.installed || !FanControl.helperRunning() {
            let installed = await Task.detached { FanControl.install() }.value
            guard installed else {
                chargeMessage = "charge helper install cancelled"
                return
            }
        }
        ChargeControl.send(limit: chargeLimit)
    }

    func runSpeedTest() async {        guard !speedTesting else { return }
        speedTesting = true
        speedTestError = nil
        defer { speedTesting = false }

        guard let result = await Network.speedTest() else {
            speedTestError = "speed test failed"
            return
        }
        speedTest = result
    }

    func refreshPorts() {        guard !portPending else { return }
        portPending = true
        let work = Task.detached { Ports.scan() }
        Task { [weak self] in
            let rows = await work.value
            self?.ports = rows
            self?.portPending = false
        }
    }

    func killPort(_ row: PortListener) async {
        let sent = await Task.detached { Ports.kill(row) }.value
        if sent {
            portError = nil
            try? await Task.sleep(nanoseconds: 300_000_000)
        } else {
            portError = "Cannot kill \(row.process) (pid \(row.pid)) — port changed or permission denied"
        }
        refreshPorts()
    }

    func refreshUsage() async {        // sqlite3 spawns behind the key/today lookups; keep them off the main actor.
        let key = await Task.detached { UsageService.apiKey() }.value
        guard let key else {
            usage = nil
            today = nil
            usageError = "No OpenCode API key found"
            return
        }
        do {
            usage = try await UsageService.fetchUsage(key: key)
            today = await Task.detached { await UsageService.today() }.value
            usageError = nil
            updatedAt = Date()
        } catch UsageService.UsageError.unauthorized {
            usage = nil
            today = nil
            usageError = "API key rejected"
        } catch {
            usageError = "Usage request failed — showing last known values"
        }
    }
}

/// Blocking system samples (SMC, ioreg, sysctl). `smc` is created lazily on the
/// first off-main call, so the ~0.6 s key scan never touches the main thread.
private enum Sampler {
    static let smc = SMC()

    struct Snapshot {
        var cpu: Double
        var ramUsed: UInt64
        var ramTotal: UInt64
        var uptime: TimeInterval
        var temps: [(label: String, celsius: Double)]
        var fans: [SMC.Fan]
        var gpuUsage: Double?
        var power: PowerSnapshot?
        var down: Double
        var up: Double
        var totalIn: UInt64
        var totalOut: UInt64
        var localIP: String?
    }

    static func read() -> Snapshot {
        let memory = Metrics.ram()
        let net = Network.sample()
        return Snapshot(cpu: Metrics.cpuPercent(),
                        ramUsed: memory.used,
                        ramTotal: memory.total,
                        uptime: Metrics.uptime(),
                        temps: smc?.temperatures() ?? [],
                        fans: smc?.fans() ?? [],
                        gpuUsage: GPU.utilization(),
                        power: Power.sample(),
                        down: net.down,
                        up: net.up,
                        totalIn: net.totalIn,
                        totalOut: net.totalOut,
                        localIP: Network.localIP())
    }
}
