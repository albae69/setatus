import AppKit

/// Offers to move the bundle into /Applications when it runs from anywhere else.
enum InstallLocation {
    private static let installed = URL(fileURLWithPath: "/Applications/Setatus.app")
    private static let skipKey = "skipInstallPrompt"

    static var shouldPrompt: Bool {
        guard Bundle.main.bundleIdentifier == "dev.bae.setatus",
              Bundle.main.bundleURL.pathExtension == "app",
              !UserDefaults.standard.bool(forKey: skipKey) else { return false }

        let path = Bundle.main.bundlePath
        if path.hasPrefix("/Applications/") { return false }
        if path.contains("/.build/") { return false }
        // A translocated bundle is read-only and changes path every launch; Gatekeeper
        // expects it in /Applications anyway.
        if path.contains("/AppTranslocation/") { return false }
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--") }) { return false }
        return true
    }

    static func promptIfNeeded() {
        guard shouldPrompt else { return }

        let alert = NSAlert()
        alert.messageText = "Move Setatus to Applications?"
        alert.informativeText = "Setatus is running from \(Bundle.main.bundlePath). In Applications, "
            + "Launch at Login and the fan helper keep working across updates."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: skipKey)
        }
        if response == .alertFirstButtonReturn {
            move()
        }
    }

    private static func move() {
        let source = Bundle.main.bundleURL
        let keepLoginItem = LaunchAtLogin.isEnabled

        try? FileManager.default.removeItem(at: installed)
        // ditto keeps extended attributes and resource forks, which a plain FileManager
        // copy can drop for app bundles.
        guard Shell.run("/usr/bin/ditto", [source.path, installed.path], timeout: 60) != nil else {
            showCopyFailure()
            return
        }
        if keepLoginItem {
            LaunchAtLogin.retarget(to: installed.appendingPathComponent("Contents/MacOS/Setatus").path)
        }

        // Two copies share one bundle id, so hand off to the installed one and quit
        // instead of leaving a second status item behind.
        NSWorkspace.shared.openApplication(at: installed,
                                           configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            DispatchQueue.main.async {
                guard app != nil else {
                    showLaunchFailure()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    private static func showLaunchFailure() {
        let alert = NSAlert()
        alert.messageText = "Setatus was copied to Applications"
        alert.informativeText = "Open it from /Applications, or allow it in System Settings › "
            + "Privacy & Security if Gatekeeper blocked the launch."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func showCopyFailure() {
        let alert = NSAlert()
        alert.messageText = "Could not copy Setatus to Applications"
        alert.informativeText = "Drag Setatus.app into Applications yourself, or run Setatus "
            + "as an administrator."
        alert.addButton(withTitle: "Show Applications")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
    }
}
