import Foundation
import SQLite3

// MARK: - Cursor Provider
/// 通过 cursor.com 网页后台接口查询 Cursor 额度（非官方公开 API，Cursor 改版后可能失效）
/// 登录态来源（优先级）：本机 Cursor 客户端已登录的令牌（只读其 state.vscdb）> 设置里手动粘贴的 Cookie
/// 兼容两种计费形态，由接口响应自动识别，无需用户选择：
///   - 旧套餐按「高级请求次数」计：GET /api/usage?user=<userId>，gpt-4.maxRequestUsage 有值
///   - 新套餐按「美元额度」计：GET /api/usage-summary，individualUsage.plan 的 used / limit（单位：美分）
final class CursorProvider: QuotaProvider {
    let type: ProviderType = .cursor

    private static let keychainKey = "cursor_session_cookie"
    private static let apiBase = "https://cursor.com/api"
    /// Cursor 客户端（VS Code 内核）把登录令牌存在这个 SQLite 文件里
    private static let stateDBPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path

    /// 一次请求所需的登录态；接口认证用的 Cookie 形如 WorkosCursorSessionToken=<userId>%3A%3A<JWT>
    private struct Session {
        let userId: String
        let token: String
        var cookie: String { "WorkosCursorSessionToken=\(userId)%3A%3A\(token)" }
    }

    var isConfigured: Bool { !candidateSessions().isEmpty }

    /// 本机 Cursor 客户端是否已登录；设置页据此显示「已连接 (自动)」而不是手动模式的「断开」
    static var hasLocalSession: Bool { localSession() != nil }

    func configure(apiKey: String) throws {
        // 粘贴内容五花八门（整条 Cookie / 仅 Cookie 值 / 仅 JWT），保存前先确认能解析出登录态，
        // 否则存进去才发现用不了，用户只会看到含糊的「认证失败」
        guard Self.parseSession(from: apiKey) != nil else { throw CursorInputError() }
        try KeychainService.save(
            key: Self.keychainKey,
            value: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func removeConfiguration() throws {
        KeychainService.delete(key: Self.keychainKey)
    }

    func fetchQuota() async throws -> QuotaInfo {
        let sessions = candidateSessions()
        guard !sessions.isEmpty else { throw ProviderError.notConfigured }

        // 本机令牌可能已过期而手动 Cookie 仍有效：认证失败就换下一个来源，全部失败才报错
        for session in sessions {
            do {
                return try await fetchQuota(with: session)
            } catch ProviderError.unauthorized {
                continue
            }
        }
        throw ProviderError.unauthorized
    }

    // MARK: - 查询（先判次数制，再走额度制）

    private func fetchQuota(with session: Session) async throws -> QuotaInfo {
        if let requestBased = try await fetchRequestBasedQuota(session) { return requestBased }
        return try await fetchUsageBasedQuota(session)
    }

    /// 旧套餐（按次数）：gpt-4 档的 maxRequestUsage 有值才算次数制；返回 nil 交给新套餐接口处理
    private func fetchRequestBasedQuota(_ session: Session) async throws -> QuotaInfo? {
        var components = URLComponents(string: Self.apiBase + "/usage")!
        components.queryItems = [URLQueryItem(name: "user", value: session.userId)]

        let data: Data
        do {
            data = try await get(components.url!, session)
        } catch ProviderError.unauthorized {
            throw ProviderError.unauthorized
        } catch let error as URLError {
            // 超时 / 断网这类传输层失败说明「没问到」，不能当成「不是次数制」：
            // 否则次数制账号碰上一次超时，就会回退到美元接口、把卡片显示成 $x / $y
            // （实测 /api/usage 偶发 15 秒超时，随后美元接口 0.5 秒就返回，单位就这样偶发地变了）
            throw error
        } catch {
            // 服务端有应答但不是可用数据（HTTP 错误码等）：当作旧接口不适用，交给新套餐接口
            // （新套餐账号本来就可能没有这个接口的有效数据）
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let premium = json["gpt-4"] as? [String: Any],
              let limit = premium["maxRequestUsage"] as? Double, limit > 0 else { return nil }

        let used = premium["numRequests"] as? Double ?? 0
        // 次数制的周期从 startOfMonth 起算一个月（实测与 usage-summary 的 billingCycleEnd 完全一致）
        let resetDate = Self.parseDate(json["startOfMonth"])
            .flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        return Self.makeInfo(limit: limit, used: used, resetDate: resetDate, unit: .requests)
    }

    /// 新套餐（按美元额度）：individualUsage.plan 的 used / limit 单位是美分
    private func fetchUsageBasedQuota(_ session: Session) async throws -> QuotaInfo {
        let data = try await get(URL(string: Self.apiBase + "/usage-summary")!, session)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plan = (json["individualUsage"] as? [String: Any])?["plan"] as? [String: Any] else {
            throw ProviderError.invalidResponse
        }
        // 没有额度上限（团队 / 企业等账号）算不出进度，明确提示，而不是显示一个错误的百分比
        guard let limitCents = plan["limit"] as? Double, limitCents > 0 else {
            throw ProviderError.apiError("暂不支持该套餐类型")
        }
        let usedCents = plan["used"] as? Double ?? 0
        return Self.makeInfo(
            limit: limitCents / 100, used: usedCents / 100,
            resetDate: Self.parseDate(json["billingCycleEnd"]), unit: .dollars
        )
    }

    private func get(_ url: URL, _ session: Session) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(session.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 手动设置的 Cookie 头不与系统 Cookie 存储混用，也不接收响应里的 Set-Cookie
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15

        // 偶发的首连接失败（15 秒超时 / TLS 握手失败）紧接着重试，通常 0.5 秒内就成功，所以传输层错误自动重试一次；
        // 只重试一次：再失败就如实抛出，不会无限拖长（真断网时 notConnectedToInternet 是立刻返回的）
        let result: (Data, URLResponse)
        do {
            result = try await NetworkService.session.data(for: request)
        } catch is URLError {
            result = try await NetworkService.session.data(for: request)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }

        switch http.statusCode {
        case 200:      return data
        case 401, 403: throw ProviderError.unauthorized
        default:       throw ProviderError.apiError("HTTP \(http.statusCode)")
        }
    }

    private static func makeInfo(limit: Double, used: Double, resetDate: Date?, unit: QuotaUnit) -> QuotaInfo {
        let remaining = max(0, limit - used)
        return QuotaInfo(
            id: UUID(),
            providerType: .cursor,
            limit: limit,
            used: used,
            remaining: remaining,
            remainingPercentage: max(0, min(1, remaining / limit)),
            resetDate: resetDate,
            lastUpdated: Date(),
            unit: unit
        )
    }

    /// 接口时间形如 2026-09-16T13:12:57.000Z（带毫秒）
    private static func parseDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        // 带 .withFractionalSeconds 时解析不了不含毫秒的写法，需要单独再解析一次
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - 登录态来源：本机 Cursor 客户端 → 手动粘贴的 Cookie

    private func candidateSessions() -> [Session] {
        var sessions: [Session] = []
        if let local = Self.localSession() { sessions.append(local) }
        if let raw = KeychainService.load(key: Self.keychainKey), let manual = Self.parseSession(from: raw) {
            sessions.append(manual)
        }
        return sessions
    }

    private static func localSession() -> Session? {
        guard let token = readLocalAccessToken(), let userId = decodeUserId(fromJWT: token) else { return nil }
        return Session(userId: userId, token: token)
    }

    /// 只读读取 Cursor 客户端保存的登录令牌（JWT）；未安装 / 未登录 / 读取失败一律返回 nil，转由手动 Cookie 兜底
    /// 令牌只在内存中使用并只发往 cursor.com，不写日志、不落盘
    private static func readLocalAccessToken() -> String? {
        var db: OpaquePointer?
        // 只读打开：绝不修改 Cursor 自己的数据库
        guard sqlite3_open_v2(stateDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        // Cursor 正在写库时最多等 0.5 秒，避免卡住刷新
        sqlite3_busy_timeout(db, 500)

        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        let token = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// 把用户粘贴的内容解析成登录态，支持三种写法：
    ///   1. 整条 Cookie：WorkosCursorSessionToken=user_xxx%3A%3Aeyj...（可夹带其他 Cookie）
    ///   2. Cookie 的值：user_xxx%3A%3Aeyj... 或 user_xxx::eyj...
    ///   3. 只有 JWT：用户 ID 从其 payload.sub 取
    private static func parseSession(from raw: String) -> Session? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "WorkosCursorSessionToken=") {
            text = String(text[range.upperBound...]).components(separatedBy: ";")[0]
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        text = text.removingPercentEncoding ?? text  // %3A%3A → ::

        if let separator = text.range(of: "::") {
            let userId = String(text[..<separator.lowerBound])
            let token = String(text[separator.upperBound...])
            return userId.isEmpty || token.isEmpty ? nil : Session(userId: userId, token: token)
        }
        guard let userId = decodeUserId(fromJWT: text) else { return nil }
        return Session(userId: userId, token: text)
    }

    /// 从 JWT 的 payload.sub（形如 auth0|user_xxx）取出 Cookie 里要用的用户 ID（竖线之后的部分）
    private static func decodeUserId(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        // JWT 用 base64url 且省略补位，要还原成标准 base64 才能解码
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = payload["sub"] as? String,
              let userId = sub.split(separator: "|").last, !userId.isEmpty else { return nil }
        return String(userId)
    }
}

/// 手动粘贴的内容解析不出登录态时的提示（不带「接口错误」前缀，避免误导）
private struct CursorInputError: LocalizedError {
    var errorDescription: String? { "无法识别，请粘贴 WorkosCursorSessionToken 的值" }
}
