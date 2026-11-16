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
        return runAdmin(script)
    }

    /// Runs a shell script as root through one authorization prompt; blocks until it finishes.
    private static func runAdmin(_ script: String) -> Bool {
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
        return process.terminationStatus == 0 && installed
    }

    /// Single-quote for the admin shell script; paths may contain quotes or spaces.
    private static func quoted(_ value: String) -> String {
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
        let expectedDirectory = URL(fileURLWithPath: home)
            .appendingPathComponent(".config/setatus")
            .resolvingSymlinksInPath()
        var engaged = false
        var hardwareEngaged = false
        var announcedRPM = -1
        var lastModeCheck = Date.distantPast

        while true {
            if stopping.withLock({ $0 }) {
                log("exit: signal", home: home)
                restore(smc)
                exit(0)
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

            usleep(1_000_000)
        }
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
