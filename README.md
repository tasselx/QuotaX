# QuotaX

macOS 菜单栏 AI 额度监控工具。像查看 CPU / 内存一样随时查看 AI 服务剩余额度。

## 功能

- 菜单栏常驻，交替显示各服务商剩余百分比
- 支持 OpenRouter、Codex (ChatGPT)、Amp
- 自动检测本地配置（Codex auth.json、Amp CLI、环境变量）
- 额度不足时发送系统通知
- 可自定义刷新间隔和预警阈值
- 密钥仅保存在本地，不会上传

## 支持的服务商

| 服务商 | 数据来源 | 配置方式 |
|--------|---------|---------|
| OpenRouter | API (`/api/v1/auth/key`) | 手动输入 API Key 或设置 `OPENROUTER_API_KEY` 环境变量 |
| Codex | ChatGPT Backend API | 自动读取 `~/.codex/auth.json` |
| Amp | `amp usage` 命令 | 自动检测本地 CLI |

## 环境要求

- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 构建

```bash
# 安装 XcodeGen（如未安装）
brew install xcodegen

# 生成 Xcode 项目并编译
make build

# 打包 DMG
make dmg
# 产物位于 build/QuotaX.dmg

# 清理
make clean
```

## 项目结构

```
QuotaX/
├── Models/          # 数据模型（QuotaInfo, AppSettings）
├── Providers/       # 服务商适配器（OpenRouter, Codex, Amp）
├── Services/        # 基础服务（本地存储, 网络, 通知）
├── ViewModels/      # 业务逻辑（QuotaViewModel）
├── Views/           # UI 视图（Dashboard, Settings）
├── QuotaXApp.swift  # 应用入口
└── Info.plist
```

## 安全

- 密钥存储在 `~/Library/Application Support/QuotaX/`，不使用云存储
- 无账号体系，无数据上传，无用户追踪
- 仅发送只读查询请求，不修改任何服务商数据
