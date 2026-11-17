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

    /// Down/up in Mbps from Cloudflare's public speed endpoint. fast.com has no
    /// unauthenticated API (its token is fetched by the site's JS), so this uses the
    /// endpoint behind speed.cloudflare.com instead.
    static func speedTest() async -> (down: Double, up: Double)? {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: config)

        func Mbps(_ bytes: Int, _ seconds: TimeInterval) -> Double {
            seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0
        }

        func download(_ bytes: Int) async -> (bytes: Int, seconds: TimeInterval)? {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return nil }
            let start = Date()
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return (data.count, Date().timeIntervalSince(start))
        }

        // 8 MB first; a slow link falls back to 2 MB so the request still finishes.
        var measured = await download(8_000_000)
        if measured == nil || measured!.seconds > 20 {
            measured = await download(2_000_000)
        }
        guard let down = measured else { return nil }

        guard let url = URL(string: "https://speed.cloudflare.com/__up") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = Data(count: 4_000_000)
        let start = Date()
        guard let (_, _) = try? await session.upload(for: request, from: body) else { return (Mbps(down.bytes, down.seconds), 0) }
        return (Mbps(down.bytes, down.seconds), Mbps(body.count, Date().timeIntervalSince(start)))
    }

    static func totals() -> (in: UInt64, out: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        // The table can grow between the size probe and the fill; retry instead of
        // reporting a bogus zero rate for the tick.
        for _ in 0..<3 {
            var length = 0
            guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
                return (0, 0)
            }
            var buffer = [UInt8](repeating: 0, count: length)
            guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { continue }
            return sum(buffer, length)
        }
        return (0, 0)
    }

    private static func sum(_ buffer: [UInt8], _ length: Int) -> (in: UInt64, out: UInt64) {
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
