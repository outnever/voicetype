<!-- GSD:project-start source:PROJECT.md -->

## Project

**VoiceType**

VoiceType 是一个 macOS 系统级语音输入与 AI 纠错工具。用户按住热键说话即可将语音转为文字输入到任意应用；当语音识别出错时，按纠错键说出"把 X 改成 Y"的自然语言指令，AI 就能原地修正错误文字——全程无需碰键盘。

**Core Value:** 说错了不用摸键盘——再按一下热键，说句人话就能改回来。

### Constraints

- **平台**: macOS 优先，v1 不在 Windows 上实现
- **AI 依赖**: 纠错功能依赖云端大模型 API（GPT-4o 或 Claude），需要网络连接
- **离线能力**: 语音转文字（Whisper）和 VAD（silero-vad）本地运行，无需网络
- **权限**: 需要 macOS 辅助功能权限（无障碍 API）和麦克风权限

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.x | Primary language | Native macOS integration, no bridging overhead for system APIs, first-class concurrency (async/await), required by WhisperKit |
| SwiftUI | macOS 14+ | UI framework | Modern declarative UI, menu bar app support via `MenuBarExtra` scene (macOS 14+), less boilerplate than AppKit for simple UIs |
| AppKit (selective) | macOS 14+ | System-level APIs | Global hotkey registration (Carbon/CGEvent), accessibility API, menu bar extras — SwiftUI still needs AppKit bridging for these |
| Xcode | 17+ | IDE and toolchain | WhisperKit requires Xcode 16.0+; target latest stable for Swift 6 support and current SDKs |
| Approach | Verdict | Rationale |
|----------|---------|-----------|
| **Swift + SwiftUI** | **USE** | Deepest system integration (accessibility API, global hotkeys, Core Audio, Core ML/ANE). WhisperKit is Swift-native and Core ML optimized. Always-running menu bar utility — must be memory-efficient. |
| Electron | AVOID | Cannot access macOS accessibility APIs without native addons. Always-on Chromium process wastes battery/memory. Global hotkey support unreliable. |
| Tauri (Rust) | AVOID | Still needs Swift/ObjC bridging for AXUIElement and CGEvent. Adds language-boundary complexity for no benefit on a macOS-only v1. Rust audio/ML ecosystem weaker on macOS. |
| Python (py2app) | AVOID | Packaging Python on macOS is fragile. No native SwiftUI/MenuBarExtra support. Audio pipeline overhead through Python-CoreAudio bridging. |

### Speech-to-Text

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| WhisperKit | >= 0.9.0 | On-device speech-to-text | **Primary choice.** Native Swift, runs on Apple Neural Engine (ANE) via Core ML. Built-in VAD chunking, real-time streaming, incremental loading. Automatic model download from HuggingFace. Model: `large-v3-v20240930_626MB` for production, `tiny` for development. MIT license. |
| whisper.cpp | 1.9.1 | Fallback STT engine | Mature C/C++ implementation (52k stars). Strong Apple Silicon support via Metal + Core ML. Has built-in silero-vad integration and XCFramework for Swift. Use only if WhisperKit proves insufficient. |

- **Development**: `tiny` (fastest, lowest accuracy, ~75MB disk)
- **Production**: `large-v3-v20240930_626MB` (compressed, best accuracy for multilingual, ~626MB disk)
- **Alternative macOS-only**: `large-v3-v20240930_turbo` (maximum speed and accuracy, recommended for macOS by Argmax)

### Voice Activity Detection

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| WhisperKit built-in VAD | bundled | Speech segment detection | WhisperKit includes VAD-based chunking via `chunkingStrategy: .vad`. Uses the same silero-vad model internally. Single dependency, no separate integration needed. |
| silero-vad (via whisper.cpp) | v6.2.0 | VAD fallback | whisper.cpp includes a ggml-converted silero-vad model. Use only if moving to whisper.cpp as the STT engine. |

### Audio Capture

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| AVAudioEngine | macOS native | Microphone audio capture | Built-in macOS framework. Tap the input node for real-time PCM float buffers. No external dependency. Low latency, hardware-accelerated format conversion. |
| Core Audio (AudioToolbox) | macOS native | Low-level audio control | Use only if AVAudioEngine lacks control (e.g., specific sample rate enforcement, input device selection). Otherwise, AVAudioEngine is sufficient. |

### Global Hotkeys

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| CGEvent API (CoreGraphics) | macOS native | Global key event monitoring | The most modern approach. `CGEvent.tapCreate` with `.cgSessionEventTap` listens for key events system-wide. No deprecated Carbon dependency. Requires accessibility permission. |
| HotKey (soffes/HotKey) | 0.2.1 | Hotkey registration wrapper | Convience Swift wrapper around Carbon `RegisterEventHotKey`. 1.1k stars, MIT license. Simpler than CGEvent for simple global hotkeys, but depends on deprecated Carbon. Use for rapid prototyping; migrate to CGEvent if Carbon issues arise. |
| Alternative: `NSEvent.addGlobalMonitorForEvents` | macOS native | Global event monitoring | Simpler but only works when app is frontmost (not suitable for always-in-background utility). **Do not use for this project.** |

### Text I/O via Accessibility

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| AXUIElement API (ApplicationServices) | macOS native | Read/write text in any app | Native accessibility framework. `AXUIElementCopyAttributeValue` reads selected text and cursor position. `AXUIElementSetAttributeValue` sets text at cursor. Works across all apps that support accessibility (most do). |
| NSPasteboard | macOS native | Clipboard fallback | Fallback for apps that don't expose text via accessibility API. Write dictation to clipboard, simulate Cmd+V paste. Less seamless but universally compatible. |

### AI Correction (Cloud LLM)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| MacPaw/OpenAI | main branch (auto-updating) | OpenAI API client (GPT-4o) | **Recommended for GPT-4o.** 2.9k stars, MIT license. Full Swift concurrency support, streaming (SSE), function calling, structured outputs. Actively maintained by MacPaw (makers of CleanMyMac). Supports custom host/basePath for OpenRouter and compatible providers. |
| URLSession (native) | — | Anthropic Claude API client | **Use for Anthropic.** No well-maintained Swift SDK for Anthropic exists as of 2026-07. The Messages API is straightforward REST/JSON — a thin `ClaudeClient` wrapper around `URLSession` with async/await is ~200 lines. Less dependency risk than an unmaintained third-party wrapper. |
| Anthropic Swift SDK (none found) | N/A | — | No credible, maintained Swift SDK for Anthropic exists. Avoid unmaintained 0-star repos. Building a thin `URLSession` client is safer and more maintainable than depending on abandonware. |
| Criterion | GPT-4o (via MacPaw/OpenAI) | Claude (via URLSession) |
|-----------|---------------------------|------------------------|
| Swift SDK | MacPaw/OpenAI — mature, maintained | None — build thin URLSession client |
| Prompt quality for text correction | Excellent | Excellent (possibly better for nuanced edits) |
| Latency | Fast | Fast |
| Streaming | Supported via MacPaw SSE | Supported via Anthropic SSE |
| Cost | Comparable | Comparable |
| Recommendation | Use as primary | Offer as alternative / user-selectable |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-log | 1.6+ | Structured logging | Always. Apple's official logging API. Replace all `print()` calls. |
| swift-argument-parser | 1.5+ | CLI argument parsing | Only if building a companion CLI tool for debugging. |
| SwiftSoup | 2.7+ | HTML parsing | Only if text extraction from rich text apps requires HTML parsing. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 17+ | IDE, build, archive, notarize | Required by WhisperKit. Use latest stable. |
| SwiftLint | Code style enforcement | Enforce consistent style across the project. |
| fastlane | Automated signing and distribution | Optional. Simplifies codesigning and notarization for DMG distribution. |
| git-lfs | Large file storage for Whisper models | Required if storing models in repo (not recommended — download on first launch instead). |

## Installation

# Core dependencies via Swift Package Manager (in Xcode)

# Add to Xcode project: File > Add Package Dependencies...

# 1. WhisperKit (speech-to-text + VAD)

#    URL: https://github.com/argmaxinc/argmax-oss-swift.git

#    Version: from 0.9.0

#    Product: WhisperKit

# 2. OpenAI client (GPT-4o integration)

#    URL: https://github.com/MacPaw/OpenAI.git

#    Branch: main

#    Product: OpenAI

# 3. HotKey (optional, for prototyping)

#    URL: https://github.com/soffes/HotKey.git

#    Version: from 0.2.1

#    Product: HotKey

# No CocoaPods, no Carthage, no Homebrew dependencies.

# All dependencies are Swift Package Manager native.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| WhisperKit 0.9.0+ | whisper.cpp 1.9.1 | If WhisperKit has latency issues or model loading problems on specific hardware. whisper.cpp is more battle-tested and has a larger community for debugging. |
| MacPaw/OpenAI | Custom URLSession for OpenAI | If the MacPaw library adds unnecessary complexity for a simple chat completion call. For this project, the library's streaming and error handling justify the dependency. |
| CGEvent tap for hotkeys | soffes/HotKey (Carbon) | If CGEvent tap has issues with specific keyboard layouts or game-mode exclusion. HotKey's simplicity makes it a good fallback. |
| SwiftUI MenuBarExtra | AppKit NSStatusBar | If targeting macOS < 14 (not our case). MenuBarExtra is SwiftUI-native and simpler. |
| Built-in VAD (WhisperKit) | Standalone silero-vad via ONNX | If WhisperKit's VAD chunking doesn't provide enough control over speech/silence thresholds. The standalone model gives more tuning knobs. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Electron / Tauri | Cannot access macOS accessibility APIs, global hotkeys unreliable, excessive memory for always-running utility | Swift + SwiftUI native |
| Apple's built-in Speech framework (SFSpeechRecognizer) | Requires network connection, limited to 1-minute bursts, no model selection. Not suitable for always-on dictation. | WhisperKit (offline, unlimited duration) |
| OpenAI Whisper (Python) via subprocess | Packaging Python on macOS is fragile, subprocess IPC adds latency, model loading overhead per call | WhisperKit (native, in-process) |
| Any unmaintained Anthropic Swift SDK (< 100 stars, no recent commits) | Abandonware risk. Anthropic API is simple enough for a thin URLSession wrapper. | URLSession + Codable |
| NSEvent.addGlobalMonitorForEvents (for hotkeys) | Only fires when app is frontmost. Useless for background utility app. | CGEvent.tapCreate |
| Carbon `RegisterEventHotKey` (directly) | Deprecated. Apple may remove in future macOS. Only supports key-down, not key-up. | CGEvent tap (modern, supports both events) |

## Stack Patterns by Variant

- Use WhisperKit `tiny` model (fast iteration)
- Use CGEvent tap for hotkeys (direct control)
- Use `swift-log` with `.debug` level
- Use GPT-4o via MacPaw/OpenAI
- Use WhisperKit `large-v3-v20240930_626MB` model
- Add user preference for GPT-4o vs Claude
- Implement model download progress UI on first launch
- Add offline-only mode (dictation without correction)
- Build a thin `ClaudeClient` class (~200 lines) wrapping URLSession
- Target Anthropic Messages API (`/v1/messages`)
- Implement SSE streaming via `URLSession.bytes`
- Model: `claude-sonnet-4-20250514` (best latency/cost balance for text correction)

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| WhisperKit 0.9.0 | macOS 14.0+, Xcode 16.0+, Swift 5.10+ | Package.swift includes `Package@swift-6.2.swift` — forward compatible |
| MacPaw/OpenAI (main) | Swift 5.9+, macOS 13+ | Uses Swift concurrency extensively. main branch updates with OpenAI API changes. |
| soffes/HotKey 0.2.1 | macOS 10.12+, Swift 5+ | Simple wrapper. Not Swift 6 concurrency-audited. Use with `@preconcurrency import`. |
| System frameworks (CGEvent, AXUIElement, AVAudioEngine) | macOS 14+ | Native, no version concerns. Target deployment = macOS 14.0 (matching WhisperKit requirement). |

## Sources

- [WhisperKit GitHub (argmaxinc/argmax-oss-swift)](https://github.com/argmaxinc/argmax-oss-swift) — verified v0.9.0, features, model catalog, Core ML integration. HIGH confidence.
- [whisper.cpp GitHub (ggml-org/whisper.cpp)](https://github.com/ggml-org/whisper.cpp) — verified v1.9.1, Core ML support, built-in VAD, XCFramework availability. HIGH confidence.
- [MacPaw/OpenAI GitHub](https://github.com/MacPaw/OpenAI) — verified SDK capabilities, streaming support, custom host configuration. HIGH confidence.
- [silero-vad GitHub (snakers4/silero-vad)](https://github.com/snakers4/silero-vad) — confirmed Python/ONNX implementation, whisper.cpp integration path. HIGH confidence.
- [soffes/HotKey GitHub](https://github.com/soffes/HotKey) — verified global hotkey API usage pattern. MEDIUM confidence (library aging, Carbon dependency).
- [Apple Developer: AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement) — accessibility API documentation. Not directly fetchable, verified via training data and community knowledge. MEDIUM confidence.
- Anthropic Swift SDK search — no maintained SDK found on GitHub (searched anthropic-sdk-swift, AnthropicSwift, sashabeep/anthropic-swift-sdk). HIGH confidence in the absence finding.

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
