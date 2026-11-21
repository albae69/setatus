import Foundation

struct SpeedResult: Equatable {
    let down: Double
    let up: Double
}

@MainActor
final class MetricsStore: ObservableObject {
    @Published var cpu: Double = 0
    @Published var ramUsed: UInt64 = 0
    @Published var ramTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var uptime: TimeInterval = 0
    @Published var temps: [TempReading] = []
    @Published var fans: [SMC.Fan] = []
    @Published var gpuUsage: Double?
    @Published var power: PowerSnapshot?
    @Published var netDown: Double = 0
    @Published var netUp: Double = 0
    @Published var netTotalIn: UInt64 = 0
    @Published var netTotalOut: UInt64 = 0
    @Published var localIP: String?
    @Published private(set) var speedTest: SpeedResult?
    @Published private(set) var speedTesting = false
    @Published private(set) var speedTestError: String?

    private var timer: Timer?
    private var tickPending = false
    private var afterTick: (() async -> Void)?

    var ramPercent: Double {
        ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) * 100 : 0
    }

    func runSpeedTest() async {
        guard !speedTesting else { return }
        speedTesting = true
        speedTestError = nil
        defer { speedTesting = false }

        guard let result = await Network.speedTest() else {
            speedTestError = "speed test failed"
            return
        }
        speedTest = SpeedResult(down: result.down, up: result.up)
    }

    func start(every interval: TimeInterval = 2, afterTick: @escaping () async -> Void) {
        guard timer == nil else { return }
        self.afterTick = afterTick
        Task { await tick() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    private func tick() async {
        guard !tickPending else { return }
        tickPending = true
        defer { tickPending = false }

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

        await afterTick?()
    }
}
