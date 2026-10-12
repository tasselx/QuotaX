import SwiftUI
import Combine

// MARK: - 核心 ViewModel
@MainActor
final class QuotaViewModel: ObservableObject {
    @Published var quotas: [QuotaInfo] = []
    @Published var isRefreshing = false
    @Published var lastUpdateTime: Date?
    /// 被用户隐藏的服务商：不展示、不刷新、不参与菜单栏轮播和预警，但保留连接信息，随时可重新显示
    @Published private(set) var hiddenProviders: Set<ProviderType> = []

    let settings = AppSettings.shared

    private var providers: [QuotaProvider] = []
    private var tickTimer: Timer?
    private var tickCount: Int = 0
    private var cancellables = Set<AnyCancellable>()
    private var notifiedProviders: Set<String> = []

    /// 当前菜单栏轮播到的 Provider 索引
    @Published private var rotateIndex = 0

    /// 统一 tick 间隔（秒），所有定时逻辑共用
    private static let tickInterval: TimeInterval = 5

    // MARK: - 缓存 Key
    private static let cacheKey = "cachedQuotas"
    private static let cacheTimeKey = "cachedQuotasTime"
    /// 用户拖动排序后的卡片顺序（服务商 rawValue 数组）
    private static let orderKey = "providerOrder"
    /// 用户隐藏的服务商（rawValue 数组）
    private static let hiddenKey = "hiddenProviders"

    // MARK: - 聚合状态（菜单栏使用）

    /// 当前轮播到的 Provider（仅有效条目）
    private var currentRotatedQuota: QuotaInfo? {
        let valid = quotas.filter { $0.error == nil }
        guard !valid.isEmpty else { return nil }
        return valid[rotateIndex % valid.count]
    }

    var overallStatus: QuotaStatus {
        guard let q = currentRotatedQuota else { return .unknown }
        return q.status
    }

    /// 菜单栏标题——交替显示各 Provider 的名称 + 百分比
    var menuBarTitle: String {
        switch settings.displayMode {
        case .appName:
            return "QuotaX"
        case .percentage:
            guard let q = currentRotatedQuota else { return "-" }
            return q.hasKnownRemainingPercentage
                ? "\(Int(q.remainingPercentage * 100))%"
                : q.formattedRemaining
        case .providerPercentage:
            guard let q = currentRotatedQuota else { return "QuotaX" }
            let remaining = q.hasKnownRemainingPercentage
                ? "\(Int(q.remainingPercentage * 100))%"
                : q.formattedRemaining
            return "\(q.providerName) \(remaining)"
        }
    }

    // MARK: - 生命周期

    init() {
        providers = [OpenRouterProvider(), CodexProvider(), AmpProvider(), DroidProvider(), CursorProvider()]
        hiddenProviders = Set(
            (UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(ProviderType.init(rawValue:))
        )

        loadCache()
        setupTickTimer()

        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in self?.tickCount = 0 }
            .store(in: &cancellables)

        Task { await refresh() }
    }

    // MARK: - 刷新

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let active = visibleProviders
        let results = await withTaskGroup(of: QuotaInfo.self, returning: [QuotaInfo].self) { group in
            for provider in active {
                group.addTask {
                    do {
                        return try await provider.fetchQuota()
                    } catch {
                        return .error(type: provider.type, message: error.localizedDescription)
                    }
                }
            }
            var collected: [QuotaInfo] = []
            for await info in group { collected.append(info) }
            return collected
        }

        // 按用户拖动排好的顺序展示；没排过序时保持 Provider 注册顺序
        // （必须在这里生效：每次刷新都会重建 quotas，否则拖好的顺序会被冲掉）
        // 刷新是异步的，期间用户可能刚隐藏/显示了某个服务商，所以按「现在」的状态组装而不是用开始时的名单：
        // 刚隐藏的自然被排除；本轮没抓取的（刚显示出来的）沿用已有卡片，不会被这一轮冲掉
        quotas = applyUserOrder(visibleProviders.compactMap { p in
            results.first { $0.providerType == p.type } ?? quotas.first { $0.providerType == p.type }
        })
        for q in quotas { checkThreshold(q) }
        lastUpdateTime = Date()
        saveCache()
    }

    // MARK: - Provider 管理

    func configureProvider(type: ProviderType, apiKey: String) throws {
        guard let p = providers.first(where: { $0.type == type }) else { return }
        try p.configure(apiKey: apiKey)
        Task { await refresh() }
    }

    func removeProvider(type: ProviderType) throws {
        guard let p = providers.first(where: { $0.type == type }) else { return }
        try p.removeConfiguration()
        // 断开等于忘掉这个服务商：隐藏标记一并清掉，下次重新连接就是正常显示
        if hiddenProviders.remove(type) != nil { persistHiddenProviders() }
        quotas.removeAll { $0.providerType == type }
        saveCache()
    }

    func isProviderConfigured(_ type: ProviderType) -> Bool {
        providers.first(where: { $0.type == type })?.isConfigured ?? false
    }

    // MARK: - 显示 / 隐藏（设置里按服务商开关，UserDefaults 持久化）

    /// 当前应当展示的服务商：已连接且没被隐藏
    private var visibleProviders: [QuotaProvider] {
        providers.filter { $0.isConfigured && !hiddenProviders.contains($0.type) }
    }

    /// 有已连接但被隐藏的服务商：列表为空时用来区分「全被隐藏了」和「还没配置」
    var hasHiddenConnectedProviders: Bool {
        providers.contains { hiddenProviders.contains($0.type) && $0.isConfigured }
    }

    /// 显示或隐藏某个服务商：隐藏时立刻撤掉卡片；显示时马上刷新一次让卡片回来（位置沿用拖动排序的记录）
    func setProvider(_ type: ProviderType, visible: Bool) {
        if visible {
            hiddenProviders.remove(type)
        } else {
            hiddenProviders.insert(type)
        }
        persistHiddenProviders()
        if visible {
            Task { await refresh() }
        } else {
            quotas.removeAll { $0.providerType == type }
            saveCache()
        }
    }

    private func persistHiddenProviders() {
        UserDefaults.standard.set(hiddenProviders.map(\.rawValue).sorted(), forKey: Self.hiddenKey)
    }

    // MARK: - 卡片顺序（用户拖动排序，UserDefaults 持久化）

    /// 把 source 卡片移到 target 卡片的位置（拖拽落下时调用），并记住新顺序
    func moveQuota(_ source: ProviderType, to target: ProviderType) {
        guard source != target,
              let from = quotas.firstIndex(where: { $0.providerType == source }),
              let to = quotas.firstIndex(where: { $0.providerType == target }) else { return }
        quotas.insert(quotas.remove(at: from), at: to)
        UserDefaults.standard.set(quotas.map { $0.providerType.rawValue }, forKey: Self.orderKey)
        // 缓存也按新顺序存，下次启动先显示的缓存就不会闪一下旧顺序
        saveCache()
    }

    /// 按已保存的顺序排列；没记录过的服务商（如新接入的）排在已记录的之后，彼此保持原有顺序
    private func applyUserOrder(_ list: [QuotaInfo]) -> [QuotaInfo] {
        let saved = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        func rank(_ q: QuotaInfo) -> Int { saved.firstIndex(of: q.providerType.rawValue) ?? saved.count }
        return list.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    // MARK: - 缓存（UserDefaults，启动时立即显示上次数据）

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(quotas) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cacheTimeKey)
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cached = try? JSONDecoder().decode([QuotaInfo].self, from: data) else { return }
        quotas = cached
        let ts = UserDefaults.standard.double(forKey: Self.cacheTimeKey)
        if ts > 0 { lastUpdateTime = Date(timeIntervalSince1970: ts) }
    }

    // MARK: - 统一定时器（一个 Timer 驱动轮播 + 刷新）

    private func setupTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(
            withTimeInterval: Self.tickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tickCount += 1

                // 轮播：每个 tick 切换一次
                let validCount = self.quotas.filter({ $0.error == nil }).count
                if validCount > 1 {
                    self.rotateIndex = (self.rotateIndex + 1) % validCount
                }

                // 刷新：累计 tick 达到刷新间隔时触发
                let refreshTicks = Int(self.settings.refreshInterval.seconds / Self.tickInterval)
                if self.tickCount >= refreshTicks {
                    self.tickCount = 0
                    await self.refresh()
                }
            }
        }
    }

    // MARK: - 通知阈值检查

    private func checkThreshold(_ info: QuotaInfo) {
        guard settings.notificationsEnabled else { return }
        // 获取失败的条目 remainingPercentage 恒为 0，不能当作「额度不足」，否则断网 / Key 无效时会误报；
        // 这里直接跳过且不改动 notifiedProviders，保证恢复后真正的低额度仍只提醒一次
        guard info.error == nil else { return }
        let key = info.providerName
        if info.remainingPercentage <= settings.notificationThreshold {
            guard !notifiedProviders.contains(key) else { return }
            NotificationService.sendLowQuotaAlert(provider: key, remaining: info.remainingPercentage)
            notifiedProviders.insert(key)
        } else {
            notifiedProviders.remove(key)
        }
    }
}
