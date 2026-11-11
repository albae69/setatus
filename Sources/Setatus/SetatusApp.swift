import SwiftUI
import AppKit

@main
struct SetatusApp {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--fan-hold"),
           index + 1 < CommandLine.arguments.count {
            FanControl.hold(home: CommandLine.arguments[index + 1])
        }
        if CommandLine.arguments.contains("--selfcheck") {
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
    private lazy var menu = buildMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        }
        updateTitle()

        let hosting = NSHostingController(rootView: PanelView().environmentObject(model))
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
        model.restoreFan()
    }

    private func updateTitle() {
        statusItem?.button?.title = model.menuTitle
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
        menu.addItem(item("Fan Auto", #selector(fanAuto)))
        menu.addItem(.separator())

        let metricsItem = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
        let metricsMenu = NSMenu()
        for (index, metric) in MenuMetric.allCases.enumerated() {
            metricsMenu.addItem(metricItem(metric, index: index))
        }
        metricsItem.submenu = metricsMenu
        menu.addItem(metricsItem)

        menu.addItem(item("Launch at Login", #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(item("About Setatus", #selector(showAbout)))
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
        Task { await model.refreshUsage() }
    }

    @objc private func fanAuto() {
        Task { await model.applyFan(0) }
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

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "Dibuat oleh bae",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Setatus",
            .applicationVersion: version,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
