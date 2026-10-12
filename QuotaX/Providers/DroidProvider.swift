import Foundation

// MARK: - Droid (Factory) Provider
/// 通过 Factory 官方 API 查询 Droid 的 Token 限额
/// droid CLI 没有 usage 子命令，它自身也是调用 GET /api/billing/limits 读取额度，这里与之保持一致
/// Key 来源优先级: 本地加密存储 > 环境变量 FACTORY_API_KEY
final class DroidProvider: QuotaProvider {
    let type: ProviderType = .droid

    private static let keychainKey = "droid_api_key"
    private static let apiURL = URL(string: "https://api.factory.ai/api/billing/limits")!

    /// 单个限额窗口（5 小时 / 每周 / 每月）的解析结果
    private struct LimitWindow {
        /// 已用百分比 0~100（已按窗口过期规则修正）
        let used: Double
        let resetDate: Date?
    }

    var isConfigured: Bool { resolveApiKey() != nil }

    func configure(apiKey: String) throws {
        // 粘贴的密钥常带首尾空白或换行，会让 Authorization 头失效，保存前先清理
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainService.save(key: Self.keychainKey, value: trimmed)
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
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, resp) = try await NetworkService.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError.invalidResponse }

        switch http.statusCode {
        // Factory 对格式错误的 Key 返回 400（"Invalid api key format"），该接口无请求参数，
        // 400 只可能来自鉴权头，归为认证失败，避免提示成含糊的「接口错误: HTTP 400」
        case 400, 401, 403: throw ProviderError.unauthorized
        case 200:           return try parse(data)
        default:            throw ProviderError.apiError("HTTP \(http.statusCode)")
        }
    }

    // MARK: - Key 来源：本地加密存储 → 环境变量
    private func resolveApiKey() -> String? {
        // 空串视为未配置，避免只粘贴了空白时被误判为「已连接」
        if let key = KeychainService.load(key: Self.keychainKey), !key.isEmpty { return key }
        if let key = ProcessInfo.processInfo.environment["FACTORY_API_KEY"], !key.isEmpty { return key }
        return nil
    }

    // MARK: - 解析 /api/billing/limits 响应
    /// 响应结构（仅 Token 限额计费账户）：
    /// limits.{standard, core}.{fiveHour, weekly, monthly}.{usedPercent, windowEnd, secondsRemaining}
    /// extraUsageBalanceCents：额外用量余额（美分）
    /// 与 droid 一致：总览取标准额度里「已用最高」的窗口作为瓶颈，展示其剩余比例与重置时间；
    /// 同时把 droid 用量面板的三块内容（标准 / Core / 额外用量）作为明细一并带出，卡片逐项展示
    private func parse(_ data: Data) throws -> QuotaInfo {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        let limits = json["limits"] as? [String: Any]
        guard let standard = limits?["standard"] as? [String: Any] else {
            // 旧版 Standard/Premium 计费账户不返回 limits，暂不支持
            throw ProviderError.apiError("账户未启用 Token 限额计费")
        }

        let now = Date()
        let standardWindows = Self.parseWindows(standard, now: now)
        // 并列时 max(by:) 保留靠前者（5 小时 → 每周 → 每月）；重置时间取该瓶颈窗口自己的
        guard let tightest = standardWindows.max(by: { $0.window.used < $1.window.used })?.window else {
            throw ProviderError.invalidResponse
        }

        var details = Self.details(of: standardWindows, group: "标准")
        // Core 额度池：接口没返回就不展示，不影响总览
        if let core = limits?["core"] as? [String: Any] {
            details += Self.details(of: Self.parseWindows(core, now: now), group: "Core")
        }
        // 额外用量余额：与 droid 面板一致，余额为 0 也展示，便于确认没有超额缓冲
        if let cents = json["extraUsageBalanceCents"] as? Double {
            details.append(QuotaDetail(label: "额外用量余额", valueText: String(format: "$%.2f", cents / 100)))
        }

        return QuotaInfo(
            id: UUID(),
            providerType: .droid,
            limit: 100,
            used: tightest.used,
            remaining: 100 - tightest.used,
            remainingPercentage: (100 - tightest.used) / 100.0,
            resetDate: tightest.resetDate,
            lastUpdated: Date(),
            unit: .percentage,
            details: details
        )
    }

    /// 用量面板里的三个窗口（接口键 → 展示名），顺序与 droid 一致
    private static let windowKeys: [(key: String, label: String)] = [
        ("fiveHour", "5 小时"), ("weekly", "每周"), ("monthly", "每月")
    ]

    /// 解析一个额度池（standard / core）下存在的窗口，缺失的窗口直接略过
    private static func parseWindows(_ pool: [String: Any], now: Date) -> [(label: String, window: LimitWindow)] {
        windowKeys.compactMap { item in
            guard let raw = pool[item.key] as? [String: Any] else { return nil }
            return (label: item.label, window: parseWindow(raw, now: now))
        }
    }

    private static func details(of windows: [(label: String, window: LimitWindow)], group: String) -> [QuotaDetail] {
        windows.map {
            QuotaDetail(group: group, label: $0.label, usedPercentage: $0.window.used, resetDate: $0.window.resetDate)
        }
    }

    private static func parseWindow(_ window: [String: Any], now: Date) -> LimitWindow {
        let rawUsed = min(100, max(0, window["usedPercent"] as? Double ?? 0))
        let windowEnd = parseDate(window["windowEnd"])

        // 重置时间：优先 secondsRemaining，其次 windowEnd（仅采用未来时间）
        if let secs = window["secondsRemaining"] as? Double, secs > 0 {
            return LimitWindow(used: rawUsed, resetDate: now.addingTimeInterval(secs))
        }
        if let end = windowEnd, end > now {
            return LimitWindow(used: rawUsed, resetDate: end)
        }
        // 窗口已过期：Factory 会残留旧用量，官方网页端与 droid 都按「已重置」处理，这里保持一致
        return LimitWindow(used: windowEnd != nil ? 0 : rawUsed, resetDate: nil)
    }

    /// windowEnd 可能是 ISO8601 字符串，也可能是秒 / 毫秒时间戳
    private static func parseDate(_ value: Any?) -> Date? {
        if let ts = value as? Double {
            return Date(timeIntervalSince1970: ts > 1e12 ? ts / 1000 : ts)
        }
        guard let text = value as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        // 带 .withFractionalSeconds 时无法解析不含小数秒的字符串，需要单独再解析一次
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
