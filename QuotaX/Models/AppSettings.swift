import Foundation

// MARK: - 菜单栏显示模式
enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case appName = "QuotaX"
    case percentage = "Percentage"
    case providerPercentage = "ProviderPercentage"

    var label: String {
        switch self {
        case .appName:            return "QuotaX"
        case .percentage:         return "百分比"
        case .providerPercentage: return "服务商 + 百分比"
        }
    }
}

// MARK: - 自动刷新间隔
enum RefreshInterval: Int, CaseIterable, Codable {
    case fiveMinutes    = 300
    case fifteenMinutes = 900
    case thirtyMinutes  = 1800
    case oneHour        = 3600

    var label: String {
        switch self {
        case .fiveMinutes:    return "5 分钟"
        case .fifteenMinutes: return "15 分钟"
        case .thirtyMinutes:  return "30 分钟"
        case .oneHour:        return "1 小时"
        }
    }

    var seconds: TimeInterval { TimeInterval(rawValue) }
}

// MARK: - 应用设置（UserDefaults 持久化）
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    @Published var displayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { UserDefaults.standard.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }
    @Published var notificationThreshold: Double {
        didSet { UserDefaults.standard.set(notificationThreshold, forKey: Keys.threshold) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notifEnabled) }
    }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let displayMode   = "displayMode"
        static let refreshInterval = "refreshInterval"
        static let threshold     = "notificationThreshold"
        static let notifEnabled  = "notificationsEnabled"
    }

    private init() {
        let d = UserDefaults.standard
        self.launchAtLogin      = d.bool(forKey: Keys.launchAtLogin)
        self.displayMode        = MenuBarDisplayMode(rawValue: d.string(forKey: Keys.displayMode) ?? "") ?? .percentage
        self.refreshInterval    = RefreshInterval(rawValue: d.integer(forKey: Keys.refreshInterval)) ?? .fifteenMinutes
        let t = d.double(forKey: Keys.threshold)
        self.notificationThreshold = t > 0 ? t : 0.2
        self.notificationsEnabled  = d.object(forKey: Keys.notifEnabled) == nil ? true : d.bool(forKey: Keys.notifEnabled)
    }
}
