import SwiftUI

// MARK: - 卡片位置（拖动排序用）
/// 各卡片在 "cards" 坐标空间里的位置，用来判断指针拖到了哪张卡片上
private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [ProviderType: CGRect] = [:]
    static func reduce(value: inout [ProviderType: CGRect], nextValue: () -> [ProviderType: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - 主面板（点击菜单栏弹出）
struct DashboardView: View {
    @EnvironmentObject var viewModel: QuotaViewModel
    /// 正在被拖动的卡片
    @State private var draggingType: ProviderType?
    /// 被拖卡片跟随指针的纵向位移
    @State private var dragOffset: CGFloat = 0
    /// 拖动中指针正悬停的另一张卡片，用来高亮落点
    @State private var dropTargetType: ProviderType?
    @State private var cardFrames: [ProviderType: CGRect] = [:]

    private static let cardsSpace = "cards"

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
        // 宽度固定；高度跟随内容，由 providerList 按卡片自然高度撑开并封顶
        // （Droid 带上多块明细后卡片明显变高，写死高度会让少量服务商时留白过多、全开时又不够）
        .frame(width: 320)
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

    /// 卡片堆叠：同一份内容既用来撑开高度，也用来真正滚动展示
    private var providerCards: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.quotas) { quota in
                card(for: quota)
            }
        }
        .coordinateSpace(name: Self.cardsSpace)
        .overlay(alignment: .topLeading) {
            // 落点高亮画在最上层：被拖的卡片不透明，画在目标卡片自己身上会被盖住
            if let target = dropTargetType, let frame = cardFrames[target] {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
        .padding(16)
    }

    private func card(for quota: QuotaInfo) -> some View {
        let type = quota.providerType
        let isDragging = draggingType == type
        return ProviderRowView(quota: quota)
            // 被拖的卡片垫一层不透明底：卡片本身是半透明的，拖过其他卡片时文字会叠在一起看不清
            // （菜单栏弹窗里 .background 样式本身也是半透明的，实测叠字，所以用不透明的窗口底色）
            .background {
                if isDragging { RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)) }
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CardFramesKey.self,
                        value: [type: geo.frame(in: .named(Self.cardsSpace))]
                    )
                }
            }
            .shadow(color: .black.opacity(isDragging ? 0.35 : 0), radius: 8, y: 4)
            .offset(y: isDragging ? dragOffset : 0)
            .zIndex(isDragging ? 1 : 0)
            .gesture(reorderGesture(for: type))
            // 右键直接隐藏：和设置里的「显示」开关是同一份状态，想显示回来到设置里打开
            .contextMenu {
                Button {
                    viewModel.setProvider(type, visible: false)
                } label: {
                    Label("隐藏 \(type.rawValue)", systemImage: "eye.slash")
                }
            }
    }

    /// 拖动排序：卡片本体跟着指针走，指针所在的另一张卡片高亮，松手后被拖的卡片占用它的位置（顺序由 ViewModel 持久化）。
    /// 不用系统的 onDrag/onDrop：在菜单栏弹窗里它的拖影只截到了不透明的进度条，落下也不触发；
    /// 也不做「拖过即互换」：卡片高低不一（Droid 明显更高），换位后指针会落到别的卡片上来回抖动。
    /// 坐标取外层 "cards" 空间而不是卡片自身，否则卡片一动手势坐标就跟着变，会抖
    private func reorderGesture(for type: ProviderType) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.cardsSpace))
            .onChanged { value in
                draggingType = type
                dragOffset = value.translation.height
                dropTargetType = cardFrames.first {
                    $0.key != type && ($0.value.minY...$0.value.maxY).contains(value.location.y)
                }?.key
            }
            .onEnded { _ in
                withAnimation {
                    if let target = dropTargetType { viewModel.moveQuota(type, to: target) }
                    draggingType = nil
                    dragOffset = 0
                    dropTargetType = nil
                }
            }
    }

    private var providerList: some View {
        // ScrollView 自身没有固有高度（单独放进弹窗会塌成 0 高度，只剩页眉页脚），
        // 且 0 高度时内容不会被布局，也就量不到高度。所以用一份不可见的卡片副本撑开容器：
        // 容器高度 = 卡片自然高度，封顶 600pt（5 家服务商全开且 Droid 含 Core 明细时实测 586pt，需完整显示不滚动）；
        // 真正显示的 ScrollView 叠在上面，内容超出封顶时在列表内滚动
        providerCards
            .hidden()
            .frame(maxHeight: 600)
            .overlay {
                ScrollView(.vertical, showsIndicators: false) {
                    providerCards
                }
                .scrollBounceBehavior(.basedOnSize)
            }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        // 区分「已连接但全被隐藏」和「还没配置」：前者引导去设置里重新打开显示开关
        let allHidden = viewModel.hasHiddenConnectedProviders
        return VStack(spacing: 12) {
            Image(systemName: allHidden ? "eye.slash" : "plus.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(allHidden ? "服务商已全部隐藏" : "尚未配置服务商")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(allHidden ? "打开设置重新显示" : "打开设置添加密钥") {
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