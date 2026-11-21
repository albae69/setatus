import Foundation

@MainActor
final class ChargeController: ObservableObject {
    @Published var limit: Int
    @Published private(set) var state: ChargeState?
    @Published private(set) var message: String?

    private static let storageKey = "chargeLimit"

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.storageKey) as? Int
        limit = stored.map { min(100, max(50, $0)) } ?? 100
    }

    /// The helper treats requests older than 30 s as abandoned, so a live limit has to
    /// be re-sent while the slider is below 100.
    func sync() async {
        state = await Task.detached { ChargeControl.state() }.value
        if limit < 100 {
            ChargeControl.send(limit: limit)
        }
    }

    /// 100 means no limit. Below that the root helper holds the battery at the set percent.
    func apply(_ limit: Int) async {
        self.limit = min(100, max(50, limit))
        UserDefaults.standard.set(self.limit, forKey: Self.storageKey)
        message = nil

        // Always make sure the helper is current: an older build ignores charge.json, so a
        // limit it set earlier would never be released by turning the slider off.
        guard await PrivilegedHelper.ensureInstalled() else {
            message = "charge helper install cancelled"
            return
        }
        ChargeControl.send(limit: self.limit)
    }

    /// Re-arm a saved limit without a prompt; installing the helper stays a user action.
    func rearmIfNeeded() {
        if limit < 100, FanControl.installed, FanControl.helperRunning() {
            ChargeControl.send(limit: limit)
        }
    }
}
