import Foundation

// MARK: - OpenRouter Provider
/// 通过 OpenRouter API 查询额度使用情况
/// API: GET https://openrouter.ai/api/v1/auth/key
/// Key 来源优先级: Keychain > 环境变量 OPENROUTER_API_KEY
final class OpenRouterProvider: QuotaProvider {
    let type: ProviderType = .openRouter

    private static let keychainKey = "openrouter_api_key"
    private static let apiURL = URL(string: "https://openrouter.ai/api/v1/auth/key")!

    var isConfigured: Bool { resolveApiKey() != nil }

    func configure(apiKey: String) throws {
        try KeychainService.save(key: Self.keychainKey, value: apiKey)
    }

    func removeConfiguration() throws {
        KeychainService.delete(key: Self.keychainKey)
    }

    func fetchQuota() async throws -> QuotaInfo {
        guard let apiKey = resolveApiKey() else {
            throw ProviderError.notConfigured
        }

        var req = URLRequest(url: Self.apiURL)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, resp) = try await NetworkService.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError.invalidResponse }

        switch http.statusCode {
        case 401, 403: throw ProviderError.unauthorized
        case 200:      return try parse(data)
        default:       throw ProviderError.apiError("HTTP \(http.statusCode)")
        }
    }

    // MARK: - Key 来源：Keychain → 环境变量
    private func resolveApiKey() -> String? {
        if let key = KeychainService.load(key: Self.keychainKey) { return key }
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
           !key.isEmpty { return key }
        return nil
    }

    // MARK: - 解析 /api/v1/auth/key 响应
    /// API 返回 limit_remaining（本周期剩余），直接使用而非 limit - usage（累计总量）
    private func parse(_ data: Data) throws -> QuotaInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any] else {
            throw ProviderError.invalidResponse
        }

        let limit = d["limit"] as? Double
        let limitRemaining = d["limit_remaining"] as? Double
        let usage = d["usage"] as? Double ?? 0

        let remaining: Double?
        let used: Double
        let pct: Double

        if let limitRemaining {
            // 优先用 API 返回的本周期剩余
            remaining = limitRemaining
            if let limit, limit > 0 {
                used = limit - limitRemaining
                pct = max(0, limitRemaining / limit)
            } else {
                used = usage
                pct = 1.0
            }
        } else if let limit, limit > 0 {
            remaining = limit - usage
            used = usage
            pct = max(0, (limit - usage) / limit)
        } else {
            remaining = nil
            used = usage
            pct = 1.0
        }

        return QuotaInfo(
            id: UUID(), providerType: .openRouter,
            limit: limit, used: used, remaining: remaining,
            remainingPercentage: pct, resetDate: nil,
            lastUpdated: Date(), unit: .dollars
        )
    }
}
