import Foundation

struct TempReading: Equatable {
    let label: String
    let celsius: Double
}

/// Blocking system samples (SMC, ioreg, sysctl). `smc` is created lazily on the
/// first off-main call, so the ~0.6 s key scan never touches the main thread.
enum Sampler {
    static let smc = SMC()

    struct Snapshot {
        var cpu: Double
        var ramUsed: UInt64
        var ramTotal: UInt64
        var uptime: TimeInterval
        var temps: [TempReading]
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
                        temps: smc?.temperatures().map { TempReading(label: $0.label, celsius: $0.celsius) } ?? [],
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
