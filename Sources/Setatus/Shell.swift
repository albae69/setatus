import Foundation

private final class Box<T>: @unchecked Sendable {
    var value: T?
}

enum Shell {
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        // Drain on another queue while we wait: output larger than the 64 KiB pipe
        // buffer would otherwise block the child on write and us on waitUntilExit
        // forever. The timeout also drops children that never exit at all.
        let box = Box<Data>()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.value = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        if drained.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if drained.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return box.value.flatMap { String(data: $0, encoding: .utf8) }
    }
}
