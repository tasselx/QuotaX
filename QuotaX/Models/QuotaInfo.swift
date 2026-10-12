import SwiftUI

// MARK: - Provider 类型标识
enum ProviderType: String, CaseIterable, Codable, Identifiable {
    case openRouter = "OpenRouter"
    case codex = "Codex"
    case amp = "Amp"
    case droid = "Droid"
    case cursor = "Cursor"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .openRouter: return "network"
        case .codex: return "terminal"
        case .amp: return "bolt.fill"
        case .droid: return "cpu"
        case .cursor: return "cursorarrow.rays"
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

    /// 按剩余比例（0~1）划分绿 / 黄 / 红三档；总览与明细行共用同一阈值，避免两处各写一份魔法数
    static func forRemaining(_ fraction: Double) -> QuotaStatus {
        if fraction > 0.5 { return .normal }
        if fraction > 0.2 { return .warning }
        return .danger
    }

    var color: Color {
        switch self {
        case .normal:  return .green
        case .warning: return .orange
        case .danger:  return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - 额度明细（同一服务商下的多个子额度，如 Droid 的 5 小时 / 每周 / 每月窗口）
struct QuotaDetail: Codable, Identifiable {
    /// 分组标题（如「标准」「Core」）；相邻且同组的行在卡片里归为一节
    var group: String?
    let label: String
    /// 已用百分比 0~100；nil 表示该行没有进度概念（如余额），改用 valueText 展示
    var usedPercentage: Double?
    var resetDate: Date?
    /// 无进度条的行的右侧文本（如「$12.34」）
    var valueText: String?

    /// 同一张卡片内 group + label 唯一
    var id: String { "\(group ?? "")|\(label)" }

    /// 剩余比例 0~1，仅有进度的行才有值
    var remainingFraction: Double? {
        usedPercentage.map { max(0, min(1, (100 - $0) / 100)) }
    }

    var status: QuotaStatus { .forRemaining(remainingFraction ?? 1) }

    /// 剩余百分比文本：直接用 100 - used 向下取整（等价于 droid 面板「已用向上取整」），
    /// 避开 Int(x * 100) 先除后乘带来的浮点截断误差
    var formattedRemaining: String? {
        guard let used = usedPercentage else { return nil }
        let remaining = max(0, min(100, 100 - used)).rounded(.down)
        return "\(Int(remaining))%"
    }

    var formattedResetDate: String? { resetDate.map(QuotaInfo.formatResetDate) }
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
    /// 多块用量明细；仅部分服务商提供（如 Droid），为空时卡片沿用单进度条样式。可选类型保证旧缓存仍能解码
    var details: [QuotaDetail]?
    /// 可用额度重置次数（如 OpenAI Codex Reset Credits）；nil 表示不支持或未返回
    var resetCredits: Int? = nil

    var providerName: String { providerType.rawValue }

    /// 是否有可用于进度条和百分比展示的总额度
    var hasKnownRemainingPercentage: Bool {
        unit == .percentage || limit != nil
    }

    var status: QuotaStatus {
        guard error == nil else { return .unknown }
        guard hasKnownRemainingPercentage else { return .unknown }
        return .forRemaining(remainingPercentage)
    }

    /// 格式化剩余百分比（菜单栏 / 卡片标题使用）
    var formattedRemaining: String {
        if unit == .dollars, limit == nil, let remaining {
            return String(format: "$%.2f", remaining)
        }
        return "\(Int(remainingPercentage * 100))%"
    }

    /// 格式化用量详情（卡片副标题使用）
    var formattedUsage: String {
        switch unit {
        case .dollars:
            if let limit { return String(format: "$%.2f / $%.2f", used, limit) }
            if let remaining { return String(format: "$%.2f remaining", remaining) }
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
        resetDate.map(Self.formatResetDate)
    }

    /// 重置时间的统一格式（卡片总览与明细行共用）
    static func formatResetDate(_ date: Date) -> String {
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
