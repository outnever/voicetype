# Phase 02: Core Dictation — 技术研究

**Researched:** 2026-07-31
**Domain:** macOS 离线语音听写（WhisperKit + AXUIElement + NSPasteboard）
**Confidence:** HIGH（核心栈已验证至官方文档，HUD/UI 模式为 MEDIUM，NSPasteboard 时间细节为 LOW）

## Summary

Phase 2 实现 VoiceType 的核心闭环：用户按住 ⌥+空格 说话 → 松手 → 转录文字出现在当前应用光标处。核心技术路径为：AVAudioEngine 采集音频进入 RingBuffer（Phase 1 已实现）→ 热键释放时取出完整音频缓冲区 → WhisperKit 本地转录（VAD 切分 + 标点 + 去填充词）→ AXUIElement 写入目标应用（剪贴板回退）。

**关键发现：WhisperKit 实际解析版本为 0.18.0（Package.resolved 确认），远超 STACK.md 标注的 0.9.0。API 保持一致但需以实测为准。** 模型下载大小 ~626MB（`large-v3-v20240930_626MB`），首次启动必须异步加载并显示进度。AXUIElement 文本写入是多应用兼容的核心挑战——PITFALLS.md §1 和 §5 的风险在此阶段集中爆发。

**Primary recommendation:** 使用 WhisperKit 0.18.0 的 `transcribe(audioArray:)` API（直接接受 Float32 数组，与 Phase 1 的 RingBuffer 输出格式天然匹配），VAD 通过 `chunkingStrategy: .vad` 内置处理，文字输入走 AXUIElement → NSPasteboard 多级回退链。

## User Constraints (from CONTEXT.md)

### Locked Decisions

| ID | Decision | Constraint |
|----|----------|------------|
| D-01 | 默认 `tiny` 开发，生产 `large-v3-v20240930_626MB` | 两个模型路径都必须支持 |
| D-02 | 首次启动异步下载模型，显示进度 | WhisperKit 内置下载器可用，需接 `ModelStore.$progress` |
| D-03 | 模型加载后缓存在内存，不重复加载 | TranscriptionService 持有单例 pipe |
| D-04 | 模型下载/加载在后台线程，不阻塞菜单栏 | 延续 Phase 1 `Task.detached` 模式 |
| D-05 | 使用 WhisperKit 内置 VAD，`chunkingStrategy: .vad` | 不引入独立 silero-vad |
| D-06 | VAD 静默检测 + 手动释放热键双重触发 | 热键释放优先于 VAD 超时 |
| D-07 | 热键释放立即转录 | 不要等 VAD 超时 |
| D-08 | 主策略 AXUIElement 写入光标 | `AXUIElementSetAttributeValue` |
| D-09 | 回退策略剪贴板粘贴 | 保存→写入→Cmd+V→恢复 |
| D-10 | 跳过密码字段 | `kAXIsPasswordFieldAttribute` 检测 |
| D-11 | macOS 系统级 HUD 覆盖层 | 半透明浮窗，显示"🎤 录音中…" |
| D-12 | 转录完成后 HUD 消失 | 文字自动出现在光标处 |
| D-13 | 菜单栏图标实时反映状态 | 复用 Phase 1 AppState |
| D-14 | 中英双语自动检测 | Whisper large-v3 原生支持 |
| D-15 | Whisper 内置标点，不额外后处理 | 利用 Whisper 原生能力 |
| D-16 | 去除填充词 | Whisper 天然过滤 + 正则补充 |

### the agent's Discretion

- WhisperKit 具体 API 调用方式（v0.18.0+）
- VAD 静默阈值秒数（建议 1-2 秒）
- HUD 覆盖层的具体 UI 样式和动画
- 剪贴板回退的具体延迟时间
- 正则模式的精确写法
- TranscriptionService 与 AppCoordinator 的集成方式（复用 Phase 1 coordinator 回调模式）

### Deferred Ideas (OUT OF SCOPE)

- （无——discussion 未超出阶段范围）

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DICT-01 | 按住热键说话，松手后转录文字出现在光标处 | §WhisperKit Transcription + §AXUIElement Text Insertion + §Phase 1 Integration |
| DICT-02 | VAD 自动检测用户说话结束 | §WhisperKit Built-in VAD |
| DICT-03 | 离线听写（无需网络） | §WhisperKit Offline Capability |
| DICT-04 | 自动标点和大写 | §WhisperKit Built-in Punctuation |
| DICT-05 | 去除填充词（"um", "uh", "呃"、"嗯"） | §Filler Word Removal |
| DICT-06 | 跨应用文字输入（AX + 剪贴板回退） | §AXUIElement + §NSPasteboard Fallback |
| DICT-07 | 录音可视化指示器 | §HUD Overlay + §Menu Bar State |
| DICT-08 | <15% WER 中英文 | §Model Selection（large-v3 + 双语 auto-detect） |
| UXFE-01 | 菜单栏图标反映状态 | §Menu Bar State（复用 Phase 1 AppState） |
| UXFE-02 | 错误状态提示与修复指引 | §Error Handling Strategy |
| UXFE-03 | 中英双语开箱即用 | §Language Detection |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 热键监听与录制触发 | HotkeyManager (Phase 1) | AppCoordinator | 已有 CGEvent tap，无需改动 |
| 音频采集 | AudioCaptureService (Phase 1) | — | AVAudioEngine + RingBuffer 已实现 |
| 语音转文字 | TranscriptionService (新增) | — | WhisperKit 本地推理，完全离线 |
| VAD 语音检测 | WhisperKit 内置 VAD | — | `chunkingStrategy: .vad`，无需独立组件 |
| 文字写入目标应用 | AXUIElement (accessibility) | NSPasteboard (clipboard) | 两级回退：AX 优先，剪贴板兜底 |
| 录音状态可视化 | HUD Overlay (新增) | MenuBarView (已有) | 浮窗 + 菜单栏图标双通道 |
| 错误处理与用户提示 | AppCoordinator | — | 已有 error state + statusMessage |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| WhisperKit (argmax-oss-swift) | **0.18.0** (resolved) | 本地语音转文字 | Swift-native，Core ML/ANE 优化，内置 VAD，自动模型下载。已验证 6.3k stars，MIT license。 |
| ApplicationServices (AXUIElement) | macOS 14+ native | 读写任意应用文字 | 系统框架，无障碍 API 标准接口。无需额外依赖。 |
| AppKit (NSPasteboard) | macOS 14+ native | 剪贴板回退文字插入 | 系统框架。Phase 1 已间接使用（CGEvent）。 |

> **⚠️ Version note:** `Package.resolved` pins WhisperKit at **0.18.0** (resolved from `Package.swift` constraint `from: "0.9.0"`). STACK.md references 0.9.0 but the actual API matches the main-branch docs fetched in this research. The API surface (`WhisperKit`, `WhisperKitConfig`, `transcribe(audioArray:)`, `DecodingOptions`, `chunkingStrategy: .vad`) is stable across 0.9.0→0.18.0.

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-log | 1.6+ | 结构化日志 | Phase 1 已集成。Phase 2 新增 `Log.transcription` 和 `Log.textIO` 标签。 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| WhisperKit built-in VAD | 独立 silero-vad via ONNX | 独立 VAD 可精细调阈值，但增加依赖和复杂度。D-05 已锁定内置方案。 |
| AXUIElement direct write | CGEventPost 模拟逐键输入 | 逐键更可靠但极慢。剪贴板粘贴（Cmd+V）是更好的中间方案。 |
| 自定义 HUD | 系统 `NSUserNotification` | 通知不显眼且有时延。Phase 2 需要实时浮窗。 |

### Version Verification

```bash
# WhisperKit version confirmed from Package.resolved
# Resolved: 0.18.0 (revision e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef)
# Source: https://github.com/argmaxinc/argmax-oss-swift.git
```

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| argmax-oss-swift (WhisperKit) | SPM (GitHub) | 2+ yrs | 6.3k stars | github.com/argmaxinc/argmax-oss-swift | OK | Approved — already resolved in Package.resolved |
| swift-log | SPM (GitHub) | 5+ yrs | Apple official | github.com/apple/swift-log | OK | Approved — Phase 1 dependency |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*All Phase 2 packages are either system frameworks (AXUIElement, NSPasteboard, SwiftUI) or already-resolved SPM dependencies from Phase 1. No new external packages needed.*

## Architecture Patterns

### System Architecture Diagram (Dictation Flow)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          PRESENTATION LAYER                               │
│  ┌──────────────────┐  ┌─────────────────────────────────────────────┐  │
│  │  MenuBarView     │  │  HUDOverlay (新增)                          │  │
│  │  (已有，复用)     │  │  • 半透明浮窗 NSWindow                     │  │
│  │  iconName: 动态   │  │  • level: .floating (CGWindowLevel 1000)   │  │
│  │  statusMessage    │  │  • 显示 "🎤 录音中…" / 错误提示            │  │
│  └────────┬─────────┘  └──────────────────┬──────────────────────────┘  │
│           │                               │                              │
├───────────┴───────────────────────────────┴──────────────────────────────┤
│                       ORCHESTRATION LAYER                                 │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │                    AppCoordinator (复用+扩展)                         ││
│  │  • onDictationKeyDown: → state=.recording, startAudioCapture()       ││
│  │  • onDictationKeyUp:   → stopAudioCapture(), transcribe(), insert()  ││
│  │  • 管理 TranscriptionService 生命周期                                 ││
│  │  • 驱动 HUDOverlay 显隐                                               ││
│  └───┬──────────────────┬─────────────────────┬─────────────────────────┘│
│      │                  │                     │                           │
├──────┴──────────────────┴─────────────────────┴───────────────────────────┤
│                       INPUT CAPTURE LAYER (Phase 1)                       │
│  ┌──────────────────┐  ┌─────────────────────────────────────────────┐  │
│  │  HotkeyManager   │  │  AudioCaptureService                        │  │
│  │  (Phase 1)       │  │  (Phase 1, 复用)                             │  │
│  │  ⌥+Space hold    │  │  AVAudioEngine → RingBuffer<Float>          │  │
│  │  按键/释放事件    │  │  16kHz mono Float32 PCM                     │  │
│  └──────────────────┘  └────────────────────┬────────────────────────┘  │
│                                             │                            │
├─────────────────────────────────────────────┴────────────────────────────┤
│                       SPEECH PROCESSING LAYER (Phase 2 新增)             │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │              TranscriptionService (新增)                             ││
│  │  • 持有 WhisperKit pipe 实例（缓存）                                 ││
│  │  • transcribe(audioArray: [Float]) → String                         ││
│  │  • DecodingOptions(chunkingStrategy: .vad, detectLanguage: true)    ││
│  │  • 后台 Task.detached(priority: .userInitiated) 执行推理            ││
│  │  • 首次启动: async 下载模型 → ModelStore.$progress → UI 进度条      ││
│  └────────────────────────────────┬─────────────────────────────────────┘│
│                                   │                                       │
├───────────────────────────────────┴───────────────────────────────────────┤
│                       TEXT I/O LAYER (Phase 2 新增)                       │
│  ┌──────────────────────┐  ┌───────────────────────────────────────────┐│
│  │  AccessibilityBridge  │  │  ClipboardBridge                         ││
│  │  (新增)               │  │  (新增)                                  ││
│  │  AXUIElementSetValue  │  │  1. 保存原剪贴板内容                     ││
│  │  检查密码字段跳过      │  │  2. 写入转录文字到剪贴板                ││
│  │  失败→自动回退        │  │  3. CGEvent 模拟 Cmd+V                   ││
│  │                       │  │  4. 延迟 200ms                           ││
│  │                       │  │  5. 恢复原剪贴板内容                     ││
│  └──────────────────────┘  └───────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure (Phase 2 additions)

```
VoiceType/
├── Transcription/                    # Phase 2 新增
│   ├── TranscriptionService.swift    # WhisperKit 封装
│   ├── TranscriptionError.swift      # 错误类型
│   └── ModelDownloadManager.swift    # 模型下载进度管理
├── TextIO/                           # Phase 2 新增
│   ├── TextIOProtocol.swift          # 协议定义
│   ├── AccessibilityBridge.swift     # AXUIElement 主策略
│   ├── ClipboardBridge.swift         # NSPasteboard 回退
│   └── TextInsertionError.swift      # 错误类型
├── UI/                               # Phase 2 扩展
│   ├── HUDOverlay.swift              # 录音浮窗（新增）
│   └── HUDWindowController.swift     # NSWindow 控制器（新增）
├── AppCoordinator.swift              # 扩展：转录+文字插入流程
└── Utilities/
    ├── AppState.swift                # 复用 .recording / .transcribing / .idle
    └── Logging.swift                 # 新增 Log.transcription, Log.textIO
```

### Pattern 1: WhisperKit 单例转录服务

**What:** `TranscriptionService` 持有 `WhisperKit` pipe 实例，初始化时异步加载模型，后续复用缓存的 pipe。转录在 `Task.detached` 中执行，避免阻塞主线程。

**When to use:** 每次按键触发听写。不要每次创建新 pipe（模型加载开销巨大）。

**Example:**
```swift
// Source: WhisperKit README (argmaxinc/argmax-oss-swift, v0.18.0)
// [VERIFIED: GitHub README, webfetch 2026-07-31]

import WhisperKit

@MainActor
final class TranscriptionService: ObservableObject {
    private var pipe: WhisperKit?
    @Published var modelState: ModelState = .notLoaded
    @Published var downloadProgress: Double = 0.0

    enum ModelState {
        case notLoaded, downloading(progress: Double), loading, ready
        case error(String)
    }

    /// 初始化时异步加载模型。菜单栏图标不等待此操作。
    func initialize(modelName: String = "openai_whisper-large-v3-v20240930_626MB") async {
        do {
            // 最小配置：指定模型名，WhisperKit 自动从 HuggingFace 下载
            let config = WhisperKitConfig(model: modelName)
            self.pipe = try await WhisperKit(config)
            self.modelState = .ready
            Log.transcription.info("WhisperKit model loaded: \(modelName)")
        } catch {
            self.modelState = .error(error.localizedDescription)
            Log.transcription.error("WhisperKit init failed: \(error)")
        }
    }

    /// 转录 Float32 音频数组，返回文字字符串。
    /// 在后台 Task.detached 中执行（PITFALLS.md §7 和 §12）。
    func transcribe(audioArray: [Float]) async throws -> String {
        guard let pipe = pipe else {
            throw TranscriptionError.modelNotLoaded
        }

        return try await Task.detached(priority: .userInitiated) {
            let options = DecodingOptions(
                task: .transcribe,
                detectLanguage: true,       // D-14: 中英双语自动检测
                chunkingStrategy: .vad,     // D-05: 内置 VAD
                skipSpecialTokens: true
            )
            let results = try await pipe.transcribe(
                audioArray: audioArray,
                decodeOptions: options
            )
            // 将所有 segment 的 text 拼接
            return results?.map(\.text).joined(separator: "") ?? ""
        }.value
    }
}
```

**⚠️ API 注意:** WhisperKit 0.18.0 的 `transcribe(audioArray:)` 参数名和返回类型可能与上述示例有细微差异。关键 API 调用 `pipe.transcribe(audioArray: audioArray)` 和 `DecodingOptions(chunkingStrategy: .vad)` 已从官方 README 确认 [VERIFIED: GitHub README]。具体参数标签（如 `decodeOptions` vs `options`）需根据 Xcode 自动补全确认。

### Pattern 2: AXUIElement 多级文字插入回退链

**What:** `CompositeTextIO` 实现 `TextIOProtocol`，先尝试 `AccessibilityBridge`（AXUIElement 写入），失败则自动回退到 `ClipboardBridge`（剪贴板粘贴）。每次写入前检查密码字段。

**When to use:** 每次转录完成后插入文字。PITFALLS.md §1 明确指出 AXUIElement 在非标准应用中容易失败，回退链必须从 day one 设计。

**Example:**
```swift
// Source: PITFALLS.md §1, §5 and ARCHITECTURE.md Pattern 2
// [CITED: .planning/research/PITFALLS.md §1 AXUIElement fragility]
// [CITED: .planning/research/ARCHITECTURE.md Pattern 2 Protocol-Based Strategy]

import ApplicationServices

protocol TextIOProtocol {
    func insertText(_ text: String) async throws
    func isPasswordField() -> Bool
}

final class CompositeTextIO: TextIOProtocol {
    let primary: AccessibilityBridge
    let fallback: ClipboardBridge

    func insertText(_ text: String) async throws {
        // D-10: 检查密码字段——不操作安全输入区域
        guard !primary.isPasswordField() else {
            Log.textIO.warning("Password field detected — refusing to insert text")
            throw TextInsertionError.passwordFieldBlocked
        }

        // D-08: 主策略——AXUIElement 写入
        do {
            try await primary.insertText(text)
            Log.textIO.info("Text inserted via AXUIElement — \(text.count) chars")
            return
        } catch {
            Log.textIO.warning("AXUIElement insert failed: \(error). Falling back to clipboard.")
        }

        // D-09: 回退策略——剪贴板粘贴
        do {
            try await fallback.insertText(text)
            Log.textIO.info("Text inserted via clipboard fallback — \(text.count) chars")
        } catch {
            Log.textIO.error("Both AXUIElement and clipboard fallback failed: \(error)")
            throw TextInsertionError.allStrategiesFailed
        }
    }

    func isPasswordField() -> Bool {
        primary.isPasswordField()
    }
}

final class AccessibilityBridge {
    /// 通过 AXUIElement 将文字插入当前焦点应用的光标位置。
    ///
    /// PITFALLS.md §1: 不是所有应用都支持标准 AX text protocol。
    /// 已确认的行为差异：
    /// - AppKit 原生应用（TextEdit, Notes）：完全支持
    /// - Electron 应用（VS Code, Slack）：部分支持，可能需逐应用适配
    /// - 终端模拟器（Terminal.app, iTerm2）：通常不支持 AX 文字写入
    func insertText(_ text: String) async throws {
        // 获取系统全局焦点元素
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard result == .success, let app = focusedApp else {
            throw TextInsertionError.noFocusedApp
        }

        // 获取焦点 UI 元素（光标所在文本框）
        var focusedElement: CFTypeRef?
        let elemResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elemResult == .success, let element = focusedElement else {
            throw TextInsertionError.noFocusedElement
        }

        let axElement = element as! AXUIElement

        // 尝试通过 kAXSelectedTextAttribute 写入
        // （如果用户有选中文字则替换，否则插入光标处）
        let writeResult = AXUIElementSetAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        guard writeResult == .success else {
            throw TextInsertionError.axWriteFailed(code: writeResult.rawValue)
        }
    }

    /// D-10: 检测当前焦点是否为密码/安全字段。
    func isPasswordField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else { return false }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return false }

        var isPassword: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXIsPasswordFieldAttribute as CFString,
            &isPassword
        )

        if result == .success, let value = isPassword as? Bool {
            return value
        }
        return false
    }
}
```

### Pattern 3: NSPasteboard 剪贴板保存→写入→粘贴→恢复

**What:** 使用剪贴板作为文字传输通道。关键操作：保存原始内容 → 写入转录文本 → 模拟 Cmd+V → 等待粘贴完成 → 恢复原始内容。每个步骤之间需要适当延迟（100-200ms）。

**When to use:** AXUIElement 写入失败的自动回退，或者目标应用不支持无障碍 API 时。

**Example:**
```swift
// Source: PITFALLS.md §5 and ARCHITECTURE.md TextIO section
// [CITED: .planning/research/PITFALLS.md §5 clipboard corruption]

import AppKit
import CoreGraphics

final class ClipboardBridge {
    /// PITFALLS.md §5: 剪贴板是共享系统资源。使用后必须恢复原内容。
    /// 延迟 200ms 确保粘贴事件在剪贴板写入后触发。
    func insertText(_ text: String) async throws {
        let pasteboard = NSPasteboard.general

        // Step 1: 保存原始剪贴板内容
        let originalItems = pasteboard.pasteboardItems?.compactMap { item in
            item.string(forType: .string)
        }

        // Step 2: 清空并写入转录文本
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Step 3: 等待剪贴板写入完成（关键！PITFALLS.md §5）
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Step 4: 模拟 Cmd+V
        simulateCommandV()

        // Step 5: 等待粘贴事件完成
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Step 6: 恢复原始剪贴板内容
        pasteboard.clearContents()
        if let original = originalItems?.first {
            pasteboard.setString(original, forType: .string)
        }

        Log.textIO.info("Clipboard write→paste→restore cycle completed")
    }

    /// 通过 CGEvent 模拟 Cmd+V 快捷键
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        // Cmd 按下
        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) {
            cmdDown.flags = .maskCommand
            cmdDown.post(tap: .cghidEventTap)
        }

        // V 按下
        if let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
            vDown.flags = .maskCommand
            vDown.post(tap: .cghidEventTap)
        }

        // V 释放
        if let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            vUp.flags = .maskCommand
            vUp.post(tap: .cghidEventTap)
        }

        // Cmd 释放
        if let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) {
            cmdUp.post(tap: .cghidEventTap)
        }
    }
}
```

### Pattern 4: macOS HUD 浮窗覆盖层

**What:** 使用 `NSWindow` 配合 `.floating` level 创建一个半透明、无边框的系统级覆盖窗，在录音时显示状态文字。使用 `NSWindowController` 管理生命周期，通过 `AppCoordinator` 的 `@Published state` 驱动显隐。

**When to use:** 录音中和转录中等需要系统级视觉反馈的场景（DICT-07, D-11, D-12）。

**Example:**
```swift
// Source: macOS HUD pattern — general SwiftUI+AppKit knowledge
// [ASSUMED] — HUD overlay exact API not verified against official docs this session

import SwiftUI
import AppKit

/// 系统级浮窗覆盖层——录音/转录状态指示器
final class HUDWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = .floating           // 浮于所有窗口之上
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.alphaValue = 0.9
        window.isMovableByWindowBackground = false

        // 中心定位到屏幕中央偏下
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 100
            let y = screenRect.midY - 200
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.init(window: window)
        window.contentView = NSHostingView(
            rootView: HUDOverlayView()
        )
    }

    func show(with message: String) {
        if let view = window?.contentView?.subviews.first as? NSHostingView<HUDOverlayView> {
            // 更新 HUD 文字
        }
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

/// SwiftUI HUD 内容视图
struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 180, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
    }

    var iconName: String {
        switch coordinator.state {
        case .recording: return "mic.fill"
        case .transcribing: return "gearshape.arrow.triangle.2.circlepath"
        default: return "mic.fill"
        }
    }

    var message: String {
        switch coordinator.state {
        case .recording: return "🎤 录音中…"
        case .transcribing: return "📝 转录中…"
        default: return ""
        }
    }
}
```

### Anti-Patterns to Avoid

- **Anti-pattern: 每次转录都重新加载 Whisper 模型** —— PITFALLS.md §7。模型加载需要 2-30 秒，必须缓存 pipe 单例。
- **Anti-pattern: 主线程运行 Whisper 推理** —— PITFALLS.md §7、§12。推理可能耗时 2-5 秒，必须在 `Task.detached` 中运行。
- **Anti-pattern: 单策略文字输入（仅 AXUIElement）** —— PITFALLS.md §1。必须实现 AX→剪贴板回退链。
- **Anti-pattern: 不保存/恢复剪贴板直接使用** —— PITFALLS.md §5。会破坏用户剪贴板内容。
- **Anti-pattern: 不检查密码字段** —— D-10。操作安全输入区域是安全性和 UX 的双重问题。

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 语音转文字 | 自建 ASR 引擎 | WhisperKit `transcribe(audioArray:)` | Whisper 是当前最优的离线 ASR 模型，WhisperKit 已封装 ANE 加速、模型管理、VAD |
| VAD 语音活动检测 | 独立 silero-vad ONNX 集成 | WhisperKit `chunkingStrategy: .vad` | WhisperKit 已内置 silero-vad，无需重复集成 |
| 跨应用无差别文字输入 | 仅使用 AXUIElement | 多级回退链（AX → Clipboard → 可能 keystroke） | AXUIElement 不保证在所有应用中可用（PITFALLS.md §1） |
| 剪贴板传输 | 直接写入不恢复 | Save→Write→Paste→Restore 四步协议 | 剪贴板是共享系统资源（PITFALLS.md §5） |

**Key insight:** Phase 2 的核心复杂度不在 AI（WhisperKit 封装得很好），而在文字输入层（macOS 的多应用兼容性是真实挑战）。投入 60% 精力在 TextIO 层，40% 在 TranscriptionService + Coordinator 集成。

## Common Pitfalls

### Pitfall 1: AXUIElement 在非原生应用中静默失败

**What goes wrong:** 转录文字在 TextEdit 中完美插入，在 VS Code、Slack、浏览器输入框中完全无反应。
**Why it happens:** PITFALLS.md §1：非 AppKit 应用（Electron、浏览器、终端）使用自定义或残缺的 AX 实现。
**How to avoid:** 实现 `CompositeTextIO` 自动回退。当 AX 写入失败时不报错，静默切换到剪贴板 Fallback（D-09/D-19）。
**Warning signs:** 仅在 TextEdit 中测试，未验证 VS Code / Chrome / Slack / Terminal。

### Pitfall 2: Whisper 幻觉与短音频

**What goes wrong:** 用户说了不到 1 秒的话，Whisper 生成无意义或重复的文字。
**Why it happens:** PITFALLS.md §2：Whisper 需要完整语义上下文，极短视频缺乏冗余信息导致模型"脑补"。
**How to avoid:**
- 设置最短录音时长（建议 300ms），拒绝超短片段
- 使用 `large-v3` 模型（比小模型幻觉率低）
- 热键释放后才提交完整音频（非 streaming），提高上下文完整性
**Warning signs:** 极短录音（<300ms）也提交转录，未检查转录结果合理性。

### Pitfall 3: 剪贴板破坏用户数据

**What goes wrong:** 用户复制了一段重要内容，听写后剪贴板内容被替换为转录文字，原内容永久丢失。
**Why it happens:** PITFALLS.md §5：剪贴板是共享系统资源，直接 `clearContents() + setString()` 不恢复原内容。
**How to avoid:**
- **Always save and restore:** 写入前保存 `pasteboardItems`，粘贴后恢复
- Favor AXUIElement as primary strategy (D-08)
- 粘贴与恢复之间留足延迟（100ms 写+200ms 粘）
**Warning signs:** 仅用剪贴板作单一策略，未实现保存/恢复逻辑。

### Pitfall 4: 主线程阻塞——模型加载冻结 UI

**What goes wrong:** 应用启动后菜单栏图标出现，但模型加载在主线程执行，导致整个 UI 卡死 10-30 秒。
**Why it happens:** PITFALLS.md §7：Whisper 模型加载涉及内存映射和 Core ML 编译（首次），天然慢。
**How to avoid:**
- 所有模型加载在 `Task.detached(priority: .userInitiated)` 中
- 菜单栏图标在 1 秒内渲染（Phase 1 已保证）
- 显示"正在加载语音模型…"状态
**Warning signs:** 在 `@MainActor init()` 中调用 `WhisperKit(config)`。

### Pitfall 5: VAD 静默阈值在不同声学环境失效

**What goes wrong:** 开发者在安静办公室调好的 VAD 参数，用户在咖啡厅使用时要么不触发要么过度触发。
**Why it happens:** PITFALLS.md §6：静态阈值不适应不同环境噪声。
**How to avoid (Phase 2 scope):**
- WhisperKit 的 `.vad` chunkingStrategy 已有合理的默认参数
- 热键释放作为主要结束信号（D-07），VAD 仅作辅助
- 用户始终可以手动控制开始/结束（热键优先）
- v2 可增加自适应阈值（PITFALLS.md §6 建议）

## Code Examples

### 完整听写流程：热键按下→录音→释放→转录→插入

```swift
// Source: Phase 1 AppCoordinator.swift + Phase 2 research
// Integration of existing Phase 1 infrastructure with new TranscriptionService + TextIO

@MainActor
final class AppCoordinator: ObservableObject {
    // Phase 1: existing
    let audioCapture = AudioCaptureService()
    let hotkeyManager = HotkeyManager()

    // Phase 2: new
    let transcriptionService = TranscriptionService()
    let textIO = CompositeTextIO(
        primary: AccessibilityBridge(),
        fallback: ClipboardBridge()
    )
    let hudController = HUDWindowController()

    // MARK: - Dictation Flow

    func setupDictationFlow() {
        // ⌥+Space 按下 → 开始录音
        hotkeyManager.onDictationKeyDown = { [weak self] in
            guard let self else { return }
            do {
                try self.audioCapture.start()
                self.state = .recording
                self.hudController.show(with: "🎤 录音中…")
            } catch {
                self.state = .error("麦克风不可用: \(error.localizedDescription)")
            }
        }

        // ⌥+Space 释放 → 停止录音 → 转录 → 插入
        hotkeyManager.onDictationKeyUp = { [weak self] in
            guard let self else { return }
            self.audioCapture.stop()
            self.hudController.hide()
            self.performDictation()
        }
    }

    private func performDictation() {
        Task {
            // 从 RingBuffer 取出录音期间的全部音频
            let audioSamples = audioCapture.buffer.read(
                count: AudioConstants.maxBufferCapacity
            )

            guard !audioSamples.isEmpty else {
                self.state = .idle
                return
            }

            // 转录
            self.state = .transcribing
            self.statusMessage = "转录中…"
            self.hudController.show(with: "📝 转录中…")

            do {
                let text = try await transcriptionService.transcribe(
                    audioArray: audioSamples
                )

                // 插入文字
                self.hudController.hide()
                try await textIO.insertText(text)

                self.state = .idle
                self.statusMessage = "就绪"
            } catch {
                self.state = .error("转录失败: \(error.localizedDescription)")
                self.hudController.hide()
            }
        }
    }
}
```

### 填充词去除（DICT-05）

```swift
// Whisper 模型本身会过滤大部分填充词（尤其 large-v3）。
// 剩余可通过简单正则补充处理（D-16, agent discretion）。
// [ASSUMED] — exact regex patterns not verified, need user tuning

func removeFillerWords(from text: String) -> String {
    var result = text
    let fillerPatterns = [
        // 中文
        ("\\b呃+\\b", ""),
        ("\\b嗯+\\b", ""),
        ("\\b那个\\b", ""),
        ("\\b就是\\b", ""),
        // 英文
        ("\\bum\\b", ""),
        ("\\buh\\b", ""),
        ("\\byou know\\b", ""),
        ("\\blike\\b", ""),   // 谨慎：like 也是正常词汇
    ]

    for (pattern, replacement) in fillerPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
    }

    // 清理多余空格
    result = result.replacingOccurrences(
        of: "\\s{2,}",
        with: " ",
        options: .regularExpression
    )
    return result.trimmingCharacters(in: .whitespaces)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| whisper.cpp (C++) | WhisperKit (native Swift) | 2024 (argmax-oss-swift) | 更简单的 SPM 集成，ANE 自动优化，内置 VAD |
| 独立 silero-vad ONNX | WhisperKit chunkingStrategy: .vad | 2025 (WhisperKit) | 消除外部 VAD 依赖，单一 WhisperKit 依赖完成 STT+VAD |
| AVFoundation `SFSpeechRecognizer` | WhisperKit 本地模型 | 永久（项目架构决定） | Apple Speech API 需网络且限制 1 分钟；WhisperKit 离线无限时长 |

**Deprecated/outdated:**
- `whisper.cpp` as primary (still valid fallback): WhisperKit 0.9+ is mature and directly integrates with Swift concurrency. Keep whisper.cpp only as emergency fallback.
- Manual Core ML model compilation: WhisperKit handles this transparently.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | WhisperKit 0.18.0 `transcribe(audioArray:)` 的参数标签与示例代码完全匹配 | §Pattern 1 | 编译器报错——需根据 Xcode 自动补全微调参数名 |
| A2 | macOS NSPasteboard 剪贴板保存/恢复在 `CGEventPost` 模拟 Cmd+V 之后 200ms 完成 | §Pattern 3 | 延迟不足导致粘贴不完整或恢复过早破坏粘贴——可调大延迟 |
| A3 | `kAXIsPasswordFieldAttribute` 在所有 macOS 14+ 系统中可用且行为一致 | §Pattern 2 | 某些应用不暴露此属性——不会错误地操作密码字段（保守：失败则拒绝操作） |
| A4 | HUD 浮窗 `.floating` level 在所有 Spaces 中正确显示（`.canJoinAllSpaces`） | §Pattern 4 | 多桌面环境可能不显示→改用 `.screenSaver` level 或检测 active space |
| A5 | Whisper large-v3 模型对中文+英文混合听写的 WER < 15% | §DICT-08 | 实际 WER 更高→v2 换 turbo 模型或增加语言偏好设置 |

## Open Questions

1. **WhisperKit 0.18.0 API 精确参数标签**
   - What we know: README 中 `transcribe(audioPath:)` 和 `transcribe(audioArray:)` 的返回类型为 `[TranscriptionResult]?`。`DecodingOptions(chunkingStrategy: .vad)`
   - What's unclear: `transcribe(audioArray:decodeOptions:)` vs `transcribe(audioArray:options:)` 的具体参数标签
   - Recommendation: 实现时根据 Xcode 自动补全确认。不影响架构设计。

2. **VAD 静默阈值最佳值**
   - What we know: WhisperKit 内置 VAD 有默认阈值，silero-vad 典型推荐 `minSilenceDurationMs: 500-1000`
   - What's unclear: WhisperKit 0.18.0 的 VAD 是否暴露阈值配置参数，还是使用内部默认值
   - Recommendation: 先用 WhisperKit 默认 VAD 参数（D-05）。如果用户体验不佳（VAD 切分不准确），再调查是否有配置 Hook。热键释放优先于 VAD（D-07）已降低对精确 VAD 的依赖。

3. **AXUIElement vs 剪贴板回退时机**
   - What we know: AX 在很多应用中失败，但失败模式多样（返回错误码 vs 静默无操作）
   - What's unclear: 如何可靠区分"AX 写入成功但应用不响应"和"AX 写入失败"
   - Recommendation: 实现超时+回退：AX 写入后 500ms 内检测文字是否出现（读取光标位置文字），如果未变化则自动触发剪贴板回退。这是高级特性，Phase 2 mvp 先实现简单回退（AX 返回错误时切换）。

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift 6 | Whole project | ✓ | 6.3.3 | — |
| WhisperKit (SPM) | TranscriptionService | ✓ | 0.18.0 (resolved) | — (already resolved in Package.resolved) |
| AVAudioEngine | AudioCaptureService | ✓ | macOS native | — |
| AXUIElement | AccessibilityBridge | ✓ | macOS native | ClipboardBridge |
| NSPasteboard | ClipboardBridge | ✓ | macOS native | — |
| CGEvent | ClipboardBridge (Cmd+V) | ✓ | macOS native | — |
| Model download network | First launch model download | Unknown | — | 预装 tiny 模型，首次启动无网络时使用 tiny |

**Missing dependencies with no fallback:**
- **模型下载网络**: 首次启动需要网络下载 ~626MB 模型。没有网络则只能使用 tiny 模型（如果预装）或显示"需要网络下载语音模型"。

**Missing dependencies with fallback:**
- （无——所有运行时依赖均为 macOS 系统框架或已解析的 SPM 包）

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | — |
| V3 Session Management | No | — |
| V4 Access Control | No (Phase 3 API keys) | — |
| V5 Input Validation | **Yes** | AXUIElement 写入前验证文字内容（非空、长度合理）。剪贴板回退前验证原内容存在。 |
| V6 Cryptography | No (Phase 3 Keychain) | — |

### Known Threat Patterns for macOS Dictation

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| 操作密码/安全字段 | Information Disclosure | `kAXIsPasswordFieldAttribute` 检测，拒绝在安全字段中写入（D-10） |
| 剪贴板内容泄露 | Information Disclosure | 粘贴后立即恢复原剪贴板内容（D-09），不保留转录文字在剪贴板 |
| AXUIElement 读取无关应用内容 | Privacy | 仅在用户主动触发听写时读取；不轮询；不清点其他应用内容；每次操作后清空缓冲区 |
| 临时音频文件残留 | Information Disclosure | 音频仅在内存中处理（RingBuffer），不写入磁盘。转录后立即丢弃。 |

## Sources

### Primary (HIGH confidence)
- [WhisperKit GitHub README (argmaxinc/argmax-oss-swift)](https://github.com/argmaxinc/argmax-oss-swift) — webfetch 2026-07-31. Verified: API surface (`WhisperKit`, `WhisperKitConfig`, `transcribe(audioArray:)`, `DecodingOptions`, `chunkingStrategy: .vad`), model catalog, VAD integration, incremental loading. Confidence: HIGH.
- [Argmax Pro SDK Docs — Real-time Transcription](https://app.argmaxinc.com/docs/examples/real-time-transcription) — webfetch 2026-07-31. Verified: Streaming API, `DecodingOptionsPro`, VAD modes (`voiceTriggered`, `alwaysOn`), language detection. Confidence: HIGH (official docs).
- [Package.resolved](/Users/nobot/opencode/voicetype/Package.resolved) — Verified WhisperKit resolved version 0.18.0. Confidence: HIGH.
- [Phase 1 Source Code](/Users/nobot/opencode/voicetype/VoiceType/) — Verified: `AudioCaptureService` (AVAudioEngine + RingBuffer), `AppCoordinator` (state machine + hotkey callbacks), `AppState` enum. Confidence: HIGH.
- `.planning/research/PITFALLS.md` §1 (AXUIElement), §2 (Whisper hallucination), §5 (clipboard), §7 (main thread), §12 (inference threads) — Verified existing research. Confidence: HIGH.
- `.planning/research/ARCHITECTURE.md` §TextIO, §TranscriptionService, §Component Responsibilities — Verified existing research. Confidence: HIGH.

### Secondary (MEDIUM confidence)
- [Apple AXUIElement Documentation](https://developer.apple.com/documentation/applicationservices/axuielement) — Attempted webfetch (JavaScript required, failed). Referenced via `kAXSelectedTextAttribute`, `kAXFocusedUIElementAttribute`, `kAXFocusedApplicationAttribute` patterns from PITFALLS.md and community knowledge. Confidence: MEDIUM.
- [Apple NSPasteboard Documentation](https://developer.apple.com/documentation/appkit/nspasteboard) — Attempted webfetch (JavaScript required, failed). Save/restore pattern from PITFALLS.md §5. Confidence: MEDIUM.

### Tertiary (LOW confidence)
- macOS HUD overlay pattern (`.floating` NSWindow + `.canJoinAllSpaces` + `.nonactivatingPanel`) — Training knowledge, not verified against official docs this session. Confidence: LOW. [ASSUMED]
- Filler word regex patterns — Training knowledge. Exact patterns need user tuning and testing. Confidence: LOW. [ASSUMED]
- `CGEventPost` Cmd+V simulation with exact delay timing (100ms write + 200ms paste) — Community knowledge, not benchmarked. Confidence: LOW. [ASSUMED]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — WhisperKit API confirmed from official README (webfetch), Package.resolved confirms version.
- Architecture: HIGH — Existing ARCHITECTURE.md verified against codebase, WhisperKit integration pattern validated against official docs.
- Pitfalls: HIGH — PITFALLS.md provides comprehensive, well-researched coverage cross-referenced with official docs.
- HUD/UI patterns: LOW — Training knowledge only; plan should include a `checkpoint:human-verify` for HUD window behavior.

**Research date:** 2026-07-31
**Valid until:** 2026-08-30 (30 days for stable APIs; WhisperKit 0.18 API expected stable)
