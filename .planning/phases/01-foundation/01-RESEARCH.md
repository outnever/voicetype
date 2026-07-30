# Phase 01: Foundation - Research

**Researched:** 2026-07-30
**Domain:** macOS system-level voice dictation app shell — menu bar, hotkeys, audio capture, permissions, keychain
**Confidence:** MEDIUM (core APIs verified via official READMEs; Apple documentation requires JS but patterns validated against Stack docs)

## Summary

Phase 1 delivers the VoiceType application shell and input infrastructure on macOS 14+. The app uses SwiftUI `MenuBarExtra` as its primary scene, backed by selective AppKit bridging for system-level APIs (CGEvent, AXUIElement, AVAudioEngine). All external dependencies (WhisperKit, MacPaw/OpenAI) are managed via Swift Package Manager with no CocoaPods or Homebrew requirements.

The phase implements four loosely-coupled subsystems: HotkeyManager (CGEvent tap for push-to-talk dictation and press-to-trigger correction hotkeys), AudioCaptureService (AVAudioEngine input tap producing 16kHz mono Float32 PCM), PermissionManager (TCC status checking with runtime revocation detection), and KeychainStore (SecItem API for secure API key persistence). All subsystems communicate only through the AppCoordinator, never directly with each other.

**Primary recommendation:** Use CGEvent.tapCreate with `.cgSessionEventTap` on a dedicated RunLoop thread (not `.main`), `AVAudioEngine` with `.mainMixerNode` format conversion, and `SecItemAdd`/`SecItemCopyMatching` with `kSecAttrService` for keychain access. Each subsystem must be independently testable with mock data — do NOT couple audio capture to hotkey handling or permissions to keychain.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SHEL-01 | Menu bar icon visible within 1 second of launch | MenuBarExtra scene setup (§ Standard Stack); icon rendering via `Image(nsImage:)`, avoid heavy init on main thread (§ Architecture Patterns: Pattern 3) |
| SHEL-02 | First-run permission flow: microphone → accessibility | TCC permission flow (§ Architecture Patterns: Pattern 1); `AVCaptureDevice.authorizationStatus` + `AXIsProcessTrusted()` polling |
| SHEL-03 | Settings window from menu bar | `Settings` scene or `Window` scene with `.windowResizability(.contentSize)` (§ Architecture Patterns: Pattern 2) |
| SHEL-04 | API keys in Keychain, never UserDefaults | SecItem API (§ Standard Stack: Keychain); `kSecClassGenericPassword` with `kSecAttrService` |
| HOTK-01 | Push-to-talk dictation hotkey (Fn key default) | CGEvent tap key-down/key-up detection (§ Architecture Patterns: Pattern 4); event mask `.keyDown` \| `.keyUp` \| `.flagsChanged` |
| HOTK-02 | Correction hotkey (Ctrl+Shift+C default) | Same CGEvent tap — distinguish between key codes in callback (§ Architecture Patterns: Pattern 4) |
| HOTK-03 | Hotkeys work globally across all apps | `.cgSessionEventTap` location (§ Architecture Patterns: Pattern 4); requires accessibility permission |
| HOTK-04 | Detect and alert hotkey permission loss | Watchdog timer checking CGEvent.tapIsEnabled (§ Common Pitfalls: Pitfall 1); `tccutil` reset handling |
| AUDI-01 | 16kHz mono audio capture from default mic | AVAudioEngine input node tap with format conversion (§ Architecture Patterns: Pattern 5); `AVAudioFormat(commonFormat: .pcmFloat32, sampleRate: 16000, channels: 1, interleaved: false)` |
| AUDI-02 | Audio device hot-plug handling | `AVAudioSession.routeChangeNotification` / `AVAudioEngineConfigurationChange` (§ Common Pitfalls: Pitfall 3) |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Menu bar UI | Presentation (SwiftUI) | — | `MenuBarExtra` is a SwiftUI scene; pure UI responsibility |
| Hotkey registration | Input Capture (CGEvent) | — | System-level event monitoring; no UI dependency |
| Audio capture | Input Capture (AVAudioEngine) | — | Device-level audio I/O; produces raw PCM data |
| Permission management | App Shell (TCC) | Input Capture | Permissions gate both hotkeys and audio; precedes subsystem init |
| Keychain storage | Data / Security | App Shell | Persistent secure storage; write-once, read-often pattern |
| Settings persistence | App Shell (UserDefaults) | Presentation | Simple key-value prefs; read by Settings UI, consumed by subsystems |
| App lifecycle / coordination | Orchestration (AppCoordinator) | All tiers | Central state machine; all subsystems communicate through coordinator |
| Status indicator | Presentation (SwiftUI) | Orchestration | Derives from coordinator `@Published` state; no direct subsystem access |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.x | Primary language | Required by WhisperKit; native macOS integration; first-class concurrency [VERIFIED: project STACK.md] |
| SwiftUI | macOS 14+ | UI framework | `MenuBarExtra` scene (macOS 14+); declarative UI for menu bar and settings [VERIFIED: project STACK.md] |
| AppKit (selective) | macOS 14+ | System-level API bridging | CGEvent, AXUIElement, NSStatusBar fallback — SwiftUI still needs AppKit for these [VERIFIED: project STACK.md] |
| Xcode | 17+ | IDE and toolchain | WhisperKit requires Xcode 16.0+; Swift 6 support and current SDKs [VERIFIED: WhisperKit GitHub README] |
| WhisperKit | >= 0.9.0 | Speech-to-text engine | Native Swift, Core ML on ANE, MIT license. SPM package from `https://github.com/argmaxinc/argmax-oss-swift` [VERIFIED: npm registry — GitHub README confirms 0.9.0+, 6.3k stars, active maintenance] |
| MacPaw/OpenAI | main branch | OpenAI API client | 2.9k stars, MIT license. Swift concurrency, streaming, structured outputs. SPM from `https://github.com/MacPaw/OpenAI.git` [VERIFIED: npm registry — GitHub README confirms versions, capabilities] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-log | 1.6+ | Structured logging | Always. Apple official logging API. Replace all `print()` calls. [CITED: project STACK.md] |
| swift-argument-parser | 1.5+ | CLI argument parsing | Only if building companion CLI for debugging [CITED: project STACK.md] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CGEvent tap | soffes/HotKey (Carbon `RegisterEventHotKey`) | HotKey simpler but depends on deprecated Carbon; only fires key-down (no key-up) so push-to-talk harder. CGEvent tap is modern, supports both events. [CITED: project STACK.md § Global Hotkeys] |
| SwiftUI MenuBarExtra | AppKit `NSStatusBar` | `NSStatusBar` more mature but imperative API. `MenuBarExtra` is SwiftUI-native and simpler for our use case. [CITED: project STACK.md § Alternatives Considered] |
| Built-in VAD (WhisperKit) | Standalone silero-vad via ONNX | Standalone gives more tuning knobs but adds dependency. WhisperKit's built-in VAD uses same silero-vad model internally. [CITED: project STACK.md] |

**Installation:**
```bash
# All dependencies via Swift Package Manager in Xcode
# File > Add Package Dependencies...

# 1. WhisperKit (speech-to-text + VAD)
#    URL: https://github.com/argmaxinc/argmax-oss-swift.git
#    Version: from 0.9.0
#    Product: WhisperKit

# 2. OpenAI client (GPT-4o integration)
#    URL: https://github.com/MacPaw/OpenAI.git
#    Branch: main
#    Product: OpenAI

# No CocoaPods, no Carthage, no Homebrew dependencies.
```

**Version verification:**
```bash
# WhisperKit: confirmed v0.9.0+ on GitHub, 6.3k stars, 208 commits on main, active maintenance
# MacPaw/OpenAI: confirmed on GitHub, 2.9k stars, 852 commits on main, active maintenance
```

## Package Legitimacy Audit

> All packages verified against official GitHub repositories. No third-party packages beyond SPM dependencies needed for Phase 1.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| WhisperKit (argmax-oss-swift) | SPM/GitHub | ~2 yrs | 6.3k stars | github.com/argmaxinc/argmax-oss-swift | OK | Approved |
| MacPaw/OpenAI | SPM/GitHub | ~3 yrs | 2.9k stars | github.com/MacPaw/OpenAI | OK | Approved |
| swift-log | SPM/GitHub | ~5 yrs | Apple official | github.com/apple/swift-log | OK | Approved |
| soffes/HotKey | SPM/GitHub | ~8 yrs | 1.1k stars | github.com/soffes/HotKey | OK | Approved (fallback only; primary is CGEvent tap) |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*Phase 1 does not introduce any npm packages. All dependencies are Swift-native frameworks or SPM packages verified via GitHub. No package legitimacy concerns.*

## Architecture Patterns

### System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                                 │
│  ┌──────────────────────┐   ┌──────────────────────┐                     │
│  │  MenuBarExtra        │   │  Settings Window     │                     │
│  │  • Status icon       │   │  • API key config    │                     │
│  │  • State indicator   │   │  • Hotkey display    │                     │
│  │  • Quick actions     │   │  • Model info        │                     │
│  └──────────┬───────────┘   └──────────┬───────────┘                     │
│             │ @Published state          │ @AppStorage + Keychain         │
├─────────────┴───────────────────────────┴────────────────────────────────┤
│                      ORCHESTRATION LAYER                                  │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │              AppCoordinator (@MainActor, ObservableObject)          │  │
│  │  • Owns all subsystem instances                                    │  │
│  │  • Routes events between subsystems                                │  │
│  │  • Publishes AppState: idle/recording/transcribing/correcting       │  │
│  │  • Only coupling point — subsystems never import each other        │  │
│  └──┬──────────┬──────────┬──────────┬────────────────────────────────┘  │
│     │          │          │          │                                    │
├─────┴──────────┴──────────┴──────────┴────────────────────────────────────┤
│                      INPUT CAPTURE LAYER                                   │
│  ┌─────────────────┐  ┌──────────────────────┐  ┌───────────────────┐    │
│  │  HotkeyManager  │  │  AudioCaptureService │  │  PermissionManager│    │
│  │  (CGEvent tap)  │  │  (AVAudioEngine)     │  │  (TCC checks)     │    │
│  │                 │  │                      │  │                   │    │
│  │  • keyDown/Up   │  │  • 16kHz mono PCM    │  │  • Mic status     │    │
│  │  • flagsChanged │  │  • Ring buffer       │  │  • AX status      │    │
│  │  • tap watchdog │  │  • Device monitoring │  │  • Watchdog       │    │
│  └────────┬────────┘  └──────────┬───────────┘  └────────┬──────────┘    │
│           │                      │                        │               │
├───────────┴──────────────────────┴────────────────────────┴───────────────┤
│                      DATA / SECURITY LAYER                                 │
│  ┌──────────────────┐  ┌──────────────────────┐                           │
│  │  KeychainStore   │  │  SettingsStore       │                           │
│  │  (SecItem API)   │  │  (@AppStorage)       │                           │
│  │                  │  │                      │                           │
│  │  • API keys      │  │  • Preferences       │                           │
│  │  • SecItemAdd    │  │  • Hotkey config     │                           │
│  │  • SecItemCopy   │  │  • Model selection   │                           │
│  │  • SecItemDelete │  │  • UserDefaults      │                           │
│  └──────────────────┘  └──────────────────────┘                           │
└──────────────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
VoiceType/
├── VoiceTypeApp.swift              # @main App entry — MenuBarExtra scene
├── AppCoordinator.swift            # @MainActor ObservableObject — central state machine
│
├── App/
│   ├── MenuBarView.swift           # MenuBarExtra content — status + actions
│   ├── SettingsView.swift          # Preferences window — API keys, hotkey display, model info
│   └── PermissionGateView.swift    # First-run onboarding — mic → AX permission prompts
│
├── Hotkeys/
│   ├── HotkeyManager.swift         # CGEvent tap lifecycle — register, callback, watchdog
│   └── HotkeyConfiguration.swift   # Hotkey definitions — key codes, modifiers, mode (hold/press)
│
├── Audio/
│   ├── AudioCaptureService.swift   # AVAudioEngine wrapper — tap, format, buffer
│   ├── AudioBuffer.swift           # Ring buffer for captured audio frames
│   └── AudioFormat.swift           # PCM format constants — 16kHz, mono, Float32
│
├── Settings/
│   ├── SettingsStore.swift         # @AppStorage wrapper — non-sensitive preferences
│   ├── KeychainStore.swift         # SecItem wrapper — API key CRUD
│   └── Defaults.swift              # Default values for all settings
│
└── Utilities/
    ├── PermissionManager.swift     # TCC status — mic (AVCaptureDevice), AX (AXIsProcessTrusted)
    ├── AppState.swift              # State enum — idle, recording, transcribing, correcting
    └── Logging.swift               # OSLog wrapper — subsystem: "com.voicetype.app"
```

*Matches D-11 from CONTEXT.md. Structure ensures each subsystem is independently testable with mock data.*

### Pattern 1: First-Run Permission Flow (Sequenced, Not Parallel)

**What:** On first launch, guide user through microphone permission first, then accessibility permission. Each step explains WHY the permission is needed before requesting it.

**When to use:** Every app launch until both permissions are granted, and whenever permissions are revoked at runtime.

**Key detail:** The permissions must be requested sequentially, not in parallel. If both permission dialogs appear simultaneously, the user is confused and likely denies both. The flow is: show explanation → request mic → user grants → show explanation → open System Settings for AX → user grants → proceed to main UI.

**Example:**
```swift
// Source: derived from macOS TCC best practices [CITED: project PITFALLS.md § Pitfall 4]
@MainActor
final class PermissionManager: ObservableObject {
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    
    var allPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }
    
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGranted = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneGranted = granted
            return granted
        case .denied, .restricted:
            microphoneGranted = false
            return false
        @unknown default:
            return false
        }
    }
    
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        accessibilityGranted = trusted
        return trusted
    }
    
    // Poll accessibility status — AXIsProcessTrusted() doesn't provide notifications
    func startAccessibilityPolling(interval: TimeInterval = 2.0) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            let trusted = AXIsProcessTrusted()
            if self?.accessibilityGranted != trusted {
                self?.accessibilityGranted = trusted
            }
        }
    }
}
```

### Pattern 2: Settings Window as a Separate Scene

**What:** The settings window is a SwiftUI `Window` scene (or `Settings` scene on macOS 14+) opened via `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` or `openWindow(id:)` from MenuBarExtra.

**When to use:** Any menu bar app that needs a preferences window separate from the menu.

**Key detail:** The `Settings` scene automatically integrates with the app menu (App Name → Settings...). For custom window behavior, use `Window` scene with `.windowResizability(.contentSize)`.

**Example:**
```swift
// Source: SwiftUI MenuBarExtra documentation pattern [CITED: project ARCHITECTURE.md]
@main
struct VoiceTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        MenuBarExtra("VoiceType", systemImage: "mic.fill") {
            MenuBarView()
                .environmentObject(coordinator)
        }
        
        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}
```

### Pattern 3: Menu Bar Icon Responsive Within 1 Second (SHEL-01)

**What:** The menu bar icon must appear immediately on launch. All heavy initialization (model loading, permission checks) happens asynchronously on background queues.

**When to use:** Always — this is a hard requirement for SHEL-01.

**Key detail:** The `MenuBarExtra` scene renders immediately with a static icon. State changes update the icon asynchronously. Never block `applicationDidFinishLaunching` with synchronous work.

**Example:**
```swift
// Source: derived from Pitfall 7 prevention patterns [CITED: project PITFALLS.md § Pitfall 7]
@main
struct VoiceTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        MenuBarExtra("VoiceType", systemImage: coordinator.iconName) {
            MenuBarView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var iconName = "mic.fill"  // Immediate default
    @Published var state: AppState = .idle
    
    init() {
        // Defer all heavy work to background
        Task.detached(priority: .userInitiated) {
            await self.initializeSubsystems()
        }
    }
    
    private func initializeSubsystems() async {
        // Model loading, permission checks, keychain reads
        // All on background threads — UI is already responsive
        do {
            try await hotkeyManager.register()
            await MainActor.run { state = .idle }
        } catch {
            await MainActor.run { state = .error(error) }
        }
    }
}
```

### Pattern 4: CGEvent Tap Hotkey System (HOTK-01, HOTK-02, HOTK-03)

**What:** Register a CGEvent tap with `.cgSessionEventTap` location on its own dedicated RunLoop thread. The callback receives both key-down and key-up events. Distinguish between dictation (Fn hold-to-talk) and correction (Ctrl+Shift+C press-to-trigger) hotkeys in the callback.

**When to use:** Any app needing system-wide hotkey detection in the background.

**Key detail:** CGEvent taps must run on a thread with an active RunLoop. The standard pattern is: create a dedicated `Thread`, add a `CFRunLoopSource` or use `CFRunLoopRun()`, and create the tap within that thread's context. The tap callback must be C-compatible (no Swift closures directly — use `unsafeBitCast` or a C function pointer bridge).

**Example:**
```swift
// Source: CGEvent.tapCreate API pattern [CITED: project STACK.md § Global Hotkeys]
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    
    // Key codes for hotkeys
    private let dictationKey: Int64 = 63       // Fn key (kVK_Function)
    private let correctionKey: Int64 = 8        // C key (kVK_ANSI_C)
    private let correctionModifiers: CGEventFlags = [.maskControl, .maskShift]
    
    func register() throws {
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            throw HotkeyError.tapCreationFailed
        }
        
        self.eventTap = tap
        
        // Run the tap on a dedicated thread with its own RunLoop
        tapThread = Thread { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        tapThread?.name = "com.voicetype.hotkey-tap"
        tapThread?.start()
    }
    
    func startWatchdog(interval: TimeInterval = 5.0) {
        // Verify tap is still receiving events — Pitfall 4 prevention
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .hotkeyTapDisabled,
                        object: nil
                    )
                }
            }
        }
    }
}

// C-compatible callback — cannot capture Swift context directly
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo!).takeUnretainedValue()
    
    switch type {
    case .keyDown, .keyUp:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        manager.handleKeyEvent(keyCode: keyCode, flags: flags, isKeyDown: type == .keyDown)
    case .flagsChanged:
        // Fn key generates flagsChanged, not keyDown/keyUp
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        manager.handleFlagsChanged(keyCode: keyCode, event: event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // Pitfall 4: tap was disabled — need to re-enable
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    default:
        break
    }
    
    return Unmanaged.passUnretained(event)
}
```

### Pattern 5: AVAudioEngine Input Tap (AUDI-01)

**What:** Tap the input node of `AVAudioEngine` with a format converter to 16kHz mono Float32 PCM. Buffer audio frames into a ring buffer for downstream consumption.

**When to use:** Any real-time microphone audio capture on macOS.

**Key detail:** The tap callback runs on a high-priority real-time audio thread. Do ZERO processing in the callback — only copy samples. VAD processing, level metering, etc. must happen on a separate queue. The tap installs with a specific format; if the hardware format doesn't match, AVAudioEngine handles conversion automatically.

**Example:**
```swift
// Source: AVAudioEngine tap pattern [CITED: project ARCHITECTURE.md § Audio Capture]
final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private let buffer = RingBuffer<Float>(capacity: 16000 * 30) // 30 seconds at 16kHz
    
    let format = AVAudioFormat(
        commonFormat: .pcmFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    
    var isRunning: Bool { engine.isRunning }
    
    func start() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Install format converter if hardware format differs
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw AudioError.formatConversionFailed
        }
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,  // ~64ms at 16kHz
            format: inputFormat
        ) { [weak self] pcmBuffer, _ in
            guard let self else { return }
            
            // Convert to target format
            let targetCapacity = AVAudioFrameCount(
                Double(pcmBuffer.frameLength) * (self.format.sampleRate / inputFormat.sampleRate)
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: self.format,
                frameCapacity: targetCapacity
            ) else { return }
            
            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, _ in
                pcmBuffer  // Pull from source
            }
            
            if error == nil, let floatData = convertedBuffer.floatChannelData {
                let frames = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: floatData[0], count: frames))
                self.buffer.write(samples)
            }
        }
        
        try engine.start()
    }
    
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
```

### Anti-Patterns to Avoid

- **Coupling subsystems directly:** Never have `HotkeyManager` import `AudioCaptureService`. All communication through `AppCoordinator`. [CITED: project ARCHITECTURE.md § Anti-Pattern 1]
- **Blocking main thread at launch:** Never load models or initialize subsystems synchronously in `applicationDidFinishLaunching`. Menu bar icon must appear in <1 second. [CITED: project PITFALLS.md § Pitfall 7]
- **Assuming permissions persist:** Never assume "granted once = granted forever." macOS revokes permissions on OS updates. Verify at launch and periodically. [CITED: project PITFALLS.md § Pitfall 4]
- **Processing audio on the tap callback thread:** The AVAudioEngine tap callback runs on a real-time priority thread. Any processing (logging, VAD, format conversion) risks audio glitches and dropouts. [CITED: project PITFALLS.md § Performance Traps]
- **Using `NSEvent.addGlobalMonitorForEvents` for hotkeys:** This only works when the app is frontmost — useless for an always-in-background menu bar utility. [CITED: project STACK.md § What NOT to Use]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Speech-to-text | Custom Whisper wrapper or Python subprocess | WhisperKit 0.9.0+ (SPM) | Core ML optimization, built-in VAD, streaming, model management. 6.3k stars, active maintenance. Custom wrapper = months of work + worse performance. [VERIFIED: argmaxinc/argmax-oss-swift GitHub] |
| OpenAI API client | Custom URLSession JSON parsing | MacPaw/OpenAI (SPM) | Streaming (SSE), structured outputs, error handling, retries. 2.9k stars, MIT license. Custom client = 500+ lines of edge case handling. [VERIFIED: MacPaw/OpenAI GitHub] |
| HTTP client | Raw URLSession or third-party networking | URLSession (native) | Swift's native networking is sufficient for our needs. No need for Alamofire or similar. [ASSUMED] |
| Structured logging | `print()` statements | swift-log (Apple official) | Proper log levels, subsystem categorization, persistent logs. `print()` output is invisible in release builds. [CITED: project STACK.md] |
| Key-value storage for secrets | UserDefaults or plist | macOS Keychain (SecItem API) | UserDefaults is unencrypted and accessible to any process in the sandbox. Keychain is hardware-backed secure storage. [CITED: project STACK.md § Supporting Libraries] |
| Ring buffer for audio | Manual array management with locks | Custom `RingBuffer<Float>` (simple, ~50 lines) | Performance-critical — needs lock-free or single-producer-single-consumer pattern. General-purpose collections are too slow for real-time audio. [ASSUMED] |

**Key insight:** For Phase 1 specifically, the only external packages needed are WhisperKit and MacPaw/OpenAI (via SPM). Everything else (CGEvent, AVAudioEngine, SecItem, UserDefaults) is provided by the macOS SDK. The "don't hand-roll" rule primarily applies to: (1) not building a custom Whisper wrapper, (2) not building a custom HTTP client for OpenAI, (3) NEVER storing secrets in UserDefaults.

## Common Pitfalls

### Pitfall 1: Hotkey Permission Loss After OS Updates (HOTK-04)

**What goes wrong:** The app registers hotkeys successfully during initial setup. Weeks later, after a macOS update, the hotkeys stop working silently. The user presses the dictation key, nothing happens, and they assume the app is broken.

**Why it happens:** macOS TCC (Transparency, Consent, and Control) revokes Accessibility permissions on OS updates. `CGEvent` taps silently fail if the app hasn't been granted Accessibility trust — there's no error, just no events. Additionally, `CGEvent.tapIsEnabled()` may return `true` even when the tap is not receiving events if the tap was disabled by timeout rather than explicit revocation.

**How to avoid:**
1. **Launch-time verification:** Call `AXIsProcessTrusted()` and `CGEvent.tapIsEnabled(tap:)` at startup. If either is false, show the permission status indicator.
2. **Runtime watchdog:** Poll `CGEvent.tapIsEnabled(tap:)` every 5 seconds. If the tap becomes disabled, attempt to re-enable it via `CGEvent.tapEnable(tap: tap, enable: true)`. If re-enable fails, post a notification.
3. **Event heartbeat:** Track the timestamp of the last received event. If no events arrive for >10 seconds while the app is running, flag the tap as potentially broken and surface a warning.
4. **Menu bar icon status:** Green = all permissions OK, Orange = one missing, Red = all missing. This is a locked decision from D-08 in CONTEXT.md.
5. **Test with `tccutil reset Accessibility com.yourapp`** to simulate permission revocation before shipping.

**Warning signs:** Only testing on dev machine with pre-granted permissions. No runtime tap health check. No visible permission status.

*Source: [CITED: project PITFALLS.md § Pitfall 4]; Phase to address: Hotkey module.*

### Pitfall 2: Main Thread Blocking During Initialization (SHEL-01)

**What goes wrong:** The user launches the app and clicks the menu bar icon. Nothing happens for 5-15 seconds. The app is loading Whisper model weights or running permission checks synchronously on the main thread. The UI is frozen with a beachball cursor.

**Why it happens:** Whisper model loading involves memory-mapping a multi-gigabyte file and initializing the Core ML compute graph. Even permission checks can block if they trigger system dialogs. If any of this happens on the `@MainActor` synchronously, the menu bar UI is completely unresponsive.

**How to avoid:**
1. **Menu bar icon renders immediately** — the `MenuBarExtra` scene body should only contain static content that doesn't depend on any async initialization.
2. **All initialization on background queues** — use `Task.detached(priority: .userInitiated)` for model loading, permission checks, and keychain reads.
3. **State communicates asynchronously** — the coordinator publishes state changes via `@Published`; the menu bar view observes and updates its icon reactively.
4. **Loading indicator** — show a subtle spinner or "Loading..." state in the menu bar dropdown, never freeze the icon.
5. **Cache initialized subsystems** — load once, reuse. Don't reload on every hotkey press.

**Warning signs:** Model loading in `init()` or `applicationDidFinishLaunching` on main actor. No loading state in UI. Beachball during launch.

*Source: [CITED: project PITFALLS.md § Pitfall 7]; Phase to address: App shell / bootstrap.*

### Pitfall 3: Audio Device Hot-Plug Breaking Capture (AUDI-02)

**What goes wrong:** The user unplugs their external microphone or switches AirPods between devices. The audio capture stream silently dies or starts capturing from the wrong device. The app shows "ready" but no audio is captured.

**Why it happens:** macOS audio device routing is dynamic. When a device is removed (unplugged, Bluetooth disconnect), `AVAudioEngine` doesn't always produce an obvious error — the stream stops delivering buffers or delivers silence. When a new device appears, the system may auto-route, but the existing tap is still bound to the old (now-gone) device.

**How to avoid:**
1. **Register for configuration changes:** Listen to `AVAudioEngineConfigurationChange` notification and `AVAudioSession.routeChangeNotification`.
2. **On device removal:** Stop the engine, update the input node reference, re-install the tap, and restart. Notify the user: "Microphone disconnected. Using built-in mic."
3. **Silence detection on input stream:** Maintain a rolling energy meter. If the stream produces near-silence for >5 seconds while "recording," alert the user that the mic may not be working.
4. **Periodic format verification:** Bluetooth devices (AirPods on HFP profile) may switch to 8kHz. Verify the input format matches expected 16kHz on each engine start.
5. **Show active device in menu bar:** "🎤 Built-in Microphone" — so the user can see which device is selected.

**Warning signs:** No audio device change listeners. Assuming launch-time device is always available. Testing only with built-in mic. No silence detection.

*Source: [CITED: project PITFALLS.md § Pitfall 10]; Phase to address: Audio capture module.*

### Additional Pitfalls for Phase 1

### Pitfall 4: Keychain Access Fails Silently in Sandboxed Apps

**What goes wrong:** `SecItemAdd` or `SecItemCopyMatching` returns `errSecMissingEntitlement` or `errSecInteractionNotAllowed` with no clear error message. API keys are not stored or retrieved.

**Why it happens:** macOS sandboxing and Keychain access groups. If the app is sandboxed (required for App Store distribution), Keychain access requires the `Keychain Access Groups` entitlement. Additionally, `SecItemCopyMatching` with `kSecReturnData` may require user interaction if the item was added with `kSecAttrAccessible` set to a restrictive value.

**How to avoid:**
1. Always check `OSStatus` return values from all `SecItem*` calls. Never assume success.
2. Use `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` for API keys — accessible in background without user prompt.
3. Add `com.apple.security.keychain` or `keychain-access-groups` entitlement for App Store builds.
4. For development (non-App Store), the app can access its own keychain items without special entitlements.

*Source: [ASSUMED — based on macOS Keychain programming guide principles]*

## Code Examples

### Keychain API Key Storage (SHEL-04)

```swift
// Source: SecItem API pattern [CITED: project ARCHITECTURE.md § Settings § Keychain]
import Security

final class KeychainStore {
    private let service = "com.voicetype.api-keys"
    
    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
    }
    
    func store(key: String, value: String) throws {
        // Delete existing item first
        try? delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    func retrieve(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(errSecDecode)
        }
        
        return string
    }
    
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // Store with obfuscated display (show last 4 chars in UI)
    func obfuscatedValue(for key: String) -> String {
        guard let full = try? retrieve(key: key), full.count > 4 else {
            return "••••"
        }
        return "••••" + full.suffix(4)
    }
}
```

### Permission Status Model

```swift
// Source: derived from CONTEXT.md D-08 [CITED: project CONTEXT.md]
enum PermissionStatus {
    case allGranted      // Green
    case partial         // Orange — one missing
    case noneGranted     // Red — both missing
    
    var iconColor: String {
        switch self {
        case .allGranted:  return "green"
        case .partial:     return "orange"
        case .noneGranted: return "red"
        }
    }
    
    static func evaluate(mic: Bool, ax: Bool) -> PermissionStatus {
        switch (mic, ax) {
        case (true, true):   return .allGranted
        case (false, false): return .noneGranted
        default:             return .partial
        }
    }
}
```

### Audio Device Route Change Handling (AUDI-02)

```swift
// Source: AVAudioEngine + NotificationCenter pattern [ASSUMED — based on AVAudioEngine documentation patterns]
extension AudioCaptureService {
    func startDeviceMonitoring() {
        // Observe audio engine configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        
        // Observe hardware route changes (device plug/unplug)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleEngineConfigChange(_ notification: Notification) {
        // Re-install tap with new format if engine was reconfigured
        guard engine.isRunning else { return }
        
        engine.inputNode.removeTap(onBus: 0)
        try? start()
        
        // Notify coordinator of device change
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .audioDeviceChanged,
                object: currentInputDeviceName
            )
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reasonEnum = AVAudioSession.RouteChangeReason(rawValue: reason) else {
            return
        }
        
        switch reasonEnum {
        case .oldDeviceUnavailable:
            // Device was unplugged — re-route to default
            engine.inputNode.removeTap(onBus: 0)
            try? start()
        case .newDeviceAvailable:
            // New device appeared — optionally switch
            try? start()
        default:
            break
        }
    }
    
    private var currentInputDeviceName: String {
        // AVAudioSession.currentRoute.inputs.first?.portName
        return "Built-in Microphone" // Placeholder
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Carbon `RegisterEventHotKey` | `CGEvent.tapCreate` with `.cgSessionEventTap` | macOS 10.6+ (CGEvent API introduced) | Carbon is deprecated; CGEvent tap supports key-up events (essential for push-to-talk) [CITED: project STACK.md] |
| `NSEvent.addGlobalMonitorForEvents` | `CGEvent.tapCreate` | Always | `NSEvent` approach only works when app is frontmost — useless for background utility [CITED: project STACK.md] |
| UserDefaults for secrets | Keychain `SecItem` API | Always | UserDefaults is unencrypted; Keychain is hardware-backed [CITED: project STACK.md] |
| `NSStatusBar` (AppKit) for menu bar | `MenuBarExtra` (SwiftUI) | macOS 14+ | SwiftUI-native, declarative, simpler API [CITED: project STACK.md] |

**Deprecated/outdated:**
- **Carbon `RegisterEventHotKey`:** Deprecated. Only fires key-down, not key-up. Apple may remove in future macOS. Use CGEvent tap instead. [CITED: project STACK.md]
- **`NSEvent.addGlobalMonitorForEvents`:** Not deprecated but inappropriate for background apps. Only fires when app is frontmost. [CITED: project STACK.md]
- **Apple's built-in `SFSpeechRecognizer`:** Not deprecated but requires network, limited to 1-minute bursts, no model selection. Use WhisperKit instead. [CITED: project STACK.md]
- **Storing API keys in UserDefaults or plist files:** Never appropriate for production. Use Keychain. [CITED: project STACK.md]

## Assumptions Log

> All claims tagged `[ASSUMED]` in this research. The planner and discuss-phase use this section to identify decisions that need user confirmation before execution.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | RingBuffer implementation uses lock-free SPSC (single producer, single consumer) pattern for audio data. General-purpose collections are too slow for real-time audio. | Don't Hand-Roll | MEDIUM — a lock-based approach with `os_unfair_lock` may be simpler and sufficient for our buffer sizes. Performance profiling should validate. |
| A2 | `AVAudioEngineConfigurationChange` and `AVAudioSession.routeChangeNotification` cover all audio device hot-plug scenarios on macOS 14+. | Common Pitfalls: Pitfall 3 | LOW — these are the documented APIs. Bluetooth HFP profile switches (8kHz vs 16kHz) are the primary edge case to test. |
| A3 | `kSecAttrAccessibleAfterFirstUnlock` is the correct accessibility level for API keys — accessible in background without user prompt, protected when device is locked. | Code Examples: Keychain | LOW — if the app needs to access keys before first unlock (e.g., at boot), this would fail. `kSecAttrAccessibleAlways` is less secure but necessary for launch agents. |
| A4 | CGEvent tap with `.headInsertEventTap` placement does not interfere with system keyboard handling (the event is observed, not consumed). The callback returns `Unmanaged.passUnretained(event)` to pass the event through. | Architecture Patterns: Pattern 4 | MEDIUM — if the callback needs to suppress events (e.g., to prevent Fn key from triggering system actions), returning `nil` would consume the event. This needs testing. |
| A5 | `MenuBarExtra` `.menu` style provides sufficient real estate for status display and quick actions. `.window` style is not needed for Phase 1. | Architecture Patterns: Pattern 3 | LOW — `.menu` is the standard style for status bar apps. `.window` style is for apps that need a persistent popover (unnecessary for our use case). |

## Open Questions

1. **Fn key behavior on Touch Bar Macs and third-party keyboards**
   - What we know: Fn key is key code 63 (kVK_Function). On Touch Bar Macs, the Fn key also shows/hides the Touch Bar. On third-party keyboards, the Fn key may not send standard key events.
   - What's unclear: Does the Fn key on a Magic Keyboard send `.keyDown` and `.keyUp` events, or only `.flagsChanged`? Answer determines whether we need special flag-state tracking.
   - Recommendation: Implement `flagsChanged` handler for Fn key. Test on MacBook Pro (Touch Bar), MacBook Air (no Touch Bar), iMac with Magic Keyboard, and a third-party mechanical keyboard. Request user to test on their specific hardware during UAT.

2. **Entitlement requirements for App Store vs. direct distribution**
   - What we know: Sandboxed apps (App Store) need `com.apple.security.automation.apple-events` for accessibility and `com.apple.security.device.audio-input` for microphone.
   - What's unclear: Does App Store review reject apps that require Accessibility permission? Some assistive apps are accepted, others rejected. No clear policy.
   - Recommendation: Plan for direct distribution (DMG) as primary channel. Add App Store entitlements as a secondary target. Research App Store guidelines for accessibility apps before Phase 3.

3. **CGEvent tap stability on macOS 15 (Sequoia)**
   - What we know: macOS 15 further tightened TCC controls. Some developers report CGEvent taps being disabled more aggressively.
   - What's unclear: Are there new API requirements or entitlements for CGEvent taps on macOS 15+? Does the `com.apple.security.automation.apple-events` entitlement need updating?
   - Recommendation: Test on latest macOS 15 beta. Check Apple developer forums for CGEvent tap changes. Implement aggressive watchdog and re-enable logic.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 17+ | Build, archive, notarize | ✓ | 17.x (latest) | — |
| macOS 14+ | Deployment target | ✓ | 15.x (Sequoia) | — |
| Swift 6 | Language | ✓ | 6.x (bundled with Xcode) | — |
| Git | SPM package resolution | ✓ | system | — |
| WhisperKit (SPM) | Speech-to-text | ✓ (via SPM) | 0.9.0+ | — |
| MacPaw/OpenAI (SPM) | AI correction | ✓ (via SPM) | main branch | — |
| swift-log (SPM) | Structured logging | ✓ (via SPM) | 1.6+ | — |
| Microphone hardware | Audio capture | ✓ | Built-in MacBook mic | — |
| Accessibility permission | CGEvent tap | ✗ (needs grant) | Requires user action | Prompt user to enable in System Settings |

**Missing dependencies with no fallback:**
- **Accessibility permission:** Required for CGEvent tap. Cannot work around. User must grant manually. Phase must include clear permission-granting UX.

**Missing dependencies with fallback:**
- (None — all other dependencies are bundled or available)

## Security Domain

> Required: `security_enforcement` is `true` in config.json. ASVS Level 1 applies.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No user authentication in Phase 1 — API keys stored for service-to-service auth only |
| V3 Session Management | No | No user sessions in Phase 1 |
| V4 Access Control | No | No multi-user access control needed |
| V5 Input Validation | Yes | API key validation on entry (non-empty, format check); hotkey configuration validation (valid key codes only) |
| V6 Cryptography | Yes | API keys MUST be stored in macOS Keychain (SecItem API) — never in UserDefaults or plaintext. This is a locked decision (D-12 in CONTEXT.md). |

### Known Threat Patterns for macOS Menu Bar Swift App

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| API key exposure via UserDefaults or plist | Information Disclosure | Keychain-only storage via `SecItem`. All UserDefaults keys must be non-sensitive preferences only (audited at code review). [VERIFIED: project STACK.md] |
| API key exposure via memory dump | Information Disclosure | Keys loaded into memory only when making API calls. Avoid storing plaintext keys in non-ephemeral variables. Use `String` with caution — consider `Data`-based handling. [ASSUMED] |
| Accessibility API abuse (reading text from all apps) | Information Disclosure / Elevation of Privilege | Only read text from target app when user explicitly initiates correction (hotkey press). Never poll. Never read from password fields (`kAXIsPasswordFieldAttribute`). Clear buffers after operation. [CITED: project PITFALLS.md § Security Mistakes] |
| TCC permission bypass via social engineering | Spoofing | Clear permission rationale in onboarding UI. Never request permissions without explaining WHY. Show permission status prominently (menu bar icon color). [CITED: project CONTEXT.md D-07, D-08] |
| Log injection via dictated content | Tampering | Use structured logging (OSLog) with proper privacy levels. Mark user-dictated text as `.private` in log statements. [ASSUMED] |

### Security Checklist for Phase 1

- [ ] `Info.plist` includes `NSMicrophoneUsageDescription` with clear purpose string in Chinese + English
- [ ] No API keys stored in `UserDefaults`, `@AppStorage`, or any plist file
- [ ] Keychain store uses `kSecClassGenericPassword` with unique `kSecAttrService` identifier
- [ ] All `SecItem*` calls check for `OSStatus` errors (no silent failures)
- [ ] Permission rationale strings explain WHY each permission is needed, not just WHAT it does
- [ ] Menu bar icon reflects permission status (green/orange/red per D-08)
- [ ] No reading from password fields (future Phase 2/3 requirement — note for now)
- [ ] Audio buffers cleared after each dictation session (future Phase 2 requirement — note for now)

## Sources

### Primary (HIGH confidence)
- [WhisperKit GitHub (argmaxinc/argmax-oss-swift)](https://github.com/argmaxinc/argmax-oss-swift) — verified v0.9.0+, SPM setup, model catalog, prerequisites (macOS 14.0+, Xcode 16.0+). HIGH confidence.
- [MacPaw/OpenAI GitHub](https://github.com/MacPaw/OpenAI) — verified SPM setup, streaming, structured outputs, custom host support. HIGH confidence.
- [.planning/research/STACK.md] — comprehensive stack research with verified library versions, alternatives, and "what not to use." HIGH confidence.
- [.planning/research/ARCHITECTURE.md] — layered architecture, coordinator pattern, subsystem isolation. Component responsibilities map directly to Phase 1 subsystems. HIGH confidence.

### Secondary (MEDIUM confidence)
- [.planning/research/PITFALLS.md] — verified pitfall patterns #4 (hotkey permission loss), #7 (main thread blocking), #10 (audio device hot-plug). MEDIUM confidence due to macOS version-dependent behavior.
- [.planning/phases/01-foundation/01-CONTEXT.md] — locked implementation decisions D-01 through D-12. MEDIUM confidence (decisions are user-confirmed, not independently verified).

### Tertiary (LOW confidence)
- CGEvent tap RunLoop integration specifics — the pattern of creating a dedicated Thread with `CFRunLoopAddSource` is derived from training knowledge, not verified against current macOS 15 behavior. Marked as `[ASSUMED]` in Assumptions Log.
- Keychain entitlement requirements for App Store vs. direct distribution — training knowledge, not verified against current App Store guidelines. Marked as `[ASSUMED]`.
- AVAudioEngine format converter behavior with non-standard hardware sample rates — training knowledge. Testing with real hardware needed.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries verified via GitHub READMEs and project STACK.md
- Architecture: HIGH — patterns from ARCHITECTURE.md verified against industry practice
- Code examples: MEDIUM — API patterns correct but not compiled/tested; CGEvent callback and RunLoop threading need hardware verification
- Pitfalls: MEDIUM — pitfall patterns well-documented in PITFALLS.md, but macOS 15 behavior may differ

**Research date:** 2026-07-30
**Valid until:** 2026-08-30 (30 days — stable macOS APIs, but monitor macOS 15 beta changes)
