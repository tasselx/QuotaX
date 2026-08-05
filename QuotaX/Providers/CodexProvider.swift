import Foundation

// MARK: - Codex Provider
/// 自动读取 ~/.codex/auth.json 中的 ChatGPT OAuth Token
/// 通过 ChatGPT Backend API 查询 Codex 使用配额
final class CodexProvider: QuotaProvider {
    let type: ProviderType = .codex

    private static let keychainKey = "codex_api_key"
    private static let authFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/auth.json")
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// auth.json 解析结果
    private struct CodexAuth {
        let accessToken: String
        let accountId: String?
    }

    // MARK: - 自动检测 ~/.codex/auth.json 或手动配置的 Key
    var isConfigured: Bool {
        readAuth() != nil || KeychainService.exists(key: Self.keychainKey)
    }

    /// 是否是自动检测到的（非手动输入）
    var isAutoDetected: Bool {
        readAuth() != nil
    }

    func configure(apiKey: String) throws {
        try KeychainService.save(key: Self.keychainKey, value: apiKey)
    }

    func removeConfiguration() throws {
        KeychainService.delete(key: Self.keychainKey)
    }

    func fetchQuota() async throws -> QuotaInfo {
        guard let auth = readAuth() else {
            throw ProviderError.notConfigured
        }
        return try await fetchUsage(auth: auth)
    }

    // MARK: - 从 ~/.codex/auth.json 读取 OAuth Token

    private func readAuth() -> CodexAuth? {
        guard let data = try? Data(contentsOf: Self.authFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              !accessToken.isEmpty else {
            return nil
        }
        return CodexAuth(
            accessToken: accessToken,
            accountId: tokens["account_id"] as? String
        )
    }

    // MARK: - 调用 ChatGPT Backend API 获取 Codex 配额

    private func fetchUsage(auth: CodexAuth) async throws -> QuotaInfo {
        var req = URLRequest(url: Self.usageURL)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = auth.accountId {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        req.timeoutInterval = 20

        let (data, resp) = try await NetworkService.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }

        switch http.statusCode {
        case 401: throw ProviderError.unauthorized
        case 200: return try parseUsage(data)
        default:  throw ProviderError.apiError("HTTP \(http.statusCode)")
        }
    }

    // MARK: - 解析 /backend-api/wham/usage 响应

    private func parseUsage(_ data: Data) throws -> QuotaInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }

        let rateLimit = json["rate_limit"] as? [String: Any]
        let primaryWindow = rateLimit?["primary_window"] as? [String: Any]

        let usedPercent = primaryWindow?["used_percent"] as? Double ?? 0
        let resetAfterSeconds = primaryWindow?["reset_after_seconds"] as? Double
        let resetAt = primaryWindow?["reset_at"] as? TimeInterval

        let remainingPct = max(0, min(1, (100 - usedPercent) / 100.0))

        var resetDate: Date?
        if let ts = resetAt {
            resetDate = Date(timeIntervalSince1970: ts)
        } else if let secs = resetAfterSeconds {
            resetDate = Date().addingTimeInterval(secs)
        }

        return QuotaInfo(
            id: UUID(),
            providerType: .codex,
            limit: 100,
            used: usedPercent,
            remaining: 100 - usedPercent,
            remainingPercentage: remainingPct,
            resetDate: resetDate,
            lastUpdated: Date(),
            unit: .percentage
        )
    }
}
