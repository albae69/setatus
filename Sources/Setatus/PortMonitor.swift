import Foundation

@MainActor
final class PortMonitor: ObservableObject {
    @Published private(set) var rows = Loadable<[PortListener]>(value: [])

    private var pending = false

    func refresh() {
        guard !pending else { return }
        pending = true
        let work = Task.detached { Ports.scan() }
        Task { [weak self] in
            let rows = await work.value
            self?.rows.succeed(rows)
            self?.pending = false
        }
    }

    func kill(_ row: PortListener) async {
        let sent = await Task.detached { Ports.kill(row) }.value
        if sent {
            rows.clearError()
            try? await Task.sleep(nanoseconds: 300_000_000)
        } else {
            rows.fail("Cannot kill \(row.process) (pid \(row.pid)) — port changed or permission denied")
        }
        refresh()
    }
}
