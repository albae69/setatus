import Foundation
import Darwin

struct ProcessRow: Identifiable {
    let pid: Int32
    let name: String
    let cpu: Double
    let memoryMB: Double
    /// Seconds the process had been running when listed, with the listing time.
    /// Together they prove the PID still belongs to the same process before signalling.
    let elapsed: Double
    let listedAt: Date

    var id: Int32 { pid }
}

enum Processes {
    static func top(limit: Int = 8) -> [ProcessRow] {
        let listedAt = Date()
        guard let output = Shell.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,etime=,comm="]) else { return [] }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var rows: [ProcessRow] = []

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5,
                  let pid = Int32(fields[0]),
                  pid != selfPID,
                  let cpu = Double(fields[1]),
                  let rss = Double(fields[2]),
                  let elapsed = seconds(String(fields[3])) else { continue }
            let name = (String(fields[4]) as NSString).lastPathComponent
            rows.append(ProcessRow(pid: pid, name: name, cpu: cpu, memoryMB: rss / 1024,
                                   elapsed: elapsed, listedAt: listedAt))
        }

        return Array(rows.sorted { $0.cpu > $1.cpu }.prefix(limit))
    }

    /// Seconds since the process started, nil when the PID is gone.
    static func elapsed(_ pid: Int32) -> Double? {
        guard let output = Shell.run("/bin/ps", ["-o", "etime=", "-p", "\(pid)"]),
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return seconds(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func kill(_ row: ProcessRow) -> Bool {
        // A PID can be recycled between listing and clicking, and SIGTERM is not
        // reversible: only signal when the elapsed time grew by the time we waited.
        let waited = Date().timeIntervalSince(row.listedAt)
        guard let now = elapsed(row.pid), abs(now - (row.elapsed + waited)) <= 2 else { return false }
        return Darwin.kill(row.pid, SIGTERM) == 0
    }

    /// macOS ps has no `etimes`, only the [[dd-]hh:]mm:ss form.
    private static func seconds(_ etime: String) -> Double? {
        var days = 0.0
        var rest = Substring(etime)
        if let dash = rest.firstIndex(of: "-") {
            guard let parsed = Double(rest[rest.startIndex..<dash]) else { return nil }
            days = parsed
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let hours = parts.count == 3 ? parts[0] : 0
        return days * 86_400 + hours * 3_600 + parts[parts.count - 2] * 60 + parts[parts.count - 1]
    }
}
