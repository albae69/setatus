import Foundation
import Darwin

struct NetSpeed {
    let down: Double
    let up: Double
    let totalIn: UInt64
    let totalOut: UInt64
}

enum Network {
    private static var previous: (bytesIn: UInt64, bytesOut: UInt64, at: Date)?

    static func sample() -> NetSpeed {
        let counters = totals()
        let now = Date()
        defer { previous = (counters.in, counters.out, now) }
        guard let last = previous else {
            return NetSpeed(down: 0, up: 0, totalIn: counters.in, totalOut: counters.out)
        }

        let seconds = now.timeIntervalSince(last.at)
        guard seconds > 0 else {
            return NetSpeed(down: 0, up: 0, totalIn: counters.in, totalOut: counters.out)
        }

        let down = counters.in >= last.bytesIn ? Double(counters.in - last.bytesIn) / seconds : 0
        let up = counters.out >= last.bytesOut ? Double(counters.out - last.bytesOut) / seconds : 0
        return NetSpeed(down: down, up: up, totalIn: counters.in, totalOut: counters.out)
    }

    /// First non-loopback IPv4, preferring en0 (Wi-Fi/Ethernet).
    static func localIP() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = String(cString: host)
            if String(cString: pointer.pointee.ifa_name) == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }

    static func totals() -> (in: UInt64, out: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return (0, 0)
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return (0, 0)
        }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0

        buffer.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = length
            while remaining >= MemoryLayout<if_msghdr>.size {
                let header = pointer.assumingMemoryBound(to: if_msghdr.self).pointee
                let size = Int(header.ifm_msglen)
                guard size > 0, size <= remaining else { break }

                if header.ifm_type == RTM_IFINFO2, header.ifm_flags & IFF_UP != 0, header.ifm_flags & IFF_LOOPBACK == 0 {
                    let extended = pointer.assumingMemoryBound(to: if_msghdr2.self).pointee
                    bytesIn += extended.ifm_data.ifi_ibytes
                    bytesOut += extended.ifm_data.ifi_obytes
                }

                pointer += size
                remaining -= size
            }
        }

        return (bytesIn, bytesOut)
    }
}
