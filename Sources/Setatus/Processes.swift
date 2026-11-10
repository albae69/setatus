import Foundation
import Darwin

struct ProcessRow: Identifiable {
    let pid: Int32
    let name: String
    let cpu: Double
    let memoryMB: Double

    var id: Int32 { pid }
}

enum Processes {
    static func top(limit: Int = 8) -> [ProcessRow] {
        guard let output = Shell.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="]) else { return [] }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var rows: [ProcessRow] = []

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  pid != selfPID,
                  let cpu = Double(fields[1]),
                  let rss = Double(fields[2]) else { continue }
            let path = String(fields[3])
            let name = (path as NSString).lastPathComponent
            rows.append(ProcessRow(pid: pid, name: name, cpu: cpu, memoryMB: rss / 1024))
        }

        return Array(rows.sorted { $0.cpu > $1.cpu }.prefix(limit))
    }

    static func kill(_ pid: Int32) -> Bool {
        Darwin.kill(pid, SIGTERM) == 0
    }
}
