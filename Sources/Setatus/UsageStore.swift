import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var data = Loadable<Usage>()
    @Published private(set) var today: TodayStats?
    @Published private(set) var updatedAt: Date?

    func refresh() async {
        // sqlite3 spawns behind the key/today lookups; keep them off the main actor.
        let key = await Task.detached { UsageService.apiKey() }.value
        guard let key else {
            data = .failed("No OpenCode API key found")
            today = nil
            return
        }
        do {
            data.succeed(try await UsageService.fetchUsage(key: key))
            today = await Task.detached { await UsageService.today() }.value
            updatedAt = Date()
        } catch UsageService.UsageError.unauthorized {
            data = .failed("API key rejected")
            today = nil
        } catch {
            data.fail("Usage request failed — showing last known values")
        }
    }
}
