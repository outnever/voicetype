---
phase: 01-foundation
verified: 2026-07-30T18:00:00Z
status: human_needed
score: 4/11 must-haves verified
behavior_unverified: 7
overrides_applied: 0
behavior_unverified_items:
  - truth: "用户从任意应用按住 Fn 键，应用检测到按键按下（keyDown/flagsChanged），松手时检测到释放（keyUp/flagsChanged）"
    test: "授予辅助功能权限后，在任意应用（TextEdit、Chrome、Terminal 等）按住 Fn 键"
    expected: "菜单栏图标状态变为 Recording，释放 Fn 后恢复 Idle"
    why_human: "CGEvent tap 需要运行时辅助功能权限 + 真实按键事件 — 编译验证通过但无法程序化验证 Fn 键的 flagsChanged 检测正确性"

  - truth: "用户从任意应用按下 Ctrl+Shift+C，应用检测到组合键按下"
    test: "授予辅助功能权限后，在任意应用按下 Ctrl+Shift+C"
    expected: "菜单栏图标状态短暂变为 Correcting（约3秒后自动恢复 Idle）"
    why_human: "Requires runtime hotkey testing with Accessibility permissions — build-only verification insufficient"

  - truth: "热键在系统所有应用中均可触发（全局），不限于前台应用"
    test: "在浏览器、编辑器、终端、Finder 等多个应用中分别测试 Fn 和 Ctrl+Shift+C"
    expected: "所有应用中热键均可触发，无应用例外"
    why_human: "Cross-application testing requires human interaction across multiple apps — cannot auto-verify from build"

  - truth: "热键权限丢失时（系统更新后 tccutil 重置），应用在 5 秒内检测到并通过通知/menu bar 状态提醒用户"
    test: "运行 tccutil reset Accessibility com.voicetype.app 模拟权限撤销"
    expected: "5 秒内 watchdog 检测到 tap 失活，菜单栏显示'热键权限丢失——请重新授予辅助功能权限'警告"
    why_human: "Watchdog behavior requires permission revocation simulation (tccutil) which is a manual system operation"

  - truth: "应用能从默认麦克风采集音频，输出 16kHz 单声道 Float32 PCM 原始数据"
    test: "授予麦克风权限后，调用 startAudioCapture()，检查 RingBuffer 中是否有非零 Float32 采样"
    expected: "RingBuffer.availableCount > 0 且采样值非零（非静音）"
    why_human: "音频采集需要运行时麦克风权限 + 真实音频硬件 — 编译验证通过但无法验证真实音频数据流"

  - truth: "用户插入/拔出 USB 麦克风或蓝牙耳机（如 AirPods）时，音频采集自动切换到新设备，不崩溃不无声"
    test: "在音频采集运行中：插入 USB 麦克风 → 观察设备切换；拔出 USB 麦克风 → 观察回退到内置麦克风"
    expected: "设备变更通知发送，currentInputDevice 更新，采集不中断、不崩溃"
    why_human: "Device hot-plug testing requires physical hardware changes — cannot auto-verify"

  - truth: "音频采集在 start() 调用后 500ms 内开始产生非零样本数据"
    test: "调用 start() 后计时，检查 RingBuffer 中首次出现非零采样的时间"
    expected: "< 500ms 内 RingBuffer 中有可读数据"
    why_human: "Timing measurement requires runtime execution with real audio hardware"
human_verification:
  - test: "从 Application Support 目录删除设置后首次启动 → 应看到顺序权限引导窗口，先麦克风说明（含中文说明文字），点击'Grant Microphone Access'触发系统 TCC 对话框"
    expected: "麦克风权限引导文字为中文'VoiceType 需要用麦克风将你说的转化成文字'；点击按钮触发系统 TCC 对话框"
    why_human: "TCC 对话框为 macOS 系统级 UI，无法程序化验证"

  - test: "麦克风授权后 → 自动进入步骤 2（辅助功能），显示中文说明，点击'Open System Settings'跳转到系统设置"
    expected: "辅助功能权限引导文字为中文'VoiceType 需要辅助功能权限才能将文字输入到你正在用的应用中'；点击按钮跳转到 System Settings → Privacy → Accessibility"
    why_human: "系统设置跳转为 macOS 系统级操作，无法程序化验证"

  - test: "在设置窗口中输入 OpenAI API 密钥（如 sk-test123），点击 Save → 关闭设置窗口 → 重新打开 → 检查 API key 显示"
    expected: "密钥显示为脱敏形式如 '••••st123'（末4位可见）"
    why_human: "Keychain 读写为 macOS 安全框架，脱敏显示需要 UI 交互验证"

  - test: "在 Finder 中查看 ~/Library/Preferences/com.voicetype.app.plist → 搜索 'sk-' → 确认无 API 密钥明文"
    expected: "plist 中无任何 API 密钥字符串"
    why_human: "需要人工通过 Finder/终端检查 plist 文件内容"

  - test: "菜单栏图标在不同权限状态下的颜色正确性：全部授予=绿色，缺一个=橙色，全缺=红色"
    expected: "权限状态变化时图标颜色实时更新"
    why_human: "视觉颜色感知需要人工判断"

  - test: "启动应用 → 观察菜单栏图标出现时间"
    expected: "1 秒内菜单栏图标出现（视觉可感知）"
    why_human: "时间感知需要人工判断，且受系统负载影响"
---

# Phase 1: Foundation — Verification Report

**Phase Goal:** 用户能够启动应用、授予权限、配置设置，且全局热键和音频采集通道正常工作
**Verified:** 2026-07-30T18:00:00Z
**Status:** human_needed
**Mode:** mvp
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Source | Status | Evidence |
|---|-------|--------|--------|----------|
| 1 | 用户启动应用后 1 秒内看到菜单栏图标，颜色反映权限状态（绿/橙/红） | SC-1, SHEL-01 | ✓ VERIFIED | `AppCoordinator.iconName = "mic.fill"` 立即设默认值；所有重操作在 `Task.detached` 异步执行；`MenuBarView.statusColor` 映射 `permissionStatus→green/orange/red` |
| 2 | 首次启动时分步引导权限：先麦克风（中文说明）→ 再辅助功能（中文说明） | SC-2, SHEL-02 | ✓ VERIFIED | `PermissionGateView` 含 `.microphone→.accessibility` 顺序步骤；中文说明文字符合 D-07；`PermissionManager` 含 TCC 检查 + AXIsProcessTrusted 轮询 |
| 3 | 菜单栏→Settings 打开独立设置窗口，可配置 API 密钥并在保存后看到脱敏显示 | SC-3, SHEL-03 | ✓ VERIFIED | `MenuBarView` 含 "Open Settings..." 按钮调用 `NSApp.sendAction(Selector(("showSettingsWindow:")))`；`SettingsView` 三标签页含 API 密钥区；`KeychainStore.obfuscatedValue()` 返回 `••••`+末4位 |
| 4 | API 密钥存储于 macOS Keychain（SecItem API），不落 UserDefaults/plist | SC-4, SHEL-04 | ✓ VERIFIED | `KeychainStore` 使用 `kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock`；所有 OSStatus 显式检查；`Defaults.swift` 明确禁止存密钥 |
| 5 | 按住 Fn 键 → 检测按下（recording），松手 → 检测释放（idle） | SC-5, HOTK-01 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `HotkeyManager.handleFlagsChanged()` 检测 `.maskSecondaryFn` 转换；`AppCoordinator.onDictationKeyDown→.recording / onDictationKeyUp→.idle`；编译通过、代码已连线 |
| 6 | 按下 Ctrl+Shift+C → 检测组合键触发 | HOTK-02 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `HotkeyManager.handleKeyEvent()` 检测 keyCode==8 + `.maskControl/.maskShift`；`correctionFiredInCurrentCycle` 防重复触发 |
| 7 | 热键在所有应用中全局触发 | HOTK-03 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap)`；回调返回 `Unmanaged.passUnretained(event)` 不消费事件 |
| 8 | 权限丢失后 5 秒内 watchdog 检测并提醒 | HOTK-04 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `startWatchdog(5.0)` 检查 `CGEvent.tapIsEnabled`；自动重启用 + 失败时通知 `.hotkeyTapDisabled`；事件心跳 30s 无事件触发告警 |
| 9 | 从默认麦克风采集 16kHz 单声道 Float32 PCM | AUDI-01 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `AudioCaptureService` 安装 `AVAudioEngine` input tap + `AVAudioConverter`→16kHz mono Float32；写入 `RingBuffer<Float>` |
| 10 | 设备热插拔自动切换，不崩溃不无声 | AUDI-02 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | CoreAudio `AudioObjectAddPropertyListenerBlock` 监听默认输入设备变更；`AVAudioEngineConfigurationChange` 观察者；`performDeviceRestart()` stop→start 循环 |
| 11 | 音频采集 start() 后 500ms 内产生非零样本 | 01-03 Plan | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `AudioCaptureService.start()` 立即调用 `engine.start()`；tap 回调在实时线程写入 RingBuffer |

**Score:** 4/11 truths verified (4 ✓ VERIFIED, 7 ⚠️ PRESENT_BEHAVIOR_UNVERIFIED)

---

## MVP User Flow Coverage

| # | User Flow Step | Expected | Evidence in Codebase | Status |
|---|---------------|----------|---------------------|--------|
| 1 | 启动应用 | 1 秒内菜单栏图标出现 | `VoiceTypeApp.swift:22` (MenuBarExtra), `AppCoordinator.swift:19` (iconName="mic.fill"), `AppCoordinator.swift:90` (Task.detached 异步初始化) | ✓ VERIFIED |
| 2 | 授予权限 | 分步引导：麦克风（中文说明）→ 辅助功能（中文说明）→ 系统设置 | `PermissionGateView.swift:98-102` (中文说明文字), `PermissionGateView.swift:150-176` (顺序请求+跳转系统设置) | ✓ VERIFIED |
| 3 | 配置设置 | 菜单栏→设置窗口→输入API密钥→脱敏显示 | `MenuBarView.swift:71,108` (Settings按钮), `SettingsView.swift` (3标签页设置), `KeychainStore.swift:114-119` (脱敏显示) | ✓ VERIFIED |
| 4 | 全局热键工作 | Fn 按住/释放检测, Ctrl+Shift+C 触发检测 | `HotkeyManager.swift:296-321` (Fn flagsChanged), `HotkeyManager.swift:263-287` (Ctrl+Shift+C keyDown) | ⚠️ BEHAVIOR_UNVERIFIED |
| 5 | 音频采集工作 | 16kHz mono Float32 PCM 持续采集 | `AudioCaptureService.swift:134-163` (AVAudioEngine tap + format conversion), `AudioBuffer.swift` (RingBuffer) | ⚠️ BEHAVIOR_UNVERIFIED |

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `VoiceType/VoiceTypeApp.swift` | @main 应用入口, MenuBarExtra + Settings 场景 | ✓ VERIFIED | 76 行，完整实现 MenuBarExtra + Settings + PermissionGate Window |
| `VoiceType/AppCoordinator.swift` | 中央状态机, 含全部回调和子系统集成 | ✓ VERIFIED | 263 行，拥有 HotkeyManager + AudioCaptureService + PermissionManager |
| `VoiceType/App/MenuBarView.swift` | 菜单栏下拉内容：状态 + 权限 + 快捷操作 | ✓ VERIFIED | 140 行，完整状态颜色 + 权限行 + Settings/Quit 按钮 |
| `VoiceType/App/PermissionGateView.swift` | 首次启动顺序权限引导 (D-07) | ✓ VERIFIED | 220 行，分步引导含中文说明文字 + 进度指示器 |
| `VoiceType/App/SettingsView.swift` | 设置窗口：API 密钥 + 热键显示 + 模型信息 | ✓ VERIFIED | 381 行，三标签页含 SecureField + Keychain 集成 |
| `VoiceType/Utilities/PermissionManager.swift` | TCC 权限状态检查（麦克风+辅助功能） | ✓ VERIFIED | 142 行，含 PermissionStatus 枚举（绿/橙/红）|
| `VoiceType/Utilities/AppState.swift` | 应用状态枚举 | ✓ VERIFIED | 16 行，idle/recording/transcribing/correcting/error |
| `VoiceType/Utilities/Logging.swift` | OSLog 封装，子系统日志 | ✓ VERIFIED | 22 行，app/hotkey/audio/settings/permission Logger |
| `VoiceType/Settings/KeychainStore.swift` | SecItem API 封装：store/retrieve/delete/obfuscatedValue | ✓ VERIFIED | 146 行，完整 SecItem CRUD + OSStatus 检查 |
| `VoiceType/Settings/SettingsStore.swift` | @AppStorage + Keychain 集成 | ✓ VERIFIED | 72 行，API key CRUD 委托给 KeychainStore |
| `VoiceType/Settings/Defaults.swift` | UserDefaults key 常量 + 默认值 | ✓ VERIFIED | 51 行，明确禁止存 API 密钥 |
| `VoiceType/Hotkeys/HotkeyManager.swift` | CGEvent tap 生命周期管理 | ✓ VERIFIED | 417 行，完整 tap 注册+回调+watchdog+heartbeat |
| `VoiceType/Hotkeys/HotkeyConfiguration.swift` | 热键定义（Fn + Ctrl+Shift+C） | ✓ VERIFIED | 59 行，HotkeyMode/HotkeyDefinition/HotkeyDefaults/HotkeyError |
| `VoiceType/Audio/AudioCaptureService.swift` | AVAudioEngine 封装 | ✓ VERIFIED | 458 行，完整 tap+格式转换+设备监控+静音检测 |
| `VoiceType/Audio/AudioBuffer.swift` | 线程安全环形缓冲区 | ✓ VERIFIED | 152 行，os_unfair_lock + SPSC 模式，零分配 write/read |
| `VoiceType/Audio/AudioFormat.swift` | PCM 格式常量 | ✓ VERIFIED | 92 行，CoreAudio 设备名查询 |
| `Package.swift` | SPM 包清单 | ✓ VERIFIED | 28 行，WhisperKit + OpenAI + swift-log 依赖 |
| `VoiceType/Info.plist` | 应用配置 | ✓ VERIFIED | LSUIElement=YES, NSMicrophoneUsageDescription 含中文 |

**All 18 artifacts: exist, substantive, and wired.** No stubs, no missing files.

---

## Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|-----|--------|----------|
| VoiceTypeApp.swift | AppCoordinator.swift | `@StateObject private var coordinator` (line 14) | ✓ WIRED | Import verified, used in MenuBarExtra + Settings |
| MenuBarView.swift | PermissionManager | `coordinator.permissionManager.microphoneGranted/accessibilityGranted` (lines 60, 66) | ✓ WIRED | Status derived via AppCoordinator → PermissionManager |
| SettingsView.swift | KeychainStore | `SettingsStore.keychain.store/obfuscatedValue` (via SettingsStore) | ✓ WIRED | API key save → KeychainStore.store(); display → obfuscatedValue() |
| HotkeyManager.swift | AppCoordinator.swift | `coordinator?.onDictationKeyDown/Up/onCorrectionKeyPress` callbacks (lines 276, 310, 318) | ✓ WIRED | Callbacks dispatch via DispatchQueue.main.async |
| HotkeyManager.swift | Logging.swift | `Log.hotkey.info/warning/error` throughout | ✓ WIRED | Logger.hotkey used for all lifecycle events |
| AudioCaptureService.swift | AudioBuffer.swift | `self.buffer.write(samples)` (line 161) | ✓ WIRED | Tap callback writes converted samples to RingBuffer |
| AudioCaptureService.swift | Logging.swift | `Log.audio.info/warning/error` throughout | ✓ WIRED | Logger.audio used for all engine events |
| AudioCaptureService.swift | AppCoordinator.swift | `Notification.Name.audioDeviceChanged/.audioSilenceDetected` (lines 9, 13) | ✓ WIRED | AppCoordinator.setupAudioObservers() listens for both |
| AppCoordinator.swift | HotkeyManager | `hotkeyManager.register()` (line 224), `startWatchdog()` (line 226) | ✓ WIRED | Registration in initializeSubsystems() after permission check |

**All 9 key links: WIRED.**

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| MenuBarView | `coordinator.statusMessage` | AppCoordinator → PermissionManager / HotkeyManager | ✓ Real strings from subsystem state | ✓ FLOWING |
| MenuBarView | `coordinator.permissionStatus` | PermissionManager.PermissionStatus (mic+ax booleans) | ✓ Derived from TCC API results | ✓ FLOWING |
| SettingsView | `settingsStore.apiKeyDisplayString()` | KeychainStore.obfuscatedValue() → SecItemCopyMatching | ✓ Real Keychain data (runtime only) | ✓ FLOWING (code path complete) |
| PermissionGateView | `coordinator.permissionManager.microphoneGranted` | AVCaptureDevice.authorizationStatus | ✓ Real TCC state | ✓ FLOWING |
| AudioCaptureService | `self.buffer` | AVAudioEngine input node tap → AVAudioConverter | ✓ Real audio (runtime only) | ✓ FLOWING (code path complete) |

---

## Behavioral Spot-Checks

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| Build succeeds | `swift build` | Build complete! (0.10s) | ✓ PASS |
| Swift files compile cleanly | `swift build 2>&1 \| grep error` | No errors | ✓ PASS |

**Note:** No runtime spot-checks possible — this is a macOS GUI app requiring Accessibility + Microphone permissions. All behavior-dependent truths route to human verification.

---

## CONTEXT.md Decision Compliance

| Decision | Description | Implementation | Status |
|----------|-------------|---------------|--------|
| D-01 | MenuBarExtra 场景作为主入口 | `VoiceTypeApp.swift:22` MenuBarExtra + `.menuBarExtraStyle(.menu)` | ✅ |
| D-02 | Settings 独立设置窗口 | `VoiceTypeApp.swift:39` Settings { SettingsView() } | ✅ |
| D-03 | 听写热键 Fn (hold-to-talk) | `HotkeyConfiguration.swift:24-29` dictation with keyCode 63, holdToTalk | ✅ |
| D-04 | 纠错热键 Ctrl+Shift+C (press-to-trigger) | `HotkeyConfiguration.swift:32-37` correction with keyCode 8, pressToTrigger | ✅ |
| D-05 | CGEvent.tapCreate (非 Carbon) | `HotkeyManager.swift:119-129` CGEvent.tapCreate(.cgSessionEventTap) | ✅ |
| D-06 | Watchdog 权限监控 | `HotkeyManager.swift:336-400` 5s watchdog + heartbeat + NotificationCenter | ✅ |
| D-07 | 顺序权限引导（麦克风→辅助功能） | `PermissionGateView.swift:98-176` .microphone→.accessibility steps | ✅ |
| D-08 | 菜单栏图标颜色（绿/橙/红） | `PermissionManager.swift:120-141` PermissionStatus enum + MenuBarView.statusColor | ✅ |
| D-09 | AVAudioEngine / 16kHz mono Float32 | `AudioCaptureService.swift:119-163` tap + AVAudioConverter | ✅ |
| D-10 | 音频设备热插拔监控 | `AudioCaptureService.swift:240-288` CoreAudio + AVAudioEngineConfigurationChange | ✅ |
| D-11 | 子系统文件夹结构 | All 5 directories: App/, Hotkeys/, Audio/, Settings/, Utilities/ | ✅ |
| D-12 | Keychain (SecItem)，禁止 UserDefaults | `KeychainStore.swift` SecItem API; `Defaults.swift:6-8` explicit prohibition | ✅ |

**12/12 CONTEXT.md decisions respected.**

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SHEL-01 | 01-01 | 菜单栏图标 1 秒内出现 | ✓ SATISFIED | AppCoordinator.iconName="mic.fill" + Task.detached async init |
| SHEL-02 | 01-01 | 首次启动顺序权限引导 | ✓ SATISFIED | PermissionGateView sequential flow with Chinese text |
| SHEL-03 | 01-01 | 菜单栏打开设置窗口 | ✓ SATISFIED | MenuBarView → NSApp.sendAction + SettingsView |
| SHEL-04 | 01-01 | API 密钥存于 Keychain | ✓ SATISFIED | KeychainStore SecItem API; no key in plist |
| HOTK-01 | 01-02 | Fn hold-to-talk | ✓ SATISFIED* | HotkeyManager flagsChanged + AppCoordinator state (behavior-unverified) |
| HOTK-02 | 01-02 | Ctrl+Shift+C press-to-trigger | ✓ SATISFIED* | HotkeyManager keyDown + correctionFiredInCurrentCycle (behavior-unverified) |
| HOTK-03 | 01-02 | 全局热键 | ✓ SATISFIED* | .cgSessionEventTap + non-consuming events (behavior-unverified) |
| HOTK-04 | 01-02 | 权限丢失检测 | ✓ SATISFIED* | Watchdog 5s + heartbeat 30s (behavior-unverified) |
| AUDI-01 | 01-03 | 16kHz 单声道 Float32 PCM | ✓ SATISFIED* | AVAudioEngine tap + format converter + RingBuffer (behavior-unverified) |
| AUDI-02 | 01-03 | 设备热插拔 | ✓ SATISFIED* | CoreAudio listener + AVAudioEngineConfigurationChange (behavior-unverified) |

> *SATISFIED at code level: implementation is present, wired, and compiles. Runtime behavior verification requires human testing with macOS hardware.

**10/10 requirements satisfied at code level.**

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| SettingsView.swift | 45 | `// Whisper model selection (placeholder for Phase 2)` | ℹ️ Info | Documented deferral — Phase 2 implements model selection UI |
| SettingsView.swift | 50 | `// Language preference (placeholder for Phase 2)` | ℹ️ Info | Documented deferral — Phase 2 implements language selection |
| AppCoordinator.swift | 161 | `// Auto-reset after a short delay (placeholder until Phase 3)` | ℹ️ Info | Documented stub — Phase 3 replaces with AI correction pipeline |

**No blockers.** No TBD/FIXME/XXX debt markers. All "placeholder" references are documented Phase 2/3 deferrals with explicit tracking in SUMMARY.md known-stubs tables.

---

## 01-CHECK.md Blocker Resolution

The blocker from plan-check (RESEARCH.md Open Questions not marked RESOLVED) has been **resolved**:
- Section header: `## Open Questions (RESOLVED)` ✓
- All 3 questions individually marked `(RESOLVED)` ✓
- Fn key → flagsChanged handler implemented ✓
- Entitlements → DMG direct distribution as primary channel ✓
- macOS 15 stability → aggressive watchdog + re-enable logic implemented ✓

---

## Human Verification Required

These items cannot be verified programmatically — they require a human to run the app on macOS with real permissions and hardware.

### Behavior-Unverified Truths (7 items)

#### 1. Fn 键 Hold-to-Talk 检测

**Test:** 授予辅助功能权限后，在任意应用（TextEdit、Chrome、Terminal 等）按住 Fn 键
**Expected:** 菜单栏图标状态变为 "Recording"，释放 Fn 后恢复 "Idle"，状态切换即时（无延迟）
**Why human:** CGEvent tap 需要运行时辅助功能权限 + 真实按键事件 — 编译验证通过但无法程序化验证 Fn 键的 flagsChanged 检测正确性

#### 2. Ctrl+Shift+C 纠错热键检测

**Test:** 授予辅助功能权限后，在任意应用按下 Ctrl+Shift+C
**Expected:** 菜单栏图标状态短暂变为 "Correcting"（约3秒后自动恢复 Idle），不会重复触发
**Why human:** 组合键检测需要真实按键事件和修饰键状态 — 编译验证无法验证

#### 3. 全局热键（跨应用）

**Test:** 在浏览器（Chrome）、编辑器（VS Code/TextEdit）、终端（Terminal）、Finder 等多个应用中分别测试 Fn 和 Ctrl+Shift+C
**Expected:** 所有应用中热键均可触发，无应用例外，热键事件不干扰正常输入
**Why human:** 跨应用测试需要人工在多个应用间切换 — 无法自动验证

#### 4. Watchdog 权限丢失检测

**Test:** 运行 `tccutil reset Accessibility com.voicetype.app` 模拟权限撤销
**Expected:** 5 秒内 watchdog 检测到 tap 失活，菜单栏显示 "Hotkey permission lost — re-grant in System Settings → Privacy → Accessibility" 警告；事件心跳 30s 无事件触发告警
**Why human:** `tccutil` 为系统级命令，运行时权限撤销为手动操作

#### 5. 音频采集（16kHz mono Float32 PCM）

**Test:** 授予麦克风权限后，调用 startAudioCapture()，检查环形缓冲区中是否有非零采样
**Expected:** RingBuffer.availableCount > 0 且采样值包含非零数据（非全静音），格式为 Float32
**Why human:** 音频采集需要运行时麦克风权限 + 真实音频硬件 — 编译验证通过但无法验证真实音频数据流

#### 6. 音频设备热插拔

**Test:** 在音频采集运行中：(a) 插入 USB 麦克风 → 观察设备切换；(b) 拔出 USB 麦克风 → 观察回退到内置麦克风；(c) 连接/断开 AirPods → 观察切换
**Expected:** 设备变更通知发送，AppCoordinator.currentInputDevice 更新为正确设备名，采集不中断、不崩溃、不无声
**Why human:** 设备热插拔测试需要物理硬件操作 — 无法自动验证

#### 7. 音频采集启动延迟（<500ms 非零样本）

**Test:** 调用 start() 后计时，检查 RingBuffer 中首次出现非零采样的时间
**Expected:** < 500ms 内 RingBuffer 中有可读数据
**Why human:** 时间测量需要运行时执行 + 真实音频硬件

### Additional UI/UX Checks (6 items)

#### 8. 权限引导窗口中文文字正确性

**Test:** 从 Application Support 目录删除设置后首次启动 → 观察权限引导窗口
**Expected:** 步骤1 显示 "VoiceType 需要用麦克风将你说的转化成文字"；步骤2 显示 "VoiceType 需要辅助功能权限才能将文字输入到你正在用的应用中"
**Why human:** 中文文字渲染和阅读体验需人工判断

#### 9. API 密钥脱敏显示

**Test:** 在设置窗口中输入 OpenAI API 密钥（如 sk-test1234），点击 Save → 关闭设置窗口 → 重新打开 → 检查 API key 显示
**Expected:** 密钥显示为脱敏形式如 '••••1234'（末4位可见），且 SecureField 为空（不保留明文）
**Why human:** Keychain 读写为 macOS 安全框架，UI 脱敏显示需要交互验证

#### 10. plist 中无 API 密钥明文

**Test:** 在 Finder 中查看 ~/Library/Preferences/com.voicetype.app.plist → 搜索 'sk-' → 确认无 API 密钥明文
**Expected:** plist 中无任何 API 密钥字符串，仅含非敏感偏好配置
**Why human:** 需要人工通过 Finder/终端检查 plist 文件内容

#### 11. 菜单栏图标颜色切换

**Test:** 分别测试三种权限状态（全授予、缺一个、全缺）下的菜单栏图标颜色
**Expected:** 全部授予=绿色，缺一个=橙色，全缺=红色；状态切换时图标颜色实时更新
**Why human:** 视觉颜色感知需要人工判断

#### 12. 启动速度（1 秒内图标）

**Test:** 冷启动应用 → 观察菜单栏图标出现时间
**Expected:** 1 秒内菜单栏图标出现（视觉可感知），不会出现长时间无响应
**Why human:** 时间感知需要人工判断，且受系统负载影响

---

## Gaps Summary

**No gaps found.** All 18 artifacts exist and are substantive. All 9 key links are wired. All 12 CONTEXT.md decisions are respected. All 10 requirements have implementation evidence.

The phase is **code-complete** — all planned features are implemented and compile successfully. However, **7 of 11 truths are behavior-dependent** (CGEvent tap, audio capture, watchdog) and require human verification on real macOS hardware with Accessibility and Microphone permissions.

---

_Verified: 2026-07-30T18:00:00Z_
_Verifier: gsd-verifier_
