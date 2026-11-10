import Foundation

enum SelfCheck {
    static func run() -> Never {
        if CommandLine.arguments.contains("--logintest") {
            print("logintest: install=\(LaunchAtLogin.set(true)) enabled=\(LaunchAtLogin.isEnabled)")
            print("logintest: plist=\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/LaunchAgents/dev.bae.setatus.plist")
            print("logintest: uninstall=\(LaunchAtLogin.set(false)) enabled=\(LaunchAtLogin.isEnabled)")
            exit(0)
        }

        if CommandLine.arguments.contains("--shelltest") {
            // 200 KB output: a pipe-buffer deadlock here would hang forever.
            let data = Shell.run("/bin/sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' x"])
            print("shelltest: big output", data?.count == 200_000 ? "ok" : "failed (\(data?.count ?? -1) bytes)")

            // A child that never exits must be dropped, not waited on.
            let started = Date()
            let hung = Shell.run("/bin/sh", ["-c", "sleep 30"], timeout: 0.3)
            let took = Date().timeIntervalSince(started)
            print("shelltest: timeout", hung == nil && took < 5 ? "ok (\(String(format: "%.2f", took))s)" : "failed")
            exit(0)
        }

        if CommandLine.arguments.contains("--menutest") {
            MainActor.assumeIsolated {
                let defaults = UserDefaults.standard
                let saved = defaults.dictionary(forKey: "menuDetails")
                let model = Model()
                model.temps = [("CPU", 61.4), ("GPU", 47.6)]

                model.setDetail(.temperature, for: .cpu)
                let cpuTemp = model.menuTitle.contains("61°")
                let tagged = model.menuTitle.contains("OC ") && model.menuTitle.contains("CPU ")
                    && model.menuTitle.contains("GPU ")
                print("menutest: title", model.menuTitle)
                let reloaded = Model().detail(.cpu)
                model.setDetail(.percent, for: .cpu)
                let cpuPercent = !model.menuTitle.contains("°")

                model.setDetail(.temperature, for: .gpu)
                let gpuTemp = model.menuTitle.contains("48°")
                model.setDetail(.percent, for: .gpu)

                // No sensor for the group: stay on percent instead of printing a blank degree.
                model.temps = []
                model.setDetail(.temperature, for: .cpu)
                let fallback = !model.menuTitle.contains("°") && cpuPercent

                if let saved { defaults.set(saved, forKey: "menuDetails") }
                else { defaults.removeObject(forKey: "menuDetails") }

                let ok = cpuTemp && cpuPercent && gpuTemp && fallback && tagged && reloaded == .temperature
                print("menutest:", ok ? "ok" : "failed cpu=\(cpuTemp) pct=\(cpuPercent) gpu=\(gpuTemp) fallback=\(fallback) tags=\(tagged) persisted=\(reloaded)")
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--killtest") {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sleep")
            child.arguments = ["60"]
            try? child.run()
            let pid = child.processIdentifier
            Thread.sleep(forTimeInterval: 0.2)
            let row = ProcessRow(pid: pid, name: "sleep", cpu: 0, memoryMB: 0,
                                 elapsed: Processes.elapsed(pid) ?? 0, listedAt: Date())
            let sent = Processes.kill(row)
            child.waitUntilExit()
            print("killtest:", sent && child.terminationReason == .uncaughtSignal ? "ok" : "failed")

            // A row listed a minute ago cannot match a process that just started:
            // refusing here is what keeps a recycled PID from being signalled.
            let other = Process()
            other.executableURL = URL(fileURLWithPath: "/bin/sleep")
            other.arguments = ["60"]
            try? other.run()
            Thread.sleep(forTimeInterval: 0.2)
            let stale = ProcessRow(pid: other.processIdentifier, name: "sleep", cpu: 0, memoryMB: 0,
                                   elapsed: 0, listedAt: Date().addingTimeInterval(-60))
            let refused = !Processes.kill(stale)
            kill(other.processIdentifier, SIGKILL)
            other.waitUntilExit()
            print("killtest: reused pid", refused ? "ok" : "failed")
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
        print("uptime:", Fmt.duration(Metrics.uptime()), "(\(Int(Metrics.uptime()))s)")

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
