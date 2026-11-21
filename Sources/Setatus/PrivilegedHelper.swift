import Foundation

enum PrivilegedHelper {
    /// Installs the root helper when it is missing or stale. The check hashes the app
    /// binary and spawns pgrep, so it stays off the main actor with the install itself.
    static func ensureInstalled() async -> Bool {
        await Task.detached {
            if FanControl.installed, FanControl.helperRunning() { return true }
            return FanControl.install()
        }.value
    }
}
