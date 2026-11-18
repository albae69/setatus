import SwiftUI
import AppKit

@main
struct SetatusApp {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(where: { $0 == "--fan-daemon" || $0 == "--fan-hold" }),
           index + 1 < CommandLine.arguments.count {
            FanControl.hold(home: CommandLine.arguments[index + 1])
        }
        if CommandLine.arguments.contains("--selfcheck") || CommandLine.arguments.contains("--speedtest")
            || CommandLine.arguments.contains("--smc") || CommandLine.arguments.contains("--charge")
            || CommandLine.arguments.contains("--charge-write") {
            SelfCheck.run()
        }
        if let other = duplicateInstance() {
            other.activate(options: [.activateIgnoringOtherApps])
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// ponytail: compares resolved executable paths; add a lock file if the bundle can be copied around.
    private static func duplicateInstance() -> NSRunningApplication? {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != me && $0.executableURL?.resolvingSymlinksInPath().path == path
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = Model()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var titleTimer: Timer?
    private var uninstalling = false
    private var iconOnly = false
    private var lastRestoreAttempt = Date.distantPast
    private var titleOverhead: CGFloat = 0
    private lazy var menu = buildMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = Self.menuFont
        }
        updateTitle()

        let hosting = NSHostingController(rootView: PanelView().environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.contentSize = hosting.view.fittingSize

        titleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }

        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restoring writes fan.json, which would recreate the config we just deleted.
        if !uninstalling { model.restoreFan() }
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        // Resizing the status item while its popover is open dismisses the popover.
        guard !popover.isShown else { return }
        let title = model.menuTitle

        if iconOnly {
            button.toolTip = title
            guard Date().timeIntervalSince(lastRestoreAttempt) > 20,
                  fits(title, in: button) else { return }
            lastRestoreAttempt = Date()
            iconOnly = false
        }

        button.image = nil
        button.title = title
        button.toolTip = title

        // macOS hides status items that spill off-screen or under the notch; fall
        // back to an icon before the item disappears. There is no public visibility API.
        if isHidden(button) {
            iconOnly = true
            lastRestoreAttempt = Date()
            applyIcon(button)
            return
        }

        let textWidth = (title as NSString).size(withAttributes: [.font: button.font ?? Self.menuFont]).width
        let itemWidth = button.window?.frame.width ?? 0
        if textWidth > 0, itemWidth > textWidth {
            titleOverhead = itemWidth - textWidth
        }
    }

    private static let menuFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)

    private func applyIcon(_ button: NSStatusBarButton) {
        if let icon = NSApp.applicationIconImage?.copy() as? NSImage {
            icon.size = NSSize(width: 18, height: 18)
            button.title = ""
            button.image = icon
        } else {
            button.image = nil
            button.title = "S"
        }
        button.toolTip = model.menuTitle
    }

    private func isHidden(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return false }
        // Status item windows start unplaced (below the screen) until the menu bar lays them out.
        guard window.frame.minY >= screen.frame.midY else { return false }
        if #available(macOS 12.0, *), let right = screen.auxiliaryTopRightArea {
            // Nothing renders left of the notch: the system clips it away.
            return window.frame.minX < right.minX
        }
        return window.frame.minX < screen.frame.minX
    }

    private func fits(_ title: String, in button: NSStatusBarButton) -> Bool {
        guard let window = button.window, let screen = window.screen ?? NSScreen.main else { return false }
        var minX = screen.frame.minX
        if #available(macOS 12.0, *), let right = screen.auxiliaryTopRightArea {
            guard window.frame.maxX > right.minX else { return false }
            minX = right.minX
        }
        let width = (title as NSString).size(withAttributes: [.font: button.font ?? Self.menuFont]).width
        return width + titleOverhead <= window.frame.maxX - minX
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            guard let button = statusItem.button else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(item("Refresh", #selector(refreshAll), "r"))
        menu.addItem(.separator())

        let metricsItem = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
        let metricsMenu = NSMenu()
        for (index, metric) in MenuMetric.allCases.enumerated() {
            metricsMenu.addItem(metricItem(metric, index: index))
        }
        metricsMenu.addItem(.separator())
        metricsMenu.addItem(item("Reset to Defaults", #selector(resetMetrics)))
        metricsItem.submenu = metricsMenu
        menu.addItem(metricsItem)

        menu.addItem(item("Launch at Login", #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(item("About Setatus", #selector(showAbout)))
        menu.addItem(item("Uninstall Setatus…", #selector(uninstall)))
        menu.addItem(item("Quit Setatus", #selector(quit), "q"))
        return menu
    }

    /// CPU and GPU get a submenu with visibility plus percent/temperature, others stay flat.
    private func metricItem(_ metric: MenuMetric, index: Int) -> NSMenuItem {
        guard metric.hasDetail else {
            let entry = item(metric.title, #selector(toggleMetric(_:)))
            entry.representedObject = metric.rawValue
            return entry
        }

        let entry = NSMenuItem(title: metric.title, action: nil, keyEquivalent: "")
        entry.representedObject = metric.rawValue
        let submenu = NSMenu()

        let show = item("Show in menu bar", #selector(toggleMetric(_:)))
        show.representedObject = metric.rawValue
        submenu.addItem(show)
        submenu.addItem(.separator())

        for detail in MetricDetail.allCases {
            let option = item(detail.title, #selector(selectDetail(_:)))
            option.representedObject = detail.rawValue
            option.tag = index
            submenu.addItem(option)
        }
        entry.submenu = submenu
        return entry
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let metricsMenu = menu.items.first(where: { $0.submenu != nil })?.submenu {
            for entry in metricsMenu.items {
                guard let raw = entry.representedObject as? String,
                      let metric = MenuMetric(rawValue: raw) else { continue }
                let visible = model.metrics.contains(metric)
                let locked = visible && model.metrics.count == 1

                if let submenu = entry.submenu {
                    entry.state = visible ? .on : .off
                    for option in submenu.items where option.action == #selector(toggleMetric(_:)) {
                        option.state = visible ? .on : .off
                        option.isEnabled = !locked
                    }
                    for option in submenu.items where option.action == #selector(selectDetail(_:)) {
                        let detail = MetricDetail(rawValue: option.representedObject as? String ?? "")
                        option.state = detail == model.detail(metric) ? .on : .off
                        option.isEnabled = visible
                    }
                } else {
                    entry.state = visible ? .on : .off
                    entry.isEnabled = !locked
                }
            }
        }
        menu.items.first { $0.action == #selector(toggleLogin) }?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func refreshAll() {
        updateTitle()
        model.refreshProcesses()
        model.refreshPorts()
        Task { await model.refreshUsage() }
    }

    @objc private func resetMetrics() {
        model.resetMenuMetrics()
        updateTitle()
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let metric = MenuMetric(rawValue: raw) else { return }
        model.toggleMetric(metric)
        updateTitle()
    }

    @objc private func selectDetail(_ sender: NSMenuItem) {
        let all = MenuMetric.allCases
        guard all.indices.contains(sender.tag),
              let detail = MetricDetail(rawValue: sender.representedObject as? String ?? "") else { return }
        model.setDetail(detail, for: all[sender.tag])
        updateTitle()
    }

    @objc private func toggleLogin() {
        if !LaunchAtLogin.set(!LaunchAtLogin.isEnabled) {
            NSSound.beep()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func uninstall() {
        let confirm = NSAlert()
        confirm.messageText = "Uninstall Setatus?"
        confirm.informativeText = "Stops the fan helper, removes its login item and config, then deletes \(Bundle.main.bundlePath). This cannot be undone."
        confirm.addButton(withTitle: "Uninstall")
        confirm.addButton(withTitle: "Cancel")
        confirm.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        // Hand the fans back to firmware now, so nothing rewrites fan.json while the
        // admin script is deleting it.
        titleTimer?.invalidate()
        model.restoreFan()

        Task { @MainActor in
            let removed = await Task.detached { FanControl.uninstall() }.value
            uninstalling = removed

            let done = NSAlert()
            done.messageText = removed ? "Setatus uninstalled" : "Uninstall failed"
            done.informativeText = removed
                ? "\(Bundle.main.bundlePath) and its helper are gone."
                : "Nothing was removed. Run Setatus from /Applications and try again; details in ~/.config/setatus/install.log."
            done.alertStyle = removed ? .informational : .warning
            done.runModal()

            guard removed else { return }
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "dev.bae.setatus")
            NSApp.terminate(nil)
        }
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "Dibuat oleh bae",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Setatus",
            .applicationVersion: version,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
