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
        .padding(12)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}
