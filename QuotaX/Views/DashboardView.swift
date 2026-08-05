import SwiftUI

// MARK: - 主面板（点击菜单栏弹出）
struct DashboardView: View {
    @EnvironmentObject var viewModel: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.quotas.isEmpty {
                emptyState
            } else {
                providerList
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .frame(minHeight: 200, maxHeight: 480)
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack {
            Text("QuotaX")
                .font(.headline)

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(
                        viewModel.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: viewModel.isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Provider 列表

    private var providerList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(viewModel.quotas) { quota in
                    ProviderRowView(quota: quota)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("尚未配置服务商")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("打开设置添加密钥") {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
    }

    // MARK: - 底部栏

    private var footer: some View {
        HStack {
            if let time = viewModel.lastUpdateTime {
                Text("更新于 \(time, format: .dateTime.hour().minute().second())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                SettingsWindowController.shared.show(viewModel: viewModel)
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
