# QuotaX

<p align="center">
  <img src="assets/icon.png" width="128" alt="QuotaX 图标">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white" alt="Swift 5.0">
  <img src="https://img.shields.io/badge/macOS-14.0+-000000?logo=apple&logoColor=white" alt="macOS 14.0+">
  <img src="https://img.shields.io/github/v/release/tasselx/QuotaX?logo=github&sort=semver" alt="GitHub Release">
  <img src="https://img.shields.io/github/downloads/tasselx/QuotaX/total?logo=github" alt="GitHub Downloads">
  <img src="https://img.shields.io/github/stars/tasselx/QuotaX?logo=github" alt="GitHub Stars">
</p>

macOS 菜单栏 AI 额度监控工具。像查看 CPU / 内存一样随时查看 AI 服务剩余额度。

[English](README.md)

## 功能

- 菜单栏常驻，交替显示各服务商剩余百分比
- 支持 OpenRouter、Codex (ChatGPT)、Amp
- 自动检测本地配置（Codex auth.json 仅支持官方 ChatGPT 账号、Amp CLI、环境变量）
- 额度不足时发送系统通知
- 可自定义刷新间隔和预警阈值
- 密钥仅保存在本地，不会上传

## 支持的服务商

| 服务商 | 数据来源 | 配置方式 |
|--------|---------|---------|
| OpenRouter | API (`/api/v1/auth/key`) | 手动输入 API Key 或设置 `OPENROUTER_API_KEY` 环境变量 |
| Codex | ChatGPT Backend API | 自动读取 `~/.codex/auth.json`（仅支持官方 ChatGPT 账号） |
| Amp | `amp usage` 命令 | 自动检测本地 CLI |

## 下载

| 架构 | DMG 包 | 说明 |
|------|--------|------|
| Universal (x86_64 + arm64) | `QuotaX-1.0.dmg` | Intel 和 Apple Silicon 均可用 |
| Apple Silicon | `QuotaX-1.0-arm64.dmg` | 仅 arm64（体积更小） |
| Intel | `QuotaX-1.0-x86_64.dmg` | 仅 x86_64（体积更小） |

👉 [前往 Releases 下载](https://github.com/tasselx/QuotaX/releases)

## 环境要求

- macOS 14.0+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 构建

```bash
# 安装 XcodeGen（如未安装）
brew install xcodegen

# 生成 Xcode 项目并编译 Universal 版本
make build

# 打包 Universal DMG
make dmg

# 单独打包指定架构
make dmg-arm64    # Apple Silicon 专用
make dmg-x86_64   # Intel 专用

# 构建所有 DMG 变体
make dmg-all

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
