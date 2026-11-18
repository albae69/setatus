import Foundation

enum SelfCheck {
    static func run() -> Never {
        if CommandLine.arguments.contains("--logintest") {
            print("logintest: install=\(LaunchAtLogin.set(true)) enabled=\(LaunchAtLogin.isEnabled)")
            print("logintest: plist=\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/LaunchAgents/dev.bae.setatus.plist")
            print("logintest: uninstall=\(LaunchAtLogin.set(false)) enabled=\(LaunchAtLogin.isEnabled)")
            exit(0)
        }

        if CommandLine.arguments.contains("--charge") {
            let smc = SMC()
            let keys = ["CHTE", "CH0B", "CHWA"].map { "\($0)=\(smc?.meta($0) != nil ? "present" : "missing")" }
            let battery = Power.batteryPercent().map { String(format: "%.0f%%", $0) } ?? "—"
            print("charge: battery=\(battery) \(keys.joined(separator: " "))")
            if let state = ChargeControl.state() {
                print("charge: state limit=\(state.limit) inhibited=\(state.inhibited) supported=\(state.supported) percent=\(state.percent.map { String(format: "%.0f", $0) } ?? "—")")
            } else {
                print("charge: state none")
            }
            let cases: [(Int, Double, Bool, ChargeControl.Action)] = [
                (80, 80, false, .inhibit), (80, 90, true, .none), (80, 78, true, .resume),
                (80, 79, true, .none), (100, 95, true, .resume), (0, 90, false, .none),
            ]
            let ok = cases.allSatisfy { ChargeControl.action(limit: $0.0, percent: $0.1, inhibited: $0.2) == $0.3 }
            print("chargetest:", ok ? "ok" : "failed")

            let keyCases: [(Set<String>, String?)] = [
                (["CHTE", "CH0B", "CHWA"], "CHTE"),
                (["CH0B", "CHWA"], "CH0B"),
                (["CHWA"], "CHWA"),
                ([], nil),
            ]
            let keysOK = keyCases.allSatisfy { set, expected in
                ChargeControl.keyName { set.contains($0) } == expected
            }
            print("chargetest keys:", keysOK ? "ok" : "failed")

            let prefixes = ["CH", "B0", "BU", "AC", "BC"]
            let names = smc?.keyNames() ?? []
            let matching = names.filter { name in
                prefixes.contains { name.hasPrefix($0) }
            }
            print("charge: smc keys total=\(smc?.keyCount ?? 0) listed=\(names.count)")
            print("charge: keys", matching.map { name in
                let meta = smc?.meta(name)
                return "\(name)(\(meta?.type ?? "?")/\(meta?.size ?? 0))"
            }.joined(separator: " "))
            if let bytes = smc?.readBytes("CHTE") {
                print("charge: CHTE bytes", bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
            }
            for key in ["CHSC", "CHCC", "CHCE"] {
                print("charge: \(key)", smc?.readUInt8(key).map(String.init) ?? "—")
            }
            if let bytes = smc?.readBytes("CHNC") {
                print("charge: CHNC bytes", bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
            }
            if let bytes = smc?.readBytes("CH0R") {
                print("charge: CH0R bytes", bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--charge-write") {
            guard let smc = SMC() else { print("smc unavailable"); exit(1) }
            for key in ["CHTE", "CH0B", "CHWA"] {
                guard let meta = smc.meta(key) else { print("\(key) missing"); continue }
                let before = smc.readUInt32(key)
                let written = ChargeControl.write(smc, key: key, inhibit: true)
                let raw = meta.type == "ui32" ? smc.writeUInt32(key, 1) : smc.writeUInt8(key, 1)
                let during = smc.readUInt32(key)
                let released = ChargeControl.write(smc, key: key, inhibit: false)
                let after = smc.readUInt32(key)
                print("\(key) type=\(meta.type) size=\(meta.size) writable=\(meta.writable) before=\(before ?? 0) inhibit=\(written) raw=\(raw.map(String.init) ?? "nil") during=\(during ?? 0) release=\(released) after=\(after ?? 0)")
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--smc") {
            guard let smc = SMC() else { print("smc unavailable"); exit(1) }
            for key in ["CHTE", "CH0B", "CHWA", "CHIE", "CHIB", "CHIC", "ACEN", "BCLM", "B0AC", "BUIC"] {
                guard let meta = smc.meta(key) else { print("\(key) missing"); continue }
                let value = meta.type == "ui8" ? smc.readUInt8(key).map { String($0) } : nil
                print("\(key) type=\(meta.type) size=\(meta.size) writable=\(meta.writable) value=\(value ?? "—")")
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--speedtest") {
            Task.detached {
                let result = await Network.speedTest()
                print("speedtest:", result.map { String(format: "↓%.1f ↑%.1f Mbps", $0.down, $0.up) } ?? "failed")
                exit(0)
            }
            dispatchMain()
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

            // Port killer: a live listener on a dev port must be found and signalled.
            let server = Process()
            server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            server.arguments = ["-m", "http.server", "24678"]
            server.standardOutput = FileHandle.nullDevice
            server.standardError = FileHandle.nullDevice
            try? server.run()
            Thread.sleep(forTimeInterval: 0.5)
            let listener = Ports.scan().first { $0.pid == server.processIdentifier }
            let sentPort = listener.map { Ports.kill($0) } ?? false
            server.waitUntilExit()
            print("killtest: port", sentPort && server.terminationReason == .uncaughtSignal ? "ok" : "failed")
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

        print("processes:", Processes.top(limit: 20).map { "\($0.name)(\($0.pid)) \(String(format: "%.0f", $0.memoryMB))MB" }.joined(separator: ", "))
        print("ports:", Ports.scan().map { ":\($0.port) \($0.process)(\($0.pid))" }.joined(separator: ", "))

        // Model breakdown: 9router's usageDaily carries byModel; missing keys must not crash.
        let sample = #"{"requests":3,"cost":0.3,"byModel":{"a|p":{"requests":2,"cost":0.25,"rawModel":"a","provider":"p"},"b|p":{"requests":1,"cost":0.05}}}"#
        if let parsed = sample.data(using: .utf8).flatMap(UsageService.parseToday) {
            let ok = parsed.models.count == 2 && parsed.models.first?.name == "a" && parsed.models.first?.cost == 0.25
            print("modeltest:", ok ? "ok" : "failed \(parsed.models.map(\.name))")
        } else {
            print("modeltest: failed to parse")
        }

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            if let key = UsageService.apiKey() {
                do {
                    let usage = try await UsageService.fetchUsage(key: key)
                    print("usage:", String(format: "5h=%.0f%% week=%.0f%% month=%.0f%%", usage.rolling.percent, usage.weekly.percent, usage.monthly.percent))
                } catch {
                    print("usage: error \(error)")
                }
            } else {
                print("usage: no key")
            }

            if let today = await UsageService.today() {
                print("today:", today.requests, "req,", today.promptTokens + today.completionTokens, "tok (in \(today.inputTokens), out \(today.outputTokens), cache \(today.cacheReadTokens)r/\(today.cacheWriteTokens)w)")
                print("models:", today.models.map {
                    "\($0.name)(\($0.requests) req, in \($0.inputTokens), out \($0.outputTokens), cache \($0.cacheReadTokens)r/\($0.cacheWriteTokens)w, $\(String(format: "%.3f", $0.cost)))"
                }.joined(separator: ", "))
            } else {
                print("today: no data")
            }
            semaphore.signal()
        }
        semaphore.wait()

        exit(0)
    }
}
