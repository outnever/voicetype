---
phase: 01-foundation
plan: 01
subsystem: app-shell
tags: [menubar, permissions, keychain, settings, scaffold]
requires: []
provides: [app-entry-point, menu-bar-ui, permission-gate, keychain-storage, settings-window]
affects: []
tech-stack:
  added: [Swift-6.3, SwiftUI-macOS-14+, WhisperKit-0.18.0, MacPaw-OpenAI-main, swift-log-1.14.0]
  patterns: [MenuBarExtra, ObservableObject-Coordinator, SecItem-Keychain, TCC-Polling, @AppStorage]
key-files:
  created:
    - Package.swift
    - VoiceType/VoiceTypeApp.swift
    - VoiceType/AppCoordinator.swift
    - VoiceType/App/MenuBarView.swift
    - VoiceType/App/PermissionGateView.swift
    - VoiceType/App/SettingsView.swift
    - VoiceType/Utilities/AppState.swift
    - VoiceType/Utilities/Logging.swift
    - VoiceType/Utilities/PermissionManager.swift
    - VoiceType/Settings/KeychainStore.swift
    - VoiceType/Settings/SettingsStore.swift
    - VoiceType/Settings/Defaults.swift
  modified:
    - VoiceType/Info.plist
decisions:
  - "D-01: MenuBarExtra as primary scene (no WindowGroup, LSUIElement for Dock-less)"
  - "D-02: SwiftUI Settings scene for preferences window"
  - "D-07: Sequential permission flow (microphone first, then accessibility with polling)"
  - "D-08: Menu bar icon color reflects aggregate permission status (green/orange/red)"
  - "D-11: Subsystem folder structure (App/Hotkeys/Audio/Settings/Utilities)"
  - "D-12: API keys exclusively in Keychain via SecItem API, never UserDefaults"
  - "Build system: Package.swift (swift build) — xcodebuild unavailable (Xcode.app not installed)"
metrics:
  duration: "3m37s (execution), 81s (initial SPM resolve + build)"
  completed_date: "2026-07-30"
  tasks_completed: 3
  files_created: 12
  files_modified: 1
  requirements_covered: [SHEL-01, SHEL-02, SHEL-03, SHEL-04]
status: complete
---

# Phase 01 Plan 01: App Shell Summary

**One-liner:** 交付可编译的 VoiceType 菜单栏应用——包含权限引导（麦克风→辅助功能顺序流）、设置窗口（API 密钥配置与 Keychain 安全存储），以及中央状态机 AppCoordinator。

## Completed Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Xcode 工程骨架与项目结构 | `8ace3d9` | Package.swift, Info.plist, AppState.swift, Logging.swift, VoiceTypeApp.swift (placeholder) |
| 2 | AppCoordinator、菜单栏入口与权限系统 | `44c0c4b` | AppCoordinator.swift, VoiceTypeApp.swift (full), MenuBarView.swift, PermissionGateView.swift, PermissionManager.swift, SettingsView.swift (placeholder) |
| 3 | 设置窗口与 Keychain 密钥存储 | `f2c0aca` | SettingsView.swift (full), KeychainStore.swift, SettingsStore.swift, Defaults.swift |

## Requirements Satisfied

| ID | Requirement | How Satisfied |
|----|-------------|---------------|
| **SHEL-01** | 菜单栏图标 1 秒内出现 | `AppCoordinator.init()` 中 `iconName = "mic.fill"` 立即设默认值；所有重操作（权限检查）在 `Task.detached(priority: .userInitiated)` 异步执行 |
| **SHEL-02** | 首次启动顺序权限引导 | `PermissionGateView` 分步引导：步骤 1 解释麦克风用途 → 调用 TCC 对话框 → 步骤 2 解释辅助功能用途 → 打开系统设置 → 轮询 `AXIsProcessTrusted()` |
| **SHEL-03** | 菜单栏打开独立设置窗口 | `Settings` scene 自动集成 App 菜单；`MenuBarView` 中 "Open Settings..." 按钮调用 `NSApp.sendAction(Selector(("showSettingsWindow:")))` |
| **SHEL-04** | API 密钥存于 Keychain | `KeychainStore` 使用 `kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock`；`SettingsStore` 禁止在 @AppStorage 存密钥；设置界面脱敏显示（`••••` + 末 4 位） |

## Verification Results

```bash
$ swift build
Build complete! (0.10s)
```

- ✅ 所有 Swift 源文件编译通过（0 错误，0 警告，仅 Info.plist 资源声明告警）
- ✅ SPM 依赖全部解析成功（WhisperKit 0.18.0, MacPaw/OpenAI main, swift-log 1.14.0）
- ✅ `NSMicrophoneUsageDescription` 已含中文说明
- ✅ `LSUIElement = YES` 抑制 Dock 图标
- ⚠️ `xcodebuild` 不可用（macOS 上未安装 Xcode.app，仅有命令行工具）——使用 `swift build` 作为等效编译验证

## Deviations from Plan

### Environment Adaptation

**1. [Rule 3 - Blocking] xcodebuild unavailable, used swift build instead**
- **Found during:** Task 1
- **Issue:** 系统未安装 Xcode.app（只有 Command Line Tools via `/Library/Developer/CommandLineTools`）。`xcodebuild -project VoiceType.xcodeproj` 不可用。
- **Fix:** 使用 `Package.swift` + `swift build` 作为构建系统。Package.swift 是 Swift 的现代标准构建方式，编译验证等效。`.xcodeproj` 可在安装 Xcode 后通过打开 Package.swift 自动生成。
- **Files modified:** 无（采用 Package.swift 替代 .xcodeproj）

**2. [Rule 2 - Missing] Added placeholder @main entry point for Task 1 build**
- **Found during:** Task 1
- **Issue:** 计划要求 Task 1 项目可编译但 `VoiceTypeApp.swift` 在 Task 2 才创建。无入口点则 `swift build` 编译失败（无 `@main` 标记的 executable target）。
- **Fix:** 创建最小占位 `VoiceTypeApp.swift`（仅含 MenuBarExtra 和 "VoiceType" 文字），Task 2 中替换为完整实现。
- **Commit:** `8ace3d9`

**3. [Rule 2 - Missing] Created placeholder SettingsView for Task 2 compilation**
- **Found during:** Task 2
- **Issue:** `VoiceTypeApp.swift` 引用 `SettingsView()`（在 `Settings` scene 中），但该文件在 Task 3 才完整实现。
- **Fix:** 创建最小占位 `SettingsView`，Task 3 中替换为完整三标签页实现。
- **Commit:** `44c0c4b`

**4. [Rule 2 - Missing] Added LSUIElement to Info.plist**
- **Found during:** Task 2
- **Issue:** 纯菜单栏应用需要隐藏 Dock 图标，但计划未提及 `LSUIElement`。
- **Fix:** 在 `Info.plist` 添加 `<key>LSUIElement</key><true/>`。
- **Commit:** `44c0c4b`

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `Hotkeys/` 空目录 | VoiceType/Hotkeys/ | Phase 2 Plan 02 实现 CGEvent tap 全局热键 |
| `Audio/` 空目录 | VoiceType/Audio/ | Phase 2 Plan 03 实现 AVAudioEngine 音频采集 |
| `onDictationKeyDown/Up` 回调钩子 | AppCoordinator.swift | Phase 2 连接热键到音频采集 |
| `onCorrectionKeyPress` 回调钩子 | AppCoordinator.swift | Phase 3 连接纠错热键到 AI 纠错管线 |
| `currentInputDevice = "Unknown"` | AppCoordinator.swift | Phase 2 AUDI-02 从 AVAudioEngine 获取真实设备名 |
| Whisper Model 选单 | SettingsView.swift | Phase 2 实现模型下载和选择 |
| Language 选单 | SettingsView.swift | Phase 2 实现语言偏好 |
| 热键配置 "v2 可自定义" | SettingsView.swift | v2 需求 CONF-01 |

## Threat Flags

无新增威胁面——所有安全相关组件已在 `<threat_model>` 中覆盖：
- `KeychainStore.swift`：T-01-01（信息泄露）、T-01-03（篡改）——已缓解
- `SettingsView.swift`：T-01-02（信息泄露）——已缓解
- `PermissionManager.swift`：T-01-04（权限提升）——已缓解
- `AppCoordinator.swift`：T-01-05（拒绝服务）——已接受（风险低）

## Self-Check: PASSED

- [x] `Package.swift` exists — FOUND
- [x] `VoiceType/VoiceTypeApp.swift` exists — FOUND
- [x] `VoiceType/AppCoordinator.swift` exists — FOUND
- [x] `VoiceType/App/MenuBarView.swift` exists — FOUND
- [x] `VoiceType/App/PermissionGateView.swift` exists — FOUND
- [x] `VoiceType/App/SettingsView.swift` exists — FOUND
- [x] `VoiceType/Utilities/AppState.swift` exists — FOUND
- [x] `VoiceType/Utilities/Logging.swift` exists — FOUND
- [x] `VoiceType/Utilities/PermissionManager.swift` exists — FOUND
- [x] `VoiceType/Settings/KeychainStore.swift` exists — FOUND
- [x] `VoiceType/Settings/SettingsStore.swift` exists — FOUND
- [x] `VoiceType/Settings/Defaults.swift` exists — FOUND
- [x] `VoiceType/Info.plist` exists with NSMicrophoneUsageDescription — FOUND
- [x] Commit `8ace3d9` exists — FOUND
- [x] Commit `44c0c4b` exists — FOUND
- [x] Commit `f2c0aca` exists — FOUND
- [x] `swift build` succeeds — PASSED
