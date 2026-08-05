import UserNotifications

// MARK: - 通知服务（额度低时发送 macOS 原生通知）
enum NotificationService {

    static func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 发送额度预警，同一 Provider 使用相同 ID 防止重复弹窗
    static func sendLowQuotaAlert(provider: String, remaining: Double) {
        let content = UNMutableNotificationContent()
        content.title = "QuotaX"
        content.body  = "\(provider) 额度不足，剩余 \(Int(remaining * 100))%"
        content.sound = .default

        let id = "quota-warning-\(provider.lowercased())"
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
