# Phase 1: Foundation - Discussion Log

> **审计记录。** 不用作规划/研究/执行代理的输入。决策已记录在 CONTEXT.md，此日志保留已考虑的替代方案。

**Date:** 2026-07-30
**Phase:** 1-Foundation
**Areas discussed:** 菜单栏交互模式, 热键默认值, 权限引导策略, 项目文件组织, API密钥存储, Xcode项目配置

---

## 菜单栏交互模式

| Option | Description | Selected |
|--------|-------------|----------|
| MenuBarExtra + 独立设置窗口 | SwiftUI 原生 MenuBarExtra 场景 + Settings 场景，最简依赖 | ✓ |
| 纯菜单栏下拉面板 | 无独立窗口，完全内嵌在菜单栏面板中 | |
| AppKit NSStatusBar + NSWindow | 传统 AppKit 方案，更灵活但代码量大 | |

**Agent auto-selection:** MenuBarExtra + 独立设置窗口（SwiftUI 原生方案，macOS 14+ 支持，代码量最小）
**Notes:** 研究明确推荐 SwiftUI MenuBarExtra。仅需 AppKit 桥接用于 CGEvent/AXUIElement（后续阶段），Phase 1 纯 SwiftUI 可行。

---

## 热键默认值

| Option | Description | Selected |
|--------|-------------|----------|
| Fn (听写) + Ctrl+Shift+C (纠错) | README 原文建议的默认配置 | ✓ |
| Fn (听写) + Fn+C (纠错) | 统一使用 Fn 组合键 | |
| 可由用户自定义（无默认） | 首次启动强制用户配置 | |

**Agent auto-selection:** Fn + Ctrl+Shift+C（README 原文建议，用户无需在 Phase 1 配置即可在后续阶段直接使用）
**Notes:** 可配置性属于 v2（CONF-01），Phase 1 仅硬编码默认值。

---

## 权限引导策略

| Option | Description | Selected |
|--------|-------------|----------|
| 分步逐个引导 | 先麦克风（解释原因）→ 再辅助功能（解释原因），降低一次性请求的拒绝率 | ✓ |
| 一次性请求全部 | 一个窗口列出所有所需权限，一次性向用户请求 | |
| 延迟请求 | 只在用户首次使用时弹出，不在启动时请求 | |

**Agent auto-selection:** 分步逐个引导（降低用户认知负担，每次只解释一个权限为什么需要）
**Notes:** PITFALLS.md 警告 macOS 权限在系统更新后可能被撤销，需运行时检测并提醒。

---

## 项目文件组织

| Option | Description | Selected |
|--------|-------------|----------|
| 按子系统分文件夹 | App/, Hotkeys/, Audio/, Settings/, Utilities/ — 与 ARCHITECTURE.md 组件一一对应 | ✓ |
| 按层分文件夹 | Views/, Services/, Models/ — 传统 MVC 组织 | |
| Flat 单文件夹 | 所有源文件放一个文件夹，SwiftPM 默认风格 | |

**Agent auto-selection:** 按子系统分文件夹（与架构文档组件边界一致，组件间零直接引用，通过 AppCoordinator 路由）
**Notes:** 此组织方式为后续阶段的独立测试和 Coordinator 集成打下基础。

---

## API 密钥存储

| Option | Description | Selected |
|--------|-------------|----------|
| macOS Keychain (SecItem) | 系统级安全存储，加密保护 | ✓ |
| UserDefaults / @AppStorage | 简单但明文存储 | |
| 加密 plist 文件 | 自定义加密方案 | |

**Agent auto-selection:** macOS Keychain（STACK.md 和 PITFALLS.md 一致推荐，安全性强无需自行维护加密逻辑）
**Notes:** Keychain wrapper 作为 Utilities/ 子模块提供，Phase 5 纠错阶段将使用此模块读取 API 密钥。

---

## Xcode 项目配置

| Option | Description | Selected |
|--------|-------------|----------|
| 单一 App target | 一个 Xcode target，Swift 6，最低部署 macOS 14.0 | ✓ |
| App + Framework targets | 分离核心逻辑库和 UI 层 | |
| Swift Package + App wrapper | SPM 库 + 薄 App 壳 | |

**Agent auto-selection:** 单一 App target（Phase 1 没必要拆分 target，3 个阶段规模适中）
**Notes:** 如后续需要 XPC service（Whisper 推理隔离），可在 Phase 3 添加。

---

## Deferred Ideas

(None)
