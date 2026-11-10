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
    @Published var temps: [(label: String, celsius: Double)] = []
    @Published var fans: [SMC.Fan] = []
    @Published var fanTarget: Double = 0
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

    private let smc = SMC()
    private var metricsTimer: Timer?
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
        tickMetrics()
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickMetrics() }
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

    private func tickMetrics() {
        cpu = Metrics.cpuPercent()
        let memory = Metrics.ram()
        ramUsed = memory.used
        ramTotal = memory.total
        temps = smc?.temperatures() ?? []
        fans = smc?.fans() ?? []
        gpuUsage = GPU.utilization()
        power = Power.sample()
        let net = Network.sample()
        netDown = net.down
        netUp = net.up
        netTotalIn = net.totalIn
        netTotalOut = net.totalOut
        localIP = Network.localIP()

        if !fanInitialized, let fan = fans.first {
            fanTarget = fan.target > 0 ? fan.target : max(fan.actual, fan.minimum)
            fanInitialized = true
        }
        heartbeatFan()
    }

    private func heartbeatFan() {
        guard desiredFanRPM > 0 else { return }
        if let fan = fans.first {
            FanControl.send(fan: fan.index, rpm: desiredFanRPM)
        }
        let running = FanControl.helperRunning()
        if running != fanRunning {
            fanRunning = running
            fanMessage = running ? "manual \(desiredFanRPM) rpm" : "manual control lost"
        }
    }

    func applyFan(_ rpm: Int) {
        guard let fan = fans.first else { return }
        if rpm <= 0 {
            desiredFanRPM = 0
            fanRunning = false
            fanMessage = "auto"
            FanControl.send(fan: fan.index, rpm: 0)
            return
        }

        let target = Int(min(max(Double(rpm), fan.minimum), fan.maximum))
        desiredFanRPM = target
        fanMessage = "manual \(target) rpm"
        FanControl.send(fan: fan.index, rpm: target)

        guard !startingHelper, !FanControl.helperRunning() else { return }
        startingHelper = true
        Task {
            let started = await Task.detached { FanControl.startHelper() }.value
            if !started {
                fanMessage = "admin cancelled"
                startingHelper = false
                return
            }
            for _ in 0..<20 where !FanControl.helperRunning() {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            startingHelper = false
            heartbeatFan()
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
        processes = Processes.top(limit: 6)
    }

    func kill(_ row: ProcessRow) {
        if Processes.kill(row.pid) {
            killError = nil
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                refreshProcesses()
            }
        } else {
            killError = "Cannot kill \(row.name) (pid \(row.pid)) — permission denied"
            refreshProcesses()
        }
    }

    func refreshUsage() async {
        guard let key = UsageService.apiKey() else {
            usageError = "No opencode-go key found"
            return
        }
        do {
            usage = try await UsageService.fetchUsage(key: key)
            today = UsageService.today()
            usageError = nil
            updatedAt = Date()
        } catch {
            usageError = "Usage request failed"
        }
    }
}
