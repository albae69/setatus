import Foundation

/// Login item via `~/Library/LaunchAgents` so it works for a locally built,
/// ad-hoc signed app without waiting for SMAppService approval.
enum LaunchAtLogin {
    private static let label = "dev.bae.setatus"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        guard let executable = Bundle.main.executablePath,
              let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = object as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String]
        else { return false }
        return arguments.first == executable
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        enabled ? install() : uninstall()
    }

    private static func install() -> Bool {
        guard let executable = Bundle.main.executablePath else { return false }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func uninstall() -> Bool {
        _ = Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
        return !FileManager.default.fileExists(atPath: plistURL.path)
    }
}
