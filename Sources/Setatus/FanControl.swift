import Foundation
import Darwin
import CryptoKit
import os

struct FanRequest: Codable {
    var fan: Int
    var rpm: Int
    var updated: TimeInterval
}

enum FanControl {
    static let staleAfter: TimeInterval = 30

    private static let daemonLabel = "dev.bae.setatus.fanhelper"
    private static let helperPath = "/Library/PrivilegedHelperTools/\(daemonLabel)"
    private static let plistPath = "/Library/LaunchDaemons/\(daemonLabel).plist"

    /// Installed and running this app build: an update copies the new binary in with one prompt.
    static var installed: Bool {
        guard FileManager.default.fileExists(atPath: plistPath),
              let executable = Bundle.main.executablePath,
              let appHash = hash(executable),
              let helperHash = hash(helperPath) else { return false }
        return appHash == helperHash
    }

    private static func hash(_ path: String) -> SHA256Digest? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return SHA256.hash(data: data)
    }

    static func requestURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/setatus/fan.json")
    }

    static func send(fan: Int, rpm: Int, home: String = NSHomeDirectory()) {
        let request = FanRequest(fan: fan, rpm: max(0, rpm), updated: Date().timeIntervalSince1970)
        let url = requestURL(home: home)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(request) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func helperRunning() -> Bool {
        guard let output = Shell.run("/usr/bin/pgrep", ["-f", "--", "--fan-daemon"]) else { return false }
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One admin prompt ever: the app binary and a launchd job are installed root-owned,
    /// so later fan changes just write fan.json and the daemon picks it up.
    static func install(home: String = NSHomeDirectory()) -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(daemonLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(helperPath)</string>
            <string>--fan-daemon</string>
            <string>\(home)</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>ThrottleInterval</key><integer>5</integer>
        </dict>
        </plist>
        """
        guard let encoded = plist.data(using: .utf8)?.base64EncodedString() else { return false }

        let script = """
        set -e
        mkdir -p /Library/PrivilegedHelperTools
        launchctl bootout system/\(daemonLabel) 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f -- --fan-daemon >/dev/null || break; sleep 0.5; done
        cp \(quoted(executable)) \(quoted(helperPath))
        chown root:wheel \(quoted(helperPath))
        chmod 755 \(quoted(helperPath))
        echo \(encoded) | /usr/bin/base64 -D > \(quoted(plistPath))
        chown root:wheel \(quoted(plistPath))
        chmod 644 \(quoted(plistPath))
        launchctl bootstrap system \(quoted(plistPath)) || { sleep 1; launchctl bootstrap system \(quoted(plistPath)); }
        launchctl enable system/\(daemonLabel)
        launchctl kickstart -k system/\(daemonLabel)
        """
        return runAdmin(script) && installed
    }

    /// Removes the helper, login item, config and the app itself in one admin prompt.
    static func uninstall(home: String = NSHomeDirectory()) -> Bool {
        let app = Bundle.main.bundlePath
        // Never delete a copy running out of a build directory.
        guard app.hasPrefix("/Applications/") else { return false }
        let script = """
        launchctl bootout system/\(daemonLabel) 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -f -- --fan-daemon >/dev/null || break; sleep 0.5; done
        rm -f \(quoted(plistPath))
        rm -f \(quoted(helperPath))
        rm -f \(quoted(LaunchAtLogin.plistURL.path))
        rm -rf \(quoted(requestURL(home: home).deletingLastPathComponent().path))
        rm -rf \(quoted(app))
        """
        return runAdmin(script) && !FileManager.default.fileExists(atPath: app)
    }

    /// Runs a shell script as root through one authorization prompt; blocks until it finishes.
    static func runAdmin(_ script: String) -> Bool {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "; ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let logURL = requestURL().deletingLastPathComponent().appendingPathComponent("install.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        process.standardError = logHandle ?? FileHandle.nullDevice
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Single-quote for the admin shell script; paths may contain quotes or spaces.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Privileged helper

    static func hold(home: String) -> Never {
        let daemon = CommandLine.arguments.contains("--fan-daemon")
        log("start euid=\(geteuid()) daemon=\(daemon)", home: home)
        guard geteuid() == 0, let smc = SMC() else {
            log("exit: not root or SMC unavailable", home: home)
            exit(2)
        }

        let stopping = OSAllocatedUnfairLock(initialState: false)
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { stopping.withLock { $0 = true } }
            source.resume()
            sources.append(source)
        }

        let url = requestURL(home: home)
        let chargeURL = ChargeControl.requestURL(home: home)
        let chargeStateURL = ChargeControl.stateURL(home: home)
        let expectedDirectory = URL(fileURLWithPath: home)
            .appendingPathComponent(".config/setatus")
            .resolvingSymlinksInPath()
        var engaged = false
        var hardwareEngaged = false
        var announcedRPM = -1
        var lastModeCheck = Date.distantPast
        var chargeKey: String?
        var chargeInhibited = false
        var chargeLedGreen = false
        var ledReset = false
        var chargeReset = false
        var lastChargeWrite = Date.distantPast
        var lastChargeState: ChargeState?

        while true {
            if stopping.withLock({ $0 }) {
                log("exit: signal", home: home)
                restore(smc)
                releaseCharge(smc, key: chargeKey, inhibited: &chargeInhibited, home: home)
                if chargeLedGreen { _ = ChargeControl.setLed(smc, .system) }
                exit(0)
            }

            if chargeKey == nil {
                chargeKey = ChargeControl.keyName { smc.meta($0) != nil }
            }
            // A previous run (or another app) may have left charging inhibited; start clean
            // so the limit logic below owns the key from a known state.
            if let key = chargeKey, !chargeReset {
                ChargeControl.write(smc, key: key, inhibit: false)
                chargeReset = true
            }
            if let key = chargeKey, chargeReset {
                chargeInhibited = ChargeControl.isInhibited(smc, key: key)
            }
            // A crash can leave the ring forced green; hand it back to the system once.
            if !ledReset {
                _ = ChargeControl.setLed(smc, .system)
                ledReset = true
            }
            let chargeRequest = currentCharge(chargeURL, directory: expectedDirectory)
            let chargeLimit = chargeRequest?.limit ?? 0
            let percent = Power.batteryPercent()
            if let key = chargeKey, chargeLimit > 0, chargeLimit < 100 {
                switch ChargeControl.action(limit: chargeLimit, percent: percent ?? 0, inhibited: chargeInhibited) {
                case .inhibit:
                    if ChargeControl.write(smc, key: key, inhibit: true) {
                        chargeInhibited = true
                        log("charge: inhibit at \(Int(percent ?? 0))% limit=\(chargeLimit) key=\(key)", home: home)
                    }
                case .resume:
                    if ChargeControl.write(smc, key: key, inhibit: false) {
                        chargeInhibited = false
                        log("charge: resume at \(Int(percent ?? 0))%", home: home)
                    }
                case .none:
                    break
                }
            } else {
                releaseCharge(smc, key: chargeKey, inhibited: &chargeInhibited, home: home)
            }
            // macOS keeps the MagSafe ring amber until the battery is full, which a
            // charge limit never reaches; force green while the limit holds it paused.
            let wantsGreen = ChargeControl.ledGreen(limit: chargeLimit, inhibited: chargeInhibited)
            if wantsGreen != chargeLedGreen, ChargeControl.setLed(smc, wantsGreen ? .green : .system) {
                chargeLedGreen = wantsGreen
                log("charge: led \(wantsGreen ? "green" : "system")", home: home)
            }
            let state = ChargeState(supported: chargeKey != nil, inhibited: chargeInhibited,
                                    limit: chargeLimit, percent: percent,
                                    at: Date().timeIntervalSince1970,
                                    led: smc.meta(ChargeControl.ledKey)?.writable == true)
            let changed = lastChargeState.map {
                $0.supported != state.supported || $0.inhibited != state.inhibited
                    || $0.limit != state.limit
            } ?? true
            if changed || Date().timeIntervalSince(lastChargeWrite) > 5 {
                writeChargeState(chargeStateURL, state)
                lastChargeWrite = Date()
                lastChargeState = state
            }

            guard let request = currentRequest(smc, url: url, directory: expectedDirectory) else {
                // A daemon must outlive one bad read, a sleep or an atomic rename;
                // it only idles until the next valid request arrives.
                if hardwareEngaged {
                    log("idle: no valid request", home: home)
                    restore(smc)
                    hardwareEngaged = false
                    engaged = false
                    announcedRPM = -1
                }
                guard daemon else {
                    log("exit: no valid request", home: home)
                    exit(0)
                }
                usleep(1_000_000)
                continue
            }

            if !engaged {
                engaged = engage(smc, fan: request.fan)
                hardwareEngaged = engaged
                log("engage fan=\(request.fan) -> \(engaged)", home: home)
            }

            if engaged, Date().timeIntervalSince(lastModeCheck) > 3 {
                lastModeCheck = Date()
                if let key = modeKey(smc, fan: request.fan), smc.readUInt8(key) != 1 {
                    engaged = false
                    hardwareEngaged = false
                }
            }

            if engaged {
                let target = clamp(smc: smc, fan: request.fan, rpm: request.rpm)
                if target != announcedRPM {
                    // 0x87 (size mismatch) is returned by firmware on some Macs even though the value applies.
                    let result = smc.writeFloat("F\(request.fan)Tg", Float(target))
                    if result == nil || result == 0 || result == 0x87 {
                        announcedRPM = target
                        log("target fan=\(request.fan) rpm=\(target)", home: home)
                    } else {
                        engaged = false
                    }
                }
            }

        }
    }

    private static func currentCharge(_ url: URL, directory: URL) -> ChargeRequest? {
        let now = Date().timeIntervalSince1970
        guard let data = safeContents(url, directory: directory),
              let request = try? JSONDecoder().decode(ChargeRequest.self, from: data),
              now - request.updated < staleAfter else { return nil }
        return request
    }

    private static func releaseCharge(_ smc: SMC, key: String?, inhibited: inout Bool, home: String) {
        guard let key, ChargeControl.isInhibited(smc, key: key) else {
            inhibited = false
            return
        }
        if ChargeControl.write(smc, key: key, inhibit: false) {
            inhibited = false
            log("charge: released", home: home)
        }
    }

    private static func writeChargeState(_ url: URL, _ state: ChargeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The current request, only when fresh and pointing at a fan this Mac has.
    private static func currentRequest(_ smc: SMC, url: URL, directory: URL) -> FanRequest? {
        let now = Date().timeIntervalSince1970
        guard let data = safeContents(url, directory: directory),
              let request = try? JSONDecoder().decode(FanRequest.self, from: data),
              now - request.updated < staleAfter,
              request.rpm > 0,
              validFan(smc, request.fan) else { return nil }
        return request
    }

    private static func log(_ message: String, home: String) {
        let url = URL(fileURLWithPath: home).appendingPathComponent(".config/setatus/helper.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    private static func validFan(_ smc: SMC, _ index: Int) -> Bool {
        index >= 0 && index < 4 && smc.meta("F\(index)Ac") != nil
    }

    /// The root helper only trusts a regular file in the expected directory: it opens
    /// the path without following symlinks and checks the *opened* descriptor, so the
    /// file cannot be swapped for a link between the check and the read.
    private static func safeContents(_ url: URL, directory: URL) -> Data? {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath() == directory else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var status = stat()
        guard fstat(fd, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_size <= 64 * 1024 else { return nil }
        return try? FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd()
    }

    private static func engage(_ smc: SMC, fan: Int) -> Bool {
        if let key = modeKey(smc, fan: fan), smc.readUInt8(key) == 1 { return true }

        _ = smc.writeUInt8("Ftst", 1)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let key = modeKey(smc, fan: fan), smc.writeUInt8(key, 1) == 0 {
                return true
            }
            usleep(100_000)
        }
        return modeKey(smc, fan: fan).flatMap { smc.readUInt8($0) } == 1
    }

    private static func restore(_ smc: SMC) {
        for fan in 0..<4 {
            if let key = modeKey(smc, fan: fan), smc.readUInt8(key) == 1 {
                _ = smc.writeUInt8(key, 0)
            }
        }
        if smc.readUInt8("Ftst") == 1 {
            _ = smc.writeUInt8("Ftst", 0)
        }
    }

    private static func modeKey(_ smc: SMC, fan: Int) -> String? {
        for key in ["F\(fan)Md", "F\(fan)md"] where smc.meta(key) != nil {
            return key
        }
        return nil
    }

    private static func clamp(smc: SMC, fan: Int, rpm: Int) -> Int {
        let minimum = smc.readFloat("F\(fan)Mn") ?? 0
        let maximum = smc.readFloat("F\(fan)Mx") ?? 0
        guard maximum > minimum, maximum > 0 else { return rpm }
        return Int(min(max(Double(rpm), minimum), maximum))
    }
}
