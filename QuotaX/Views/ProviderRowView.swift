import SwiftUI

// MARK: - 单个 Provider 额度卡片
struct ProviderRowView: View {
    let quota: QuotaInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶行：图标 + 名称 + 百分比/错误
            HStack {
                Image(systemName: quota.providerType.iconName)
                    .foregroundStyle(quota.status.color)
                Text(quota.providerName)
                    .font(.system(.subheadline, weight: .semibold))

                Spacer()

                if let error = quota.error {
                    Label("错误", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .help(error)
                } else {
                    Text(quota.formattedRemaining)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(quota.status.color)
                }
            }

            if quota.error == nil {
                if let details = quota.details, !details.isEmpty {
                    // 服务商带来多块用量明细（如 Droid 的 5 小时 / 每周 / 每月）：用明细表代替单一进度条；
                    // 顶行百分比仍是最紧张的一项，菜单栏轮播与预警沿用它
                    QuotaDetailGrid(details: details)
                } else {
                    if quota.hasKnownRemainingPercentage {
                        // 进度条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.quaternary)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(quota.status.color.gradient)
                                    .frame(width: geo.size.width * quota.remainingPercentage, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    // 底行：用量 + 重置时间
                    HStack {
                        Text(quota.formattedUsage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let reset = quota.formattedResetDate {
                            Label(reset, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

// MARK: - 多窗口用量明细表
/// 标签 / 进度条 / 剩余 / 重置时间 四列对齐；进度条列弹性伸缩，其余列按内容定宽，无需写死宽度
private struct QuotaDetailGrid: View {
    let details: [QuotaDetail]

    /// 相邻且同组的行归为一节，每节带一个小标题（如「标准」「Core」）
    private var sections: [[QuotaDetail]] {
        details.reduce(into: [[QuotaDetail]]()) { result, row in
            if let last = result.last?.last, last.group == row.group {
                result[result.count - 1].append(row)
            } else {
                result.append([row])
            }
        }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(sections.indices, id: \.self) { index in
                let rows = sections[index]
                // 节与节之间留一点呼吸空间
                if index > 0 {
                    Color.clear.gridCellUnsizedAxes(.horizontal).frame(height: 2)
                }
                if let title = rows[0].group {
                    // 小标题行同时兼作列标题，点明百分比是「剩余」而非「已用」
                    GridRow {
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .gridCellColumns(2)
                        Text("剩余")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .gridColumnAlignment(.trailing)
                        Text("重置")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .gridColumnAlignment(.trailing)
                    }
                }
                ForEach(rows) { row in
                    detailRow(row)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func detailRow(_ row: QuotaDetail) -> some View {
        if let fraction = row.remainingFraction, let remaining = row.formattedRemaining {
            GridRow {
                Text(row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                UsageBar(fraction: fraction, color: row.status.color)
                Text(remaining)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.status.color)
                    .gridColumnAlignment(.trailing)
                // 窗口已过期（或从未开始）时没有重置时间，与 droid 面板「使用后开始计时」一致
                Text(row.formattedResetDate ?? "未开始")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // 日期（如「10月15日 14:23」）必须保持单行：否则进度条列会把这一列挤窄导致折行，
                    // 行高不齐，且折行后的真实高度比撑开弹窗时估算的高，卡片底部会被裁掉
                    .fixedSize(horizontal: true, vertical: false)
                    .gridColumnAlignment(.trailing)
            }
        } else {
            // 没有进度的行（如额外用量余额）：左标签、右数值
            GridRow {
                Text(row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridCellColumns(2)
                Text(row.valueText ?? "—")
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .gridCellColumns(2)
            }
        }
    }
}

// MARK: - 明细行进度条（样式与卡片总览进度条一致：6pt 高、3pt 圆角、状态色渐变）
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.quaternary)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.gradient)
                        .frame(width: geo.size.width * fraction)
                }
            }
    }
}
