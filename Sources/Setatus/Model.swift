import Foundation
import SwiftUI

/// Composition root: owns the stores, runs the refresh timers, and answers the menu
/// bar queries the AppDelegate and menu make.
@MainActor
final class Model: ObservableObject {
    let metricsStore = MetricsStore()
    let fan: FanController
    let charge = ChargeController()
    let processes = ProcessMonitor()
    let ports = PortMonitor()
    let usage = UsageStore()

    @Published private(set) var prefs: MenuBarPrefs

    private var usageTimer: Timer?
    private var processTimer: Timer?
    private var started = false

    init() {
        fan = FanController(metrics: metricsStore)
        prefs = MenuBarPrefs()
    }

    var shownMetrics: Set<MenuMetric> { prefs.metrics }

    func detail(_ metric: MenuMetric) -> MetricDetail { prefs.detail(for: metric) }

    func setDetail(_ detail: MetricDetail, for metric: MenuMetric) {
        prefs.setDetail(detail, for: metric)
    }

    func resetMenuMetrics() {
        prefs.reset()
    }

    func toggleMetric(_ metric: MenuMetric) {
        prefs.toggle(metric)
    }

    var menuTitle: String {
        MenuBarTitle.text(metrics: prefs.metrics, details: prefs.details, snapshot: menuBarSnapshot)
    }

    private var menuBarSnapshot: MenuBarSnapshot {
        MenuBarSnapshot(cpu: metricsStore.cpu,
                        ramPercent: metricsStore.ramPercent,
                        gpuUsage: metricsStore.gpuUsage,
                        fanActual: metricsStore.fans.first?.actual,
                        netDown: metricsStore.netDown,
                        netUp: metricsStore.netUp,
                        powerWatts: metricsStore.power?.inputWatts,
                        limitPercent: usage.data.value?.rolling.percent,
                        temperatures: metricsStore.temps)
    }

    func start() {
        guard !started else { return }
        started = true
        metricsStore.start { [weak self] in
            guard let self else { return }
            await self.charge.sync()
            await self.fan.sync()
        }
        charge.rearmIfNeeded()
        Task { await usage.refresh() }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.usage.refresh() }
        }
        processes.refresh()
        processTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.processes.refresh() }
        }
    }
}
