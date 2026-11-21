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
            || CommandLine.arguments.contains("--charge-write") || CommandLine.arguments.contains("--ledtest") {
            SelfCheck.run()
        }
        if let other = duplicateInstance(), !CommandLine.arguments.contains("--icontest") {
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
    private var iconTestFillers: [NSStatusItem] = []
    private static let iconTest = CommandLine.arguments.contains("--icontest")
    private lazy var menu = buildMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Runs first so the offer is the first thing a new user sees; moving hands off
        // to the installed copy and terminates this one.
        InstallLocation.promptIfNeeded()
        model.start()

        if Self.iconTest { fillBarForIconTest() }
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
        if Self.iconTest { runIconTest() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restoring writes fan.json, which would recreate the config we just deleted.
        if !uninstalling { model.fan.restore() }
    }

    private var statusTitle: String {
        Self.iconTest ? "SETATUS TEST" : model.menuTitle
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        // Resizing the status item while its popover is open dismisses the popover.
        guard !popover.isShown else { return }
        let title = statusTitle

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

    private static func bundleIcon() -> NSImage? {
        // NSApp.applicationIconImage comes from the LaunchServices cache, which can
        // outlive an icon swap; read the bundle file so About always shows the current one.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage
    }

    private func applyIcon(_ button: NSStatusBarButton) {
        if let icon = Self.bundleIcon()?.copy() as? NSImage {
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
            minX = right.minX
        }
        let width = (title as NSString).size(withAttributes: [.font: button.font ?? Self.menuFont]).width
        return Self.titleFits(width: width, overhead: titleOverhead,
                              itemMaxX: window.frame.maxX, usableMinX: minX)
    }

    /// A status item grows leftward from its right edge, so a title fits when it still
    /// clears the usable left edge; the notch clips anything to its left.
    static func titleFits(width: CGFloat, overhead: CGFloat, itemMaxX: CGFloat, usableMinX: CGFloat) -> Bool {
        guard itemMaxX > usableMinX else { return false }
        return width + overhead <= itemMaxX - usableMinX
    }

    /// Fillers created before the status item sit to its right, so a full bar pushes
    /// the app's item under the notch; removing them gives the space back.
    private func fillBarForIconTest() {
        for index in 0..<16 {
            let filler = NSStatusBar.system.statusItem(withLength: 120)
            filler.button?.title = "F\(index)"
            iconTestFillers.append(filler)
        }
    }

    private func runIconTest() {
        let cases: [(CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [
            (100, 10, 1200, 848, true),
            (100, 10, 900, 848, false),
            (42, 10, 900, 848, true),
            (52, 0, 900, 848, true),
            (52, 1, 900, 848, false),
            (100, 10, 848, 848, false),
            (100, 10, 800, 900, false),
        ]
        let fitsOK = cases.allSatisfy { width, overhead, maxX, minX, expected in
            Self.titleFits(width: width, overhead: overhead, itemMaxX: maxX, usableMinX: minX) == expected
        }
        print("icontest: fits", fitsOK ? "ok" : "failed")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            checkIconCollapse(attempt: 0, fitsOK: fitsOK)
        }
    }

    private func checkIconCollapse(attempt: Int, fitsOK: Bool) {
        guard let button = statusItem.button else {
            print("icontest: failed, no status button")
            exit(1)
        }
        updateTitle()
        let collapsed = iconOnly && button.image != nil && button.title.isEmpty
        if !collapsed, attempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                checkIconCollapse(attempt: attempt + 1, fitsOK: fitsOK)
            }
            return
        }
        let tooltip = button.toolTip?.isEmpty == false
        for filler in iconTestFillers { NSStatusBar.system.removeStatusItem(filler) }
        iconTestFillers.removeAll()
        restoreAfterIconTest(attempt: 0, fitsOK: fitsOK, collapsed: collapsed, tooltip: tooltip)
    }

    private func restoreAfterIconTest(attempt: Int, fitsOK: Bool, collapsed: Bool, tooltip: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard let button = statusItem.button else {
                print("icontest: failed, no status button")
                exit(1)
            }
            lastRestoreAttempt = .distantPast
            updateTitle()
            let restored = !iconOnly && button.image == nil && !button.title.isEmpty
            if !restored, attempt < 4 {
                restoreAfterIconTest(attempt: attempt + 1, fitsOK: fitsOK, collapsed: collapsed, tooltip: tooltip)
                return
            }
            let ok = fitsOK && collapsed && tooltip && restored
            print("icontest:", ok ? "ok" : "failed",
                  "fits=\(fitsOK) collapsed=\(collapsed) tooltip=\(tooltip) restored=\(restored)")
            exit(ok ? 0 : 1)
        }
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

    private var observesPopoverWindow = false

    private func observePopoverWindow(_ window: NSWindow) {
        guard !observesPopoverWindow else { return }
        observesPopoverWindow = true
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(popoverWindowMoved(_:)),
                                                   name: name, object: window)
        }
    }

    @objc private func popoverWindowMoved(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        keepBelowMenuBar(window)
    }

    /// AppKit anchors a status item popover to the item's drawn frame; on a tall menu
    /// bar that leaves the arrow inside the bar, so pull the window back under it.
    private func keepBelowMenuBar(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let overflow = window.frame.maxY - screen.visibleFrame.maxY
        guard overflow > 0 else { return }
        var frame = window.frame
        frame.origin.y -= overflow
        window.setFrame(frame, display: true)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // One-point rect: a full-bounds anchor lets AppKit re-anchor to the button's far
            // edge when the popover resizes, which lands it near the screen centre.
            popover.show(relativeTo: NSRect(x: button.bounds.midX, y: button.bounds.minY, width: 1, height: 1),
                         of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                keepBelowMenuBar(window)
                observePopoverWindow(window)
            }
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(item("Refresh", #selector(refreshAll), "r"))
        menu.addItem(item("Set API Key…", #selector(setAPIKey)))
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
                let visible = model.shownMetrics.contains(metric)
                let locked = visible && model.shownMetrics.count == 1

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
        model.processes.refresh()
        model.ports.refresh()
        Task { await model.usage.refresh() }
    }

    @objc private func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Set API key"
        alert.informativeText = "Used for the OpenCode usage limits. Empty falls back to 9router's key."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "oc_sk_…"
        field.stringValue = UserDefaults.standard.string(forKey: UsageService.keyOverrideDefaultsKey) ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                  forKey: UsageService.keyOverrideDefaultsKey)
        Task { await model.usage.refresh() }
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
        model.fan.restore()

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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.6.0"
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Setatus",
            .applicationVersion: version,
            .credits: credits,
        ]
        if let icon = Self.bundleIcon() {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }
}
