---
phase: 01-foundation
plan: 03
subsystem: Audio Capture
tags: [audio, avaudioengine, ringbuffer, coreaudio, hotplug, silence-detection]
requires: [01-01]
provides: [AudioCaptureService, RingBuffer, AudioFormat]
affects: [AppCoordinator]
status: complete
tech-stack:
  added:
    - AVAudioEngine (macOS native) — input node tap for real-time mic capture
    - AVAudioConverter — hardware format → 16kHz mono Float32 PCM
    - CoreAudio (AudioObjectGetPropertyData, AudioObjectAddPropertyListenerBlock) — macOS device name lookup + hotplug detection
    - os_unfair_lock — thread-safe SPSC ring buffer
  patterns:
    - Real-time audio tap callback: format conversion + RingBuffer.write only — zero processing, no logging, no allocations
    - SPSC (Single Producer, Single Consumer) ring buffer with os_unfair_lock for non-blocking thread safety
    - CoreAudio property listener for default input device changes (macOS replacement for iOS-only AVAudioSession)
    - Subsystem isolation via NotificationCenter (no direct imports of Hotkeys/UI/Settings)
key-files:
  created:
    - VoiceType/Audio/AudioFormat.swift
    - VoiceType/Audio/AudioBuffer.swift
    - VoiceType/Audio/AudioCaptureService.swift
  modified:
    - VoiceType/AppCoordinator.swift
key-decisions:
  - "Audio tap 回调线程仅做格式转换 + RingBuffer.write, 零额外处理（防音频丢帧）"
  - "RingBuffer 使用 os_unfair_lock 而非 DispatchQueue（非阻塞，无优先级反转）"
  - "macOS 设备名和设备热插拔用 CoreAudio 代替 iOS-only AVAudioSession"
  - "设备热插拔时 stop→start 而非原地修改（避免旧格式残留）"
duration: ~5 min
completed_date: 2026-07-30
---

# Phase 1 Plan 3: Audio Capture Pipeline Summary

实现基于 AVAudioEngine 的实时音频采集管线——16kHz 单声道 Float32 PCM 输入，设备热插拔监控，与 AppCoordinator 集成。

## Implementation

### Task 1: Audio Capture Pipeline (cd47d6b)

创建了三个核心音频文件：

- **AudioFormat.swift** — PCM 格式常量（16kHz mono Float32 non-interleaved）、tap 缓冲区大小（1024 frames ≈ 64ms）、环形缓冲区容量（30 秒）。提供 `currentInputDeviceName` 通过 CoreAudio API 读取当前输入设备名称（macOS 上 `AVAudioSession` 不可用）。

- **AudioBuffer.swift** — 泛型环形缓冲区 `RingBuffer<Element>`，使用 `os_unfair_lock` 保证线程安全。SPSC 模式：audio tap 回调写入 × 消费者线程读取。固定容量预分配——`write()` 和 `read()` 中零堆内存分配（实时音频线程安全要求）。缓冲区满时覆盖旧数据（ring buffer 语义）。

- **AudioCaptureService.swift** — AVAudioEngine 封装，`start()` 安装输入 tap 并通过 `AVAudioConverter` 从硬件格式转换为 16kHz mono Float32。tap 回调**仅做格式转换 + RingBuffer.write**（per RESEARCH.md Anti-Patterns ——不做 logging、VAD、level metering）。`stop()` 移除 tap、停止引擎、重置缓冲区。定义了 `AudioError` 枚举（formatConversionFailed, engineStartFailed, tapAlreadyInstalled）。

### Task 2: Device Hot-Plug Monitoring + AppCoordinator Integration (aefdf97)

- **设备监控 `startDeviceMonitoring()`** — 双重监听：① `AVAudioEngineConfigurationChange` 通知（引擎内部配置变更）；② CoreAudio `AudioObjectAddPropertyListenerBlock` 监听 `kAudioHardwarePropertyDefaultInputDevice`（系统默认输入设备变更——USB 插拔、蓝牙连接/断开）。**iOS 版 `AVAudioSession.routeChangeNotification` 在 macOS 不可用，已适配为 CoreAudio property listener**（Rule 3 自动修复）。

- **静音检测 `startSilenceDetection()`** — 每秒从 RingBuffer 读取 1 秒窗口的采样、计算 RMS 能量。若 RMS < 阈值（默认 0.001）且持续 > 5 秒 → 发送 `audioSilenceDetected` 通知。防止麦克风拔出/权限撤销后无声故障（per PITFALLS.md §10）。

- **Notification.Name 扩展** — 定义 `audioDeviceChanged` 和 `audioSilenceDetected`，AudioCaptureService 通过 NotificationCenter 与 AppCoordinator 解耦通信。

- **AppCoordinator 集成** — 添加 `let audioCapture = AudioCaptureService()` 实例；`init()` 中 `setupAudioObservers()` 监听设备变更和静音检测通知并更新 `@Published currentInputDevice` 和 `statusMessage`；`initializeSubsystems()` 中调用 `audioCapture.startDeviceMonitoring()`（设备监控独立运行，不依赖音频采集）；提供 `startAudioCapture() throws` / `stopAudioCapture()` 委托方法供 Phase 2 热键回调使用。

### Adaptations from Plan (Rule 3)

1. **AVAudioSession → CoreAudio**: macOS 不支持 `AVAudioSession`，改用 `AudioObjectGetPropertyData` 获取设备名、`AudioObjectAddPropertyListenerBlock` 监听默认输入设备变更。
2. **AVAudioCommonFormat.pcmFloat32 → .pcmFormatFloat32**: 枚举名称不同。
3. **Sendable 隔离**: `NotificationCenter` 的 `@Sendable` 闭包通过 `MainActor.assumeIsolated` 访问 `@MainActor` 状态（因 `queue: .main` 保证主线程执行但 Swift 6 类型系统不推断）。

## Verification

- [x] `swift build` passes cleanly (no errors, no warnings beyond pre-existing Info.plist notice)
- [x] AUDI-01: 16kHz mono Float32 PCM capture from default mic — AudioCaptureService.start() installs tap with format conversion
- [x] AUDI-02: Device hot-plug handling — CoreAudio listener + AVAudioEngineConfigurationChange observer trigger automatic stop→start
- [x] Tap callback only does format conversion + RingBuffer.write — zero extra processing
- [x] RingBuffer uses os_unfair_lock — non-blocking, SPSC-safe
- [x] Subsystem isolation — AudioCaptureService imports only AVFoundation + CoreAudio, no Hotkeys/UI/Settings references

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] macOS AVAudioSession unavailable — CoreAudio adaptation**
- **Found during:** Task 2
- **Issue:** Plan references `AVAudioSession.routeChangeNotification` and `AVAudioSession.sharedInstance().currentRoute.inputs` — both iOS-only APIs unavailable on macOS
- **Fix:** Replaced with `AudioObjectGetPropertyData(kAudioHardwarePropertyDefaultInputDevice)` for device name lookup and `AudioObjectAddPropertyListenerBlock` with `kAudioHardwarePropertyDefaultInputDevice` for hotplug detection
- **Files modified:** `VoiceType/Audio/AudioFormat.swift`, `VoiceType/Audio/AudioCaptureService.swift`
- **Commit:** aefdf97

**2. [Rule 1 - Bug] Wrong AVAudioCommonFormat enum case**
- **Found during:** Task 1
- **Issue:** `.pcmFloat32` doesn't exist — correct case is `.pcmFormatFloat32`
- **Fix:** Corrected enum case name
- **Files modified:** `VoiceType/Audio/AudioFormat.swift`
- **Commit:** cd47d6b

**3. [Rule 1 - Bug] CFString pointer warning with CoreAudio**
- **Found during:** Task 1
- **Issue:** Direct `&cfName` pointer to `Optional<CFString>` triggers compiler warning about object references
- **Fix:** Wrapped with `withUnsafeMutablePointer(to:)` for safe pointer access
- **Files modified:** `VoiceType/Audio/AudioFormat.swift`
- **Commit:** cd47d6b

**4. [Rule 3 - Blocking] xcodebuild → swift build**
- **Found during:** Verification
- **Issue:** Plan verification commands use `xcodebuild -project VoiceType.xcodeproj` but project uses SPM/Package.swift (no xcodeproj)
- **Fix:** Used `swift build` instead
- **Commit:** N/A (verification only)

## Self-Check

- [x] `VoiceType/Audio/AudioFormat.swift` exists
- [x] `VoiceType/Audio/AudioBuffer.swift` exists
- [x] `VoiceType/Audio/AudioCaptureService.swift` exists
- [x] `VoiceType/AppCoordinator.swift` modified with audio integration
- [x] Commit cd47d6b exists (Task 1)
- [x] Commit aefdf97 exists (Task 2)
- [x] `swift build` passes cleanly

## Self-Check: PASSED
