import Foundation

struct LimitWindow: Decodable {
    let status: String
    let percent: Double
    let resetsAt: Date?
}

struct Usage {
    let rolling: LimitWindow
    let weekly: LimitWindow
    let monthly: LimitWindow
}

struct TodayStats {
    let requests: Int
    let promptTokens: Int
    let completionTokens: Int
    let cost: Double
}

enum UsageService {
    enum UsageError: Error { case unauthorized }

    static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    // ponytail: plaintext in 9router's own DB already; move to Keychain if app is shared.
    static let keyOverrideDefaultsKey = "apiKeyOverride"

    static func apiKey() -> String? {
        let override = UserDefaults.standard.string(forKey: keyOverrideDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty { return override }
        return keyFrom9Router()
    }

    static func keyFrom9Router() -> String? {
        let db = NSHomeDirectory() + "/.9router/db/data.sqlite"
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        let sql = "select json_extract(data,'$.apiKey') from providerConnections where provider='opencode-go' and isActive=1 limit 1;"
        let output = Shell.run("/usr/bin/sqlite3", ["-readonly", db, sql])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let output, !output.isEmpty, output != "null" else { return nil }
        return output
    }

    static func fetchUsage(key: String) async throws -> Usage {
        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try parseUsage(data)
    }

    static func parseUsage(_ data: Data) throws -> Usage {
        struct Payload: Decodable {
            struct Windows: Decodable {
                let rolling: Window
                let weekly: Window
                let monthly: Window
            }
            struct Window: Decodable {
                let status: String
                let percent: Double
                let resetsAt: String?
            }
            let usage: Windows
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(Payload.self, from: data)
        let iso = ISO8601DateFormatter()

        func convert(_ w: Payload.Window) -> LimitWindow {
            LimitWindow(status: w.status,
                        percent: w.percent,
                        resetsAt: w.resetsAt.flatMap { iso.date(from: $0) })
        }
        return Usage(rolling: convert(payload.usage.rolling),
                     weekly: convert(payload.usage.weekly),
                     monthly: convert(payload.usage.monthly))
    }

    static func today() -> TodayStats? {
        let db = NSHomeDirectory() + "/.9router/db/data.sqlite"
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        let sql = "select data from usageDaily where dateKey = date('now','localtime') limit 1;"
        guard let raw = Shell.run("/usr/bin/sqlite3", ["-readonly", db, sql])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let data = raw.data(using: .utf8), !raw.isEmpty else { return nil }

        struct Payload: Decodable {
            let requests: Int?
            let promptTokens: Int?
            let completionTokens: Int?
            let cost: Double?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return TodayStats(requests: payload.requests ?? 0,
                          promptTokens: payload.promptTokens ?? 0,
                          completionTokens: payload.completionTokens ?? 0,
                          cost: payload.cost ?? 0)
    }
}
