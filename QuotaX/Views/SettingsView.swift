import SwiftUI

// MARK: - 设置窗口控制器
/// 使用 NSWindow 直接创建浮动窗口，绕过 MenuBarExtra + LSUIElement 的 Settings 场景 bug
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(viewModel: QuotaViewModel) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = SettingsContentView()
            .environmentObject(viewModel)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "QuotaX 设置"
        w.contentView = NSHostingView(rootView: content)
        w.isReleasedWhenClosed = false

        // 定位到屏幕中央偏上，避开菜单栏弹窗
        if let screen = NSScreen.main {
            let x = screen.frame.midX - 230
            let y = screen.frame.midY - 50
            w.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            w.center()
        }

        w.level = .popUpMenu
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

// MARK: - 设置内容（TabView 三栏）
struct SettingsContentView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gear") }
            ProvidersSettingsTab()
                .tabItem { Label("服务商", systemImage: "server.rack") }
            NotificationSettingsTab()
                .tabItem { Label("通知", systemImage: "bell") }
        }
        .frame(width: 440, height: 300)
    }
}

// MARK: - 通用设置 Tab
struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("开机自动启动", isOn: $settings.launchAtLogin)

            Picker("菜单栏显示", selection: $settings.displayMode) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }

            Picker("刷新间隔", selection: $settings.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 添加 Provider 窗口控制器
/// 独立 NSWindow 弹窗（替代 .sheet()，避免与高层级设置窗口的模态冲突）
final class AddProviderWindowController {
    static let shared = AddProviderWindowController()
    private var window: NSWindow?

    func show(type: ProviderType, viewModel: QuotaViewModel, relativeTo parentWindow: NSWindow?) {
        window?.close()

        let content = AddProviderPanel(providerType: type) { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
        .environmentObject(viewModel)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "连接 \(type.rawValue)"
        w.contentView = NSHostingView(rootView: content)
        w.isReleasedWhenClosed = false
        w.level = .popUpMenu

        // 居中于父窗口（若有），否则居中于屏幕
        if let parent = parentWindow {
            let px = parent.frame.midX - 190
            let py = parent.frame.midY - 80
            w.setFrameOrigin(NSPoint(x: px, y: py))
        } else {
            w.center()
        }

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = w
    }
}

// MARK: - 添加 Provider 面板内容
private struct AddProviderPanel: View {
    @EnvironmentObject var viewModel: QuotaViewModel
    let providerType: ProviderType
    let onDismiss: () -> Void

    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(instructionText)
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            if let error = errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Label("密钥仅保存在本地，不会上传", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKey.isEmpty || isSaving)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var instructionText: String {
        switch providerType {
        case .openRouter:
            return "在 openrouter.ai/settings/keys 获取 API Key。"
        case .codex:
            return "输入 OpenAI API Key，用于查询 Codex 使用状态。"
        case .amp:
            return "Amp 自动从本地 CLI 读取，通常无需手动配置。"
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        do {
            try viewModel.configureProvider(type: providerType, apiKey: apiKey)
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}

// MARK: - Provider 设置 Tab
struct ProvidersSettingsTab: View {
    @EnvironmentObject var viewModel: QuotaViewModel

    /// 是否为自动检测到的 Provider（无需手动配置密钥）
    private func isAutoDetected(_ type: ProviderType) -> Bool {
        switch type {
        case .codex:
            return FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".codex/auth.json").path
            )
        case .amp:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Form {
            ForEach(ProviderType.allCases) { type in
                HStack {
                    Image(systemName: type.iconName)
                    Text(type.rawValue)
                    Spacer()

                    if viewModel.isProviderConfigured(type) {
                        if isAutoDetected(type) {
                            Text("已连接 (自动)").foregroundStyle(.green).font(.caption)
                        } else {
                            Text("已连接").foregroundStyle(.green).font(.caption)
                            Button("断开") { try? viewModel.removeProvider(type: type) }
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button("连接") {
                            let settingsWindow = NSApp.windows.first { $0.title == "QuotaX 设置" }
                            AddProviderWindowController.shared.show(
                                type: type, viewModel: viewModel, relativeTo: settingsWindow
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 通知设置 Tab
struct NotificationSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Toggle("启用额度预警", isOn: $settings.notificationsEnabled)

            if settings.notificationsEnabled {
                HStack {
                    Text("预警阈值")
                    Slider(value: $settings.notificationThreshold, in: 0.05...0.5, step: 0.05)
                    Text("\(Int(settings.notificationThreshold * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 占位 Settings Scene（保留 Cmd+, 兼容）
struct SettingsView: View {
    var body: some View {
        Text("请从菜单栏面板打开设置")
            .frame(width: 200, height: 60)
    }
}
