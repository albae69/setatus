import Foundation
import Darwin

enum Metrics {
    private static var prev: (user: Double, sys: Double, idle: Double, nice: Double)?

    static func cpuPercent() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        let now = (
            user: Double(info.cpu_ticks.0),
            sys: Double(info.cpu_ticks.1),
            idle: Double(info.cpu_ticks.2),
            nice: Double(info.cpu_ticks.3)
        )
        defer { prev = now }
        guard let p = prev else { return 0 }

        let busy = (now.user - p.user) + (now.sys - p.sys) + (now.nice - p.nice)
        let total = busy + (now.idle - p.idle)
        guard total > 0 else { return 0 }
        return max(0, min(100, busy / total * 100))
    }

    static func ram() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, ProcessInfo.processInfo.physicalMemory) }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * ps
        return (used, ProcessInfo.processInfo.physicalMemory)
    }

    /// Wall-clock time since boot, including time spent asleep.
    static func uptime() -> TimeInterval {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, u_int(mib.count), &boottime, &size, nil, 0) == 0 else { return 0 }
        let booted = TimeInterval(boottime.tv_sec) + TimeInterval(boottime.tv_usec) / 1_000_000
        return max(0, Date().timeIntervalSince1970 - booted)
    }
}
