import Foundation

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published private(set) var rows = Loadable<[ProcessRow]>(value: [])

    private let limit: Int
    private var pending = false

    init(limit: Int = 20) {
        self.limit = limit
    }

    func refresh() {
        guard !pending else { return }
        pending = true
        let work = Task.detached { [limit] in Processes.top(limit: limit) }
        Task { [weak self] in
            let rows = await work.value
            self?.rows.succeed(rows)
            self?.pending = false
        }
    }

    func kill(_ row: ProcessRow) async {
        let sent = await Task.detached { Processes.kill(row) }.value
        if sent {
            rows.clearError()
            try? await Task.sleep(nanoseconds: 300_000_000)
        } else {
            rows.fail("Cannot kill \(row.name) (pid \(row.pid)) — process changed or permission denied")
        }
        refresh()
    }
}
