import SwiftUI
import Combine

// MARK: - 核心 ViewModel
@MainActor
final class QuotaViewModel: ObservableObject {
    @Published var quotas: [QuotaInfo] = []
    @Published var isRefreshing = false
    @Published var lastUpdateTime: Date?

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
            return "\(Int(q.remainingPercentage * 100))%"
        case .providerPercentage:
            guard let q = currentRotatedQuota else { return "QuotaX" }
            return "\(q.providerName) \(Int(q.remainingPercentage * 100))%"
        }
    }

    // MARK: - 生命周期

    init() {
        providers = [OpenRouterProvider(), CodexProvider(), AmpProvider()]

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

        let active = providers.filter(\.isConfigured)
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

        // 保持 Provider 注册顺序
        quotas = active.compactMap { p in results.first { $0.providerType == p.type } }
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
        quotas.removeAll { $0.providerType == type }
        saveCache()
    }

    func isProviderConfigured(_ type: ProviderType) -> Bool {
        providers.first(where: { $0.type == type })?.isConfigured ?? false
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
