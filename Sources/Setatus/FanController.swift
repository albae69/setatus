import Foundation

@MainActor
final class FanController: ObservableObject {
    @Published var target: Double = 0
    @Published var editing = false
    @Published private(set) var running = false
    @Published private(set) var message: String?

    private unowned let metrics: MetricsStore
    private var initialized = false
    private var desiredRPM = 0

    init(metrics: MetricsStore) {
        self.metrics = metrics
    }

    /// Runs after every sample: seeds the slider once, then keeps the helper alive.
    func sync() async {
        if !initialized, let fan = metrics.fans.first {
            target = fan.target > 0 ? fan.target : max(fan.actual, fan.minimum)
            initialized = true
        }
        if !editing, desiredRPM == 0, let fan = metrics.fans.first {
            target = fan.actual > 0 ? fan.actual : fan.minimum
        }
        await heartbeat()
    }

    private func heartbeat() async {
        guard desiredRPM > 0 else { return }
        if let fan = metrics.fans.first {
            FanControl.send(fan: fan.index, rpm: desiredRPM)
        }
        let alive = await Task.detached { FanControl.helperRunning() }.value
        if alive != running {
            running = alive
            message = alive ? "manual \(desiredRPM) rpm" : "manual control lost"
        }
    }

    func apply(_ rpm: Int) async {
        guard let fan = metrics.fans.first else { return }
        if rpm <= 0 {
            desiredRPM = 0
            running = false
            message = "auto"
            FanControl.send(fan: fan.index, rpm: 0)
            target = fan.actual > 0 ? fan.actual : fan.minimum
            return
        }

        let clamped = Int(min(max(Double(rpm), fan.minimum), fan.maximum))
        guard await PrivilegedHelper.ensureInstalled() else {
            desiredRPM = 0
            running = false
            message = "fan helper install cancelled"
            return
        }

        desiredRPM = clamped
        target = Double(clamped)
        message = "manual \(clamped) rpm"
        FanControl.send(fan: fan.index, rpm: clamped)

        var alive = false
        for _ in 0..<40 {
            if await Task.detached(operation: { FanControl.helperRunning() }).value {
                alive = true
                break
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        running = alive
        if !alive {
            message = "helper failed — see ~/.config/setatus/helper.log"
        }
    }

    func restore() {
        desiredRPM = 0
        running = false
        if let fan = metrics.fans.first {
            FanControl.send(fan: fan.index, rpm: 0)
        }
    }
}
