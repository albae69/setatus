import Foundation
import Darwin

struct PortListener: Identifiable {
    let port: Int
    let pid: Int32
    let process: String

    var id: String { "\(pid):\(port)" }
}

enum Ports {
    /// Ports dev servers commonly squat on: Vite, Next, CRA, Django, Rails, Expo, Tauri…
    static let common: Set<Int> = [
        3000, 3001, 3002, 3100, 4200, 4321, 5000, 5001, 5173, 5174, 5175, 5500,
        5555, 6006, 7000, 7860, 8000, 8001, 8008, 8080, 8081, 8082, 8085, 8888,
        9000, 9090, 9229, 1420, 19000, 19001, 19002, 19006, 24678,
    ]

    static func scan() -> [PortListener] {
        guard let output = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) else { return [] }
        var seen = Set<String>()
        var rows: [PortListener] = []

        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9,
                  let pid = Int32(fields[1]),
                  let port = fields[8].split(separator: ":").last.flatMap({ Int($0) }),
                  common.contains(port) else { continue }
            let key = "\(pid):\(port)"
            guard seen.insert(key).inserted else { continue }
            rows.append(PortListener(port: port, pid: pid, process: String(fields[0])))
        }

        return rows.sorted { $0.port < $1.port }
    }

    static func kill(_ row: PortListener) -> Bool {
        // Same PID-reuse guard as Processes: only signal when that pid still owns the port.
        guard scan().contains(where: { $0.pid == row.pid && $0.port == row.port }) else { return false }
        return Darwin.kill(row.pid, SIGTERM) == 0
    }
}
