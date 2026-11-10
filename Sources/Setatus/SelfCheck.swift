import Foundation

enum SelfCheck {
    static func run() -> Never {
        if CommandLine.arguments.contains("--killtest") {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sleep")
            child.arguments = ["60"]
            try? child.run()
            let pid = child.processIdentifier
            Thread.sleep(forTimeInterval: 0.2)
            let sent = Processes.kill(pid)
            child.waitUntilExit()
            print("killtest:", sent && child.terminationReason == .uncaughtSignal ? "ok" : "failed")
        }

        print("cpu:", String(format: "%.1f%%", Metrics.cpuPercent()))
        _ = Network.sample()
        Thread.sleep(forTimeInterval: 1)
        let net = Network.sample()
        print("net:", Int(net.down), "B/s down,", Int(net.up), "B/s up")
        print("ip:", Network.localIP() ?? "n/a",
              "total:", net.totalIn, "B in,", net.totalOut, "B out")
        print("gpu:", GPU.utilization().map { String(format: "%.0f%%", $0) } ?? "n/a")
        if let power = Power.sample() {
            print("power:",
                  power.inputWatts.map { String(format: "%.2f W in", $0) } ?? "n/a",
                  power.adapterWatts.map { String(format: "%.0f W adapter", $0) } ?? "",
                  power.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "",
                  power.externalPower ? "external" : "battery")
        }
        print("fmt:", Fmt.memory(9_905_000_000), Fmt.memory(512_000_000),
              Fmt.rate(1_200_000), Fmt.rate(240_000), Fmt.watts(6.37), Fmt.watts(68))
        print("cpu:", String(format: "%.1f%%", Metrics.cpuPercent()))

        let memory = Metrics.ram()
        print("ram:", memory.used / 1_048_576, "MB /", memory.total / 1_048_576, "MB")

        if let smc = SMC() {
            let temps = smc.temperatures()
            print("temps:", temps.isEmpty ? "none" : temps.prefix(5).map { "\($0.label)=\(String(format: "%.1f", $0.celsius))" }.joined(separator: " "))
            let fans = smc.fans()
            print("fans:", fans.isEmpty ? "none" : fans.map { "F\($0.index) \(Int($0.actual))rpm min\(Int($0.minimum)) max\(Int($0.maximum)) target\(Int($0.target))" }.joined(separator: " | "))
            let keys = ["Ftst", "F0Md", "F0md", "F0Tg"].compactMap { key in
                smc.meta(key).map { "\(key)=\($0.type)/\($0.size)\($0.writable ? "w" : "r")" }
            }
            print("fan keys:", keys.joined(separator: " "))
        } else {
            print("smc: unavailable")
        }

        print("processes:", Processes.top(limit: 6).map { "\($0.name)(\($0.pid)) \(String(format: "%.1f", $0.cpu))%" }.joined(separator: ", "))

        if let key = UsageService.apiKey() {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    let usage = try await UsageService.fetchUsage(key: key)
                    print("usage:", String(format: "5h=%.0f%% week=%.0f%% month=%.0f%%", usage.rolling.percent, usage.weekly.percent, usage.monthly.percent))
                } catch {
                    print("usage: error \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait()
        } else {
            print("usage: no key")
        }

        if let today = UsageService.today() {
            print("today:", today.requests, "req,", today.promptTokens + today.completionTokens, "tok")
        }

        exit(0)
    }
}
