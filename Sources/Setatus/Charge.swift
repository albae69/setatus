import Foundation

struct ChargeRequest: Codable {
    var limit: Int
    var updated: TimeInterval
}

struct ChargeState: Codable {
    var supported: Bool
    var inhibited: Bool
    var limit: Int
    var percent: Double?
    var at: TimeInterval
}

/// Battery charge limit, applied by the root helper: the app only writes a request file
/// and reads back the state the helper reports.
enum ChargeControl {
    static func requestURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/setatus/charge.json")
    }

    static func stateURL(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/setatus/charge-state.json")
    }

    static func send(limit: Int, home: String = NSHomeDirectory()) {
        let request = ChargeRequest(limit: min(100, max(0, limit)), updated: Date().timeIntervalSince1970)
        let url = requestURL(home: home)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(request) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func state(home: String = NSHomeDirectory()) -> ChargeState? {
        guard let data = FileManager.default.contents(atPath: stateURL(home: home).path) else { return nil }
        return try? JSONDecoder().decode(ChargeState.self, from: data)
    }

    /// SMC key that inhibits charging. CHTE is the current Apple Silicon key (ui32);
    /// CH0B and CHWA are older firmware keys (ui8).
    static func keyName(hasKey: (String) -> Bool) -> String? {
        for key in ["CHTE", "CH0B", "CHWA"] where hasKey(key) { return key }
        return nil
    }

    /// Reads the key at its own width; firmware can reset it behind our back, so the
    /// daemon treats this as the source of truth rather than its last write.
    /// Any non-zero value means inhibited: CHTE reads back the 0x01000000 written for 1,
    /// so an equality check would miss the inhibit and never release it.
    static func isInhibited(_ smc: SMC, key: String) -> Bool {
        smc.meta(key)?.type == "ui32"
            ? smc.readUInt32(key).map { $0 != 0 } ?? false
            : smc.readUInt8(key).map { $0 != 0 } ?? false
    }

    /// Writes the key at its own width. 0x87 (size mismatch) still means the value
    /// applied on some firmware.
    @discardableResult
    static func write(_ smc: SMC, key: String, inhibit: Bool) -> Bool {
        let result = smc.meta(key)?.type == "ui32"
            ? smc.writeUInt32(key, inhibit ? 1 : 0)
            : smc.writeUInt8(key, inhibit ? 1 : 0)
        return result == 0 || result == 0x87
    }

    enum Action { case inhibit, resume, none }

    /// Hysteresis: pause at the limit, resume 2 points below it.
    static func action(limit: Int, percent: Double, inhibited: Bool) -> Action {
        guard limit > 0, limit < 100 else { return inhibited ? .resume : .none }
        if percent >= Double(limit) { return inhibited ? .none : .inhibit }
        if percent <= Double(limit) - 2 { return inhibited ? .resume : .none }
        return .none
    }
}
