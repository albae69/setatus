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
    let inputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let cost: Double
    let models: [ModelStats]

    var promptTokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens }
    var completionTokens: Int { outputTokens + reasoningTokens }
}

struct ModelStats: Identifiable {
    let name: String
    let provider: String
    let requests: Int
    let inputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let cost: Double

    var id: String { "\(name)|\(provider)" }
    var promptTokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens }
    var completionTokens: Int { outputTokens + reasoningTokens }
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
        return keyFrom9Router() ?? keyFromOpenCode()
    }

    /// Fallback for setups that talk to OpenCode directly instead of through 9router:
    /// OpenCode stores its own OAuth credential and refreshes it in place.
    static func keyFromOpenCode() -> String? {
        let db = NSHomeDirectory() + "/.local/share/opencode/opencode.db"
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        let sql = """
            select coalesce(json_extract(value,'$.access'), json_extract(value,'$.key')),
                   json_extract(value,'$.expires')
            from credential
            where integration_id = 'opencode' and active = 1
            order by time_updated desc limit 1;
            """
        guard let output = Shell.run("/usr/bin/sqlite3",
                                     ["-readonly", "-cmd", ".timeout 5000", db, sql])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }

        let fields = output.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let key = String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "null" else { return nil }

        if fields.count > 1, let expires = Double(fields[1]) {
            guard Date(timeIntervalSince1970: expires / 1000) > Date() else { return nil }
        }
        return key
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

    static func today() async -> TodayStats? {
        if let stats = await todayFromOpenCode() { return stats }
        return todayFrom9Router()
    }

    static func todayFrom9Router() -> TodayStats? {
        let db = NSHomeDirectory() + "/.9router/db/data.sqlite"
        guard FileManager.default.fileExists(atPath: db) else { return nil }
        let sql = "select data from usageDaily where dateKey = date('now','localtime') limit 1;"
        guard let raw = Shell.run("/usr/bin/sqlite3", ["-readonly", db, sql])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let data = raw.data(using: .utf8), !raw.isEmpty else { return nil }
        return parseToday(data)
    }

    /// OpenCode has no per-message usage table, but its local service aggregates sessions
    /// for a time range. The service address and password live in its state directory.
    static func todayFromOpenCode() async -> TodayStats? {
        struct Service: Decodable {
            let url: URL
            let password: String
        }
        let path = NSHomeDirectory() + "/.local/state/opencode/service.json"
        guard let data = FileManager.default.contents(atPath: path),
              let service = try? JSONDecoder().decode(Service.self, from: data) else { return nil }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        guard var components = URLComponents(
            url: service.url.appendingPathComponent("api/experimental/session/stats"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "from", value: String(Int(start.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "to", value: String(Int(end.timeIntervalSince1970 * 1000))),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        let credentials = Data("opencode:\(service.password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        guard let (payload, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return parseOpenCodeToday(payload)
    }

    static func parseOpenCodeToday(_ data: Data) -> TodayStats? {
        struct Payload: Decodable {
            struct Tokens: Decodable {
                struct Cache: Decodable {
                    let read: Int
                    let write: Int
                }
                let input: Int
                let output: Int
                let reasoning: Int
                let cache: Cache
            }
            struct Model: Decodable {
                struct Ref: Decodable {
                    let id: String
                    let providerID: String
                }
                let model: Ref
                let steps: Int
                let tokens: Tokens
                let cost: Double
            }
            struct Info: Decodable {
                let steps: Int
                let tokens: Tokens
                let cost: Double
                let models: [Model]
            }
            let data: Info
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        let info = payload.data
        let models = info.models.map { model in
            ModelStats(name: model.model.id,
                       provider: model.model.providerID,
                       requests: model.steps,
                       inputTokens: model.tokens.input,
                       outputTokens: model.tokens.output,
                       reasoningTokens: model.tokens.reasoning,
                       cacheReadTokens: model.tokens.cache.read,
                       cacheWriteTokens: model.tokens.cache.write,
                       cost: model.cost)
        }.sorted { $0.cost == $1.cost ? $0.requests > $1.requests : $0.cost > $1.cost }
        return TodayStats(requests: info.steps,
                          inputTokens: info.tokens.input,
                          outputTokens: info.tokens.output,
                          reasoningTokens: info.tokens.reasoning,
                          cacheReadTokens: info.tokens.cache.read,
                          cacheWriteTokens: info.tokens.cache.write,
                          cost: info.cost,
                          models: models)
    }

    static func parseToday(_ data: Data) -> TodayStats? {
        struct Payload: Decodable {
            struct Model: Decodable {
                let rawModel: String?
                let provider: String?
                let requests: Int?
                let promptTokens: Int?
                let completionTokens: Int?
                let cachedTokens: Int?
                let cost: Double?
            }
            let requests: Int?
            let promptTokens: Int?
            let completionTokens: Int?
            let cost: Double?
            let byModel: [String: Model]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        // 9router records prompt/completion totals and cache reads only, so the input
        // share is what remains of the prompt total.
        let models = (payload.byModel ?? [:]).map { key, model in
            let cached = model.cachedTokens ?? 0
            let prompt = model.promptTokens ?? 0
            return ModelStats(name: model.rawModel ?? key.split(separator: "|").first.map(String.init) ?? key,
                              provider: model.provider ?? "",
                              requests: model.requests ?? 0,
                              inputTokens: max(prompt - cached, 0),
                              outputTokens: model.completionTokens ?? 0,
                              reasoningTokens: 0,
                              cacheReadTokens: cached,
                              cacheWriteTokens: 0,
                              cost: model.cost ?? 0)
        }.sorted { $0.cost > $1.cost }
        let cached = models.reduce(0) { $0 + $1.cacheReadTokens }
        let prompt = payload.promptTokens ?? 0
        return TodayStats(requests: payload.requests ?? 0,
                          inputTokens: max(prompt - cached, 0),
                          outputTokens: payload.completionTokens ?? 0,
                          reasoningTokens: 0,
                          cacheReadTokens: cached,
                          cacheWriteTokens: 0,
                          cost: payload.cost ?? 0,
                          models: models)
    }
}
