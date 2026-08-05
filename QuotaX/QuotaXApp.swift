import SwiftUI

@main
struct QuotaXApp: App {
    @StateObject private var viewModel = QuotaViewModel()

    init() {
        NotificationService.requestPermission()
    }

    var body: some Scene {
        // 菜单栏常驻入口
        MenuBarExtra {
            DashboardView()
                .environmentObject(viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .symbolRenderingMode(.monochrome)
                    .imageScale(.large)
                Text(viewModel.menuBarTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        // 设置窗口（通过 SettingsLink 打开）
        Settings {
            SettingsView()
                .environmentObject(viewModel)
        }
    }
}
