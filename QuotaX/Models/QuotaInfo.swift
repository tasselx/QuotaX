import SwiftUI

// MARK: - Provider 类型标识
enum ProviderType: String, CaseIterable, Codable, Identifiable {
    case openRouter = "OpenRouter"
    case codex = "Codex"
    case amp = "Amp"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .openRouter: return "network"
        case .codex: return "terminal"
        case .amp: return "bolt.fill"
        }
    }


}

// MARK: - 额度单位
enum QuotaUnit: String, Codable {
    case dollars = "$"
    case requests = "requests"
    case credits = "credits"
    case percentage = "%"
}

// MARK: - 额度状态（绿/黄/红三档）
enum QuotaStatus {
    case normal, warning, danger, unknown

    var color: Color {
        switch self {
        case .normal:  return .green
        case .warning: return .orange
        case .danger:  return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - 额度信息（Provider 查询结果的统一模型）
struct QuotaInfo: Identifiable, Codable {
    let id: UUID
    let providerType: ProviderType
    var limit: Double?
    var used: Double
    var remaining: Double?
    /// 0.0 ~ 1.0，表示剩余比例
    var remainingPercentage: Double
    var resetDate: Date?
    var lastUpdated: Date
    var unit: QuotaUnit
    var error: String?

    var providerName: String { providerType.rawValue }

    var status: QuotaStatus {
        guard error == nil else { return .unknown }
        if remainingPercentage > 0.5 { return .normal }
        if remainingPercentage > 0.2 { return .warning }
        return .danger
    }

    /// 格式化剩余百分比（菜单栏 / 卡片标题使用）
    var formattedRemaining: String {
        "\(Int(remainingPercentage * 100))%"
    }

    /// 格式化用量详情（卡片副标题使用）
    var formattedUsage: String {
        switch unit {
        case .dollars:
            if let limit { return String(format: "$%.2f / $%.2f", used, limit) }
            return String(format: "$%.2f used", used)
        case .requests, .credits:
            if let limit { return "\(Int(used)) / \(Int(limit))" }
            return "\(Int(used))"
        case .percentage:
            return "已用 \(Int(used))%"
        }
    }

    /// 格式化重置时间（具体日期时间）
    var formattedResetDate: String? {
        guard let date = resetDate else { return nil }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            fmt.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInTomorrow(date) {
            fmt.dateFormat = "明天 HH:mm"
        } else {
            fmt.dateFormat = "M月d日 HH:mm"
        }
        return fmt.string(from: date)
    }

    /// 快捷构造：表示一个获取失败的 Provider
    static func error(type: ProviderType, message: String) -> QuotaInfo {
        QuotaInfo(
            id: UUID(), providerType: type,
            limit: nil, used: 0, remaining: nil,
            remainingPercentage: 0, resetDate: nil,
            lastUpdated: Date(), unit: .credits, error: message
        )
    }
}
