import Foundation
import SwiftUI

enum MenuMetric: String, CaseIterable, Identifiable {
    case limit, cpu, gpu, ram, fan, net, power

    var id: String { rawValue }

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
    @Published var gpuUsage: Double?
    @Published var power: PowerSnapshot?
    @Published private(set) var metrics: Set<MenuMetric> = Set(MenuMetric.defaults)
    @Published var processes: [ProcessRow] = []
    @Published var killError: String?
    @Published var usage: Usage?
    @Published var today: TodayStats?
    @Published var usageError: String?
    @Published var updatedAt: Date?

    private var metricsTimer: Timer?
    private var tickPending = false
    private var processPending = false
    private var usageTimer: Timer?
    private var processTimer: Timer?
    private var started = false
    private var fanInitialized = false
    private var desiredFanRPM = 0
    private var startingHelper = false

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: MenuMetric.storageKey)
        let parsed = Set((stored ?? MenuMetric.defaults.map(\.rawValue)).compactMap(MenuMetric.init(rawValue:)))
        metrics = parsed.isEmpty ? Set(MenuMetric.defaults) : parsed
    }

    var ramPercent: Double {
        ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) * 100 : 0
    }

    var menuTitle: String {
        let parts = MenuMetric.allCases.filter { metrics.contains($0) }.map(metricTitle)
        return parts.isEmpty ? "Setatus" : parts.joined(separator: " ")
    }

    private func metricTitle(_ metric: MenuMetric) -> String {
        switch metric {
        case .limit:
            return usage.map { String(format: "%3.0f%%", $0.rolling.percent) } ?? " --%"
        case .cpu:
            return String(format: "%3.0f%%", cpu)
        case .gpu:
            return gpuUsage.map { String(format: "%3.0f%%", $0) } ?? " --%"
        case .ram:
            return String(format: "%3.0f%%", ramPercent)
        case .fan:
            return fans.first.map { String(format: "%4.0f", $0.actual) } ?? "   -"
        case .net:
            return "↓\(Fmt.pad(Fmt.rate(netDown), 4)) ↑\(Fmt.pad(Fmt.rate(netUp), 4))"
        case .power:
            return power?.inputWatts.map { Fmt.pad(Fmt.wattsCompact($0), 4) } ?? "  -W"
        }
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
        desiredFanRPM = target
        fanTarget = Double(target)
        fanMessage = "manual \(target) rpm"
        FanControl.send(fan: fan.index, rpm: target)

        let helperUp = await Task.detached { FanControl.helperRunning() }.value
        guard !startingHelper, !helperUp else { return }
        startingHelper = true
        Task {
            let started = await Task.detached { FanControl.startHelper() }.value
            guard started else {
                fanMessage = "admin cancelled"
                startingHelper = false
                return
            }
            var running = false
            for _ in 0..<80 {
                let up = await Task.detached { FanControl.helperRunning() }.value
                if up {
                    running = true
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            startingHelper = false
            fanRunning = running
            fanMessage = running ? "manual \(target) rpm" : "helper failed — see ~/.config/setatus/helper.log"
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
        let work = Task.detached { Processes.top(limit: 6) }
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

    func refreshUsage() async {
        // sqlite3 spawns behind the key/today lookups; keep them off the main actor.
        let key = await Task.detached { UsageService.apiKey() }.value
        guard let key else {
            usage = nil
            today = nil
            usageError = "No opencode-go key found"
            return
        }
        do {
            usage = try await UsageService.fetchUsage(key: key)
            today = await Task.detached { UsageService.today() }.value
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
