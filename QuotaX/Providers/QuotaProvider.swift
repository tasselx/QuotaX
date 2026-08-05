import Foundation

// MARK: - Provider 协议（SOLID — 接口隔离）
/// 每个 AI 平台实现此协议即可接入 QuotaX
protocol QuotaProvider: AnyObject {
    var type: ProviderType { get }
    var isConfigured: Bool { get }

    func fetchQuota() async throws -> QuotaInfo
    func configure(apiKey: String) throws
    func removeConfiguration() throws
}

// MARK: - Provider 错误类型
enum ProviderError: LocalizedError {
    case notConfigured
    case invalidResponse
    case networkError(Error)
    case apiError(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notConfigured:       return "服务商未配置"
        case .invalidResponse:     return "无效的响应"
        case .networkError(let e): return "网络错误: \(e.localizedDescription)"
        case .apiError(let msg):   return "接口错误: \(msg)"
        case .unauthorized:        return "认证失败，请检查密钥"
        }
    }
}
