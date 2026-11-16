import Foundation
import Darwin

struct PortListener: Identifiable {
    let port: Int
    let pid: Int32
    let process: String

    var id: String { "\(pid):\(port)" }
}

enum Ports {
    static func scan() -> [PortListener] {
        guard let output = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]) else { return [] }
        var seen = Set<Int>()
        var rows: [PortListener] = []

        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 9,
                  let pid = Int32(fields[1]),
                  let port = fields[8].split(separator: ":").last.flatMap({ Int($0) }) else { continue }
            // Threaded runtimes report one lsof row per worker; keep the first row so the row
            // still points at a real pid that kill() can signal.
            guard seen.insert(port).inserted else { continue }
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
