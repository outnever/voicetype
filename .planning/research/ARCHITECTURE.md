# Architecture Research

**Domain:** macOS voice dictation app with AI-powered correction
**Researched:** 2026-07-30
**Confidence:** HIGH

## Standard Architecture

VoiceType follows a layered architecture common to macOS assistive voice tools (similar to Superwhisper and MacWhisper). The system is organized into five horizontal layers: Input Capture, Speech Processing, Intelligence, Text I/O, and Presentation.

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRESENTATION LAYER                               │
│  ┌──────────────────┐  ┌────────────────────┐  ┌─────────────────────┐ │
│  │  Menu Bar App    │  │  Settings Window   │  │  Status Overlay     │ │
│  │  (SwiftUI)       │  │  (SwiftUI)         │  │  (HUD indicator)    │ │
│  └────────┬─────────┘  └────────┬───────────┘  └─────────┬───────────┘ │
│           │                     │                        │              │
├───────────┴─────────────────────┴────────────────────────┴──────────────┤
│                       ORCHESTRATION LAYER                                │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                    AppCoordinator (State Machine)                    ││
│  │  • Dictation mode: hotkey → record → VAD → transcribe → insert     ││
│  │  • Correction mode: hotkey → read context → record → AI → replace  ││
│  │  • Manages audio session lifecycle, error recovery, mode switching  ││
│  └────┬──────────┬──────────┬──────────────┬───────────────────────────┘│
│       │          │          │              │                             │
├───────┴──────────┴──────────┴──────────────┴─────────────────────────────┤
│                       INPUT CAPTURE LAYER                                │
│  ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐│
│  │  HotkeyManager  │  │  AudioCapture    │  │  VADEngine (silero-vad)  ││
│  │  (CGEvent tap)  │  │  (AVAudioEngine) │  │  (ggml / ONNX)           ││
│  └────────┬────────┘  └────────┬─────────┘  └───────────┬──────────────┘│
│           │                    │                        │                │
├───────────┴────────────────────┴────────────────────────┴────────────────┤
│                       SPEECH PROCESSING LAYER                            │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │                TranscriptionEngine (WhisperKit)                       ││
│  │  • CoreML-based Whisper inference on Apple Silicon                   ││
│  │  • Model loading/caching, language detection, word timestamps        ││
│  │  • Offline capable — no network needed for STT                       ││
│  └────────────────────────────┬─────────────────────────────────────────┘│
│                               │                                           │
├───────────────────────────────┴───────────────────────────────────────────┤
│                       INTELLIGENCE LAYER                                  │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │              CorrectionEngine (LLM Client)                            ││
│  │  • Sends context + correction instruction → GPT-4o / Claude          ││
│  │  • Structured output: finds target text, applies correction          ││
│  │  • Streaming optional for progress UX                                ││
│  │  • API key management, retry logic, token counting                   ││
│  └────────────────────────────┬─────────────────────────────────────────┘│
│                               │                                           │
├───────────────────────────────┴───────────────────────────────────────────┤
│                       TEXT I/O LAYER                                      │
│  ┌──────────────────────┐  ┌────────────────────────────────────────────┐│
│  │  AccessibilityBridge  │  │  ClipboardBridge                         ││
│  │  (AXUIElement API)   │  │  (NSPasteboard)                          ││
│  │  Read/write text in   │  │  Fallback when Accessibility unavailable  ││
│  │  any app's text field │  │  Uses Cmd+A, Cmd+C, Cmd+V simulation     ││
│  └──────────────────────┘  └────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **HotkeyManager** | Global hotkey registration and event routing | `CGEvent.tapCreate` with `.cgSessionEventTap`; two distinct hotkeys for dictation/correction modes |
| **AudioCapture** | Real-time microphone capture with proper audio format | `AVAudioEngine` with tap on input node; 16kHz mono Float32 PCM output |
| **VADEngine** | Voice activity detection — identifies speech start/end boundaries | silero-vad model via ggml (bundled with whisper.cpp conversion) or ONNX runtime; operates on ~30ms frames |
| **TranscriptionEngine** | Speech-to-text using local Whisper model | WhisperKit (Argmax OSS SDK) — Swift-native, CoreML-optimized, auto model download |
| **CorrectionEngine** | AI-powered text correction via cloud LLM | MacPaw/OpenAI Swift SDK for GPT-4o; constructed prompt with surrounding context + user correction instruction |
| **AccessibilityBridge** | Read/write text in arbitrary application text fields | `AXUIElementCopyAttributeValue(kAXFocusedUIElementAttribute)` for reading; `AXUIElementSetAttributeValue(kAXValueAttribute)` for writing |
| **ClipboardBridge** | Fallback text I/O via clipboard simulation | `NSPasteboard.general` + simulated Cmd+A/Cmd+C/Cmd+V key events via `CGEventPost` |
| **AppCoordinator** | Central state machine orchestrating all flows | Swift actor or `@MainActor` class; manages transitions between idle/recording/transcribing/correcting states |
| **MenuBarApp** | Status item, settings, visual feedback | SwiftUI `MenuBarExtra` scene; shows recording state, model status, quick actions |
| **SettingsManager** | User preferences, API keys, hotkey config | `UserDefaults` / `@AppStorage` for simple settings; Keychain for API keys |

## Recommended Project Structure

```
VoiceType/
├── VoiceType/                       # Main app target
│   ├── VoiceTypeApp.swift           # @main App entry — sets up MenuBarExtra
│   ├── AppCoordinator.swift         # Central state machine (actor)
│   │
│   ├── Hotkey/
│   │   ├── HotkeyManager.swift      # CGEvent tap lifecycle
│   │   └── HotkeyConfiguration.swift # Hotkey recording/storage
│   │
│   ├── Audio/
│   │   ├── AudioCaptureService.swift # AVAudioEngine wrapper
│   │   ├── AudioBuffer.swift        # Ring buffer for streaming audio
│   │   └── AudioFormat.swift        # PCM format constants
│   │
│   ├── VAD/
│   │   ├── VADEngine.swift          # silero-vad integration
│   │   ├── VADModel.swift           # Model loading (ggml or ONNX)
│   │   └── SpeechSegment.swift      # Start/end timestamp model
│   │
│   ├── Transcription/
│   │   ├── TranscriptionService.swift # WhisperKit wrapper
│   │   ├── TranscriptionResult.swift  # Structured result with timestamps
│   │   └── ModelManager.swift         # Download, cache, select models
│   │
│   ├── Correction/
│   │   ├── CorrectionEngine.swift     # LLM correction pipeline
│   │   ├── CorrectionPrompt.swift     # Prompt templates
│   │   └── LLMClient.swift            # OpenAI/Claude API abstraction
│   │
│   ├── TextIO/
│   │   ├── TextIOProtocol.swift       # Protocol: read/write/replace
│   │   ├── AccessibilityBridge.swift  # AXUIElement implementation
│   │   ├── ClipboardBridge.swift      # NSPasteboard fallback
│   │   └── TextContext.swift          # Context window model
│   │
│   ├── UI/
│   │   ├── MenuBarView.swift          # Menu bar extra content
│   │   ├── SettingsView.swift         # Preferences window
│   │   ├── HUDOverlay.swift           # Recording/status indicator
│   │   └── PermissionGateView.swift   # First-run permission prompts
│   │
│   ├── Settings/
│   │   ├── SettingsStore.swift        # @AppStorage wrapper
│   │   ├── KeychainStore.swift        # Secure API key storage
│   │   └── Defaults.swift             # Default values
│   │
│   └── Utilities/
│       ├── PermissionManager.swift    # Mic/Accessibility permission checks
│       ├── ErrorHandler.swift         # Centralized error handling
│       └── Logging.swift              # OSLog wrapper
│
├── VoiceTypeTests/
│   └── ...
│
└── Packages/                          # Local SPM packages (if needed)
    └── ...
```

### Structure Rationale

- **Hotkey/, Audio/, VAD/, Transcription/, Correction/, TextIO/: Each is an isolated subsystem** — they share no direct dependencies on each other. The `AppCoordinator` is the only coupling point. This enables independent testing and phased development.
- **No cross-imports between subsystems** — Audio doesn't import Transcription, VAD doesn't import Correction. Each subsystem defines its own protocols/inputs/outputs.
- **UI/ is separate from logic** — all UI views observe coordinator state via `@Published` or Combine; they never import Audio or Hotkey directly.
- **TextIO uses a protocol** — `AccessibilityBridge` and `ClipboardBridge` both conform to `TextIOProtocol`. The coordinator selects the strategy at runtime based on permission availability.
- **Settings in dedicated package** — keeps UserDefaults and Keychain access centralized, making it easy to audit what's persisted.

## Architectural Patterns

### Pattern 1: Central Coordinator (Mediator)

**What:** A single `AppCoordinator` actor owns all subsystem instances and routes messages between them. Subsystems never reference each other directly.

**When to use:** When you have 5+ subsystems that need to interact in multiple sequences (dictation flow, correction flow, error recovery) and you want to avoid spaghetti dependencies.

**Trade-offs:** The coordinator becomes the largest single file. Mitigate by keeping it as a thin router — actual logic lives in subsystems. Avoid having the coordinator know internal details of any subsystem.

**Example:**
```swift
@MainActor
final class AppCoordinator: ObservableObject {
    @Published var state: AppState = .idle
    @Published var statusMessage: String = "Ready"

    let hotkeyManager = HotkeyManager()
    let audioCapture = AudioCaptureService()
    let vadEngine = VADEngine()
    let transcriptionService = TranscriptionService()
    let correctionEngine = CorrectionEngine()
    let textIO: TextIOProtocol

    func startDictation() async throws {
        state = .recording
        let audioBuffer = try await audioCapture.recordUntilSilence(
            vadDetector: vadEngine.detectSpeech
        )
        state = .transcribing
        let text = try await transcriptionService.transcribe(audioBuffer)
        state = .inserting
        try await textIO.insertText(text)
        state = .idle
    }

    func startCorrection() async throws {
        state = .readingContext
        let context = try await textIO.readContext(windowSize: 500)
        state = .recordingCorrection
        let audioBuffer = try await audioCapture.recordUntilSilence(
            vadDetector: vadEngine.detectSpeech
        )
        state = .transcribing
        let instruction = try await transcriptionService.transcribe(audioBuffer)
        state = .correcting
        let correctedText = try await correctionEngine.correct(
            context: context,
            instruction: instruction
        )
        state = .replacing
        try await textIO.replaceText(correctedText)
        state = .idle
    }
}
```

### Pattern 2: Protocol-Based Strategy Selection

**What:** The Text I/O layer defines a protocol with two implementations — Accessibility (primary) and Clipboard (fallback). The coordinator tries the primary first and degrades gracefully.

**When to use:** When a feature has multiple backend strategies with different capability/availability profiles. Essential for macOS where Accessibility permissions may or may not be granted.

**Trade-offs:** The protocol must cover the lowest common denominator, so advanced Accessibility-only features (like precise cursor positioning) must be optional.

**Example:**
```swift
protocol TextIOProtocol {
    func readContext(windowSize: Int) async throws -> TextContext
    func insertText(_ text: String) async throws
    func replaceText(_ text: String) async throws
}

final class CompositeTextIO: TextIOProtocol {
    let primary: AccessibilityBridge    // AXUIElement-based
    let fallback: ClipboardBridge       // Pasteboard-based

    func insertText(_ text: String) async throws {
        do {
            try await primary.insertText(text)
        } catch {
            try await fallback.insertText(text)
        }
    }
}
```

### Pattern 3: Push-to-Talk Audio Pipeline with VAD Gating

**What:** Audio is continuously captured while the hotkey is held. VAD runs on buffered audio to detect speech end. Only the speech segment (trimmed of leading/trailing silence) is passed to Whisper.

**When to use:** Any push-to-talk dictation system. Essential for latency-sensitive UX where users expect fast turnaround.

**Trade-offs:** VAD adds ~1ms per 30ms frame (negligible). The main risk is false silence detection mid-sentence — mitigated by `min_silence_duration_ms` threshold of ~800ms.

**Example:**
```swift
// AudioCapture streams frames → VAD classifies each frame
// When VAD transitions speech→silence for > 800ms, audio capture stops
// The full speech segment buffer is trimmed and sent to WhisperKit:
let speechTimestamps = vadEngine.getSpeechTimestamps(
    audioBuffer,
    minSilenceDurationMs: 800,
    speechPadMs: 100
)
let trimmedAudio = audioBuffer.trim(to: speechTimestamps)
let transcription = try await whisperKit.transcribe(audioArray: trimmedAudio)
```

### Pattern 4: LLM Correction with Structured Context Window

**What:** Before sending a correction request to the LLM, read ~500 characters of surrounding text. The prompt template wraps this context + the user's correction instruction + explicit formatting requirements. The LLM returns only the corrected span, not the full context.

**When to use:** In-place text correction where the model must identify and fix only the erroneous portion, not regenerate everything.

**Trade-offs:** Context window size matters — too small and the model lacks context, too large and latency + token cost increase. 500 chars is a good default for sentence/paragraph-level corrections.

**Example:**
```swift
let prompt = """
You are a text correction assistant. Your ONLY job is to fix the incorrect text.
Rules:
1. Read the surrounding context to understand what was intended.
2. Apply the user's correction instruction to the TEXT TO CORRECT.
3. Return ONLY the corrected version of TEXT TO CORRECT — nothing else.

SURROUNDING CONTEXT:
>>> 
\(context.before) [TEXT TO CORRECT] \(context.selection) [/TEXT TO CORRECT] \(context.after)
<<<

CORRECTION INSTRUCTION: \(instruction)

CORRECTED TEXT:
"""

let response = try await openAI.chats(query: ChatQuery(
    messages: [.user(.init(content: .string(prompt)))],
    model: .gpt4_o,
    temperature: 0.0   // Deterministic for corrections
))
```

## Data Flow

### Dictation Flow (Push-to-Talk → Text Insertion)

```
User holds dictation hotkey
    ↓
HotkeyManager: fires .keyDown event
    ↓
AppCoordinator: transition → .recording
    ↓
AudioCapture: starts AVAudioEngine tap → buffers PCM data into ring buffer
    ↓
VADEngine: processes audio frames in real-time; detects speech start/end
    ↓ (VAD signals speech ended — silence > 800ms)
AudioCapture: stops; trims buffer to speech segment
    ↓
TranscriptionService: WhisperKit.transcribe(audioArray: trimmedBuffer)
    ↓
TranscriptionResult: (text, language, timestamps)
    ↓
AppCoordinator: transition → .inserting
    ↓
TextIO.insertText(transcriptionResult.text)
    ↓
AppCoordinator: transition → .idle
    ↓
User sees text appear at cursor
```

### Correction Flow (Hotkey → Context Read → AI Correction → Replacement)

```
User presses correction hotkey
    ↓
HotkeyManager: fires correction event
    ↓
AppCoordinator: transition → .readingContext
    ↓
TextIO.readContext(windowSize: 500) → TextContext(before, selection, after)
    ↓
AppCoordinator: transition → .recordingCorrection
    ↓
[Same audio capture → VAD → transcription pipeline as dictation]
    ↓
instruction = transcriptionResult.text  (e.g., "把苹果改成梨")
    ↓
AppCoordinator: transition → .correcting
    ↓
CorrectionEngine.correct(context: context, instruction: instruction)
    ↓
LLMClient: POST chat/completions → structured response with corrected span
    ↓
correctedText = response  (only the corrected portion)
    ↓
AppCoordinator: transition → .replacing
    ↓
TextIO.replaceText(correctedText)
    ↓
AppCoordinator: transition → .idle
    ↓
User sees corrected text in-place
```

### State Management

```
AppState (enum):
    idle
    ↓ (dictation hotkey down)
    recording
    ↓ (VAD silence)
    transcribing
    ↓ (WhisperKit done)
    inserting
    ↓ (text written)
    idle

    idle
    ↓ (correction hotkey down)
    readingContext
    ↓ (context captured)
    recordingCorrection
    ↓ (VAD silence)
    transcribing
    ↓ (instruction transcribed)
    correcting
    ↓ (LLM response)
    replacing
    ↓ (text replaced)
    idle
```

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| **WhisperKit (Argmax OSS)** | SPM package `https://github.com/argmaxinc/argmax-oss-swift` | First download of model happens on launch (~626MB for large-v3). Must handle download progress UI and offline fallback. |
| **OpenAI GPT-4o** | MacPaw/OpenAI Swift SDK `https://github.com/MacPaw/OpenAI` | Requires API key stored in Keychain. Correction mode only — dictation works fully offline. Must handle network errors, rate limits, token costs. |
| **silero-vad** | ggml model via whisper.cpp's VAD support, or ONNX runtime | whisper.cpp already bundles silero-vad conversion. The ggml model is ~864KB. If using WhisperKit, VAD must be integrated separately via ONNX. |
| **macOS Accessibility** | `ApplicationServices` framework — `AXUIElement` API | Requires user to grant Accessibility permission in System Settings. Not all apps expose their text fields via AX (e.g., some Electron apps). Clipboard fallback is essential. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **AppCoordinator ↔ Subsystems** | Direct async method calls on `@MainActor` | Coordinator is the only component that imports multiple subsystems. Subsystems are isolated. |
| **AudioCapture → VADEngine** | Data flow: AudioCapture produces Float32 arrays; VADEngine consumes them. | Coupled only through the coordinator — AudioCapture never imports VAD. |
| **VADEngine → TranscriptionService** | VAD produces SpeechSegment timestamps; coordinator passes trimmed buffer to Transcription. | No direct coupling. |
| **TranscriptionService → TextIO** | Coordinator passes `TranscriptionResult.text` to `TextIO.insertText()`. | No direct coupling. |
| **TextIO → CorrectionEngine** | Coordinator passes `TextContext` from TextIO to CorrectionEngine. | No direct coupling. |
| **CorrectionEngine → TextIO** | Coordinator passes corrected text to `TextIO.replaceText()`. | No direct coupling. |

## Anti-Patterns

### Anti-Pattern 1: Tight Coupling Between Audio and Transcription

**What people do:** Build a single `VoicePipeline` class that handles audio capture, VAD, and Whisper transcription all in one tightly coupled module.

**Why it's wrong:** You cannot test transcription without real audio input. You cannot swap VAD implementations. Every change to audio format ripples through the entire pipeline.

**Do this instead:** Keep AudioCapture, VADEngine, and TranscriptionService as separate subsystems. The coordinator orchestrates the data flow between them. Each can be tested with mock data.

### Anti-Pattern 2: Main Thread Blocking for Whisper Inference

**What people do:** Run WhisperKit transcription on the main actor because it's "just a function call."

**Why it's wrong:** Whisper inference on even a `small` model can take 2-5 seconds for a 30-second audio clip. Blocking the main thread freezes the menu bar UI, prevents hotkey events from being processed, and makes the app appear hung.

**Do this instead:** Run transcription on a background `Task.detached(priority: .userInitiated)`. Use `await` to bridge back to the main actor only for UI updates. Ensure WhisperKit's `AudioEncoder` and `TextDecoder` run off the main queue.

### Anti-Pattern 3: Assuming AXUIElement Always Works

**What people do:** Build the entire Text I/O layer around AXUIElement, assuming it's always available and works with every app.

**Why it's wrong:** Many apps (Electron-based, some text editors, terminal emulators) either don't expose standard AX text attributes or have broken AX implementations. The app becomes useless for those users.

**Do this instead:** Implement a `CompositeTextIO` with Accessibility as primary and Clipboard as automatic fallback. Log AX failures silently and degrade. Consider a third "simulated keystroke" strategy for worst-case scenarios.

### Anti-Pattern 4: Sending Full Context to LLM Every Correction

**What people do:** Send the entire document/paragraph as context to the LLM for every small correction.

**Why it's wrong:** Token costs grow linearly with context size. A correction that should cost $0.001 becomes $0.05. Latency also increases with prompt length.

**Do this instead:** Cap the context window at ~500 characters (roughly one paragraph). The prompt template wraps only the immediate neighborhood around the cursor. The LLM is instructed to return only the corrected span, not the full context.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| **Single user (v1)** | Everything runs locally on the user's Mac. WhisperKit in-process, VAD in-process. Clipboard fallback covers edge cases. No server needed. |
| **Multiple models** | ModelManager handles downloading, caching, and versioning of Whisper models. Users can select tiny/small/medium/large based on accuracy vs. speed trade-off. |
| **Multiple LLM providers** | CorrectionEngine abstracts behind LLMClient protocol. Implementations for OpenAI, Anthropic, local LLM (Ollama). Settings-based selection. |
| **Windows port (future)** | HotkeyManager and TextIO need platform-specific implementations. Whisper, VAD, and LLM layers are cross-platform. Architecture supports swapping macOS-specific layers. |

### Scaling Priorities

1. **First bottleneck:** Whisper model loading time — the large-v3 model (~626MB) takes 10-30 seconds to download and compile for CoreML on first launch. **Mitigation:** Background download with progress UI; ship with `tiny` as default and let users upgrade.
2. **Second bottleneck:** LLM API latency for correction — GPT-4o typically responds in 500ms-2s for short corrections, but network variability can cause 5-10s delays. **Mitigation:** Show "correcting..." status; implement 10s timeout with retry; consider streaming for progressive feedback.

## Build Order Implications

Based on component dependencies, the recommended build order (which maps to development phases):

```
Phase 1: AudioCapture          ← No dependencies (system APIs only)
Phase 1: HotkeyManager         ← No dependencies (system APIs only)
         ↓
Phase 2: VADEngine             ← Depends on AudioCapture (needs audio frames)
Phase 2: TextIO                ← No code dependencies (needs permission setup)
         ↓
Phase 3: TranscriptionService  ← Depends on AudioCapture + VAD (needs trimmed audio)
         ↓
Phase 4: AppCoordinator        ← Depends on Hotkey + Audio + VAD + Transcription + TextIO
Phase 4: MenuBarApp (basic)    ← Depends on Coordinator (for state display)
         ↓
Phase 5: CorrectionEngine      ← Depends on TextIO (context) + Transcription (instruction) + LLM
Phase 5: Full correction flow  ← Depends on Coordinator + CorrectionEngine
```

**Key insight:** AudioCapture + HotkeyManager can be built and tested in parallel (Phase 1). VAD + TextIO can be built in parallel once audio capture works (Phase 2). The full dictation loop (hotkey→speak→text appears) is achievable by Phase 4. Correction (Phase 5) is additive and does not block the core dictation experience.

## Sources

- WhisperKit (Argmax OSS SDK): `https://github.com/argmaxinc/argmax-oss-swift` — Swift-native Whisper inference via CoreML on Apple Silicon. v0.9.0+, 6.3k stars. Active maintenance. (confidence: HIGH)
- whisper.cpp: `https://github.com/ggml-org/whisper.cpp` — C/C++ Whisper port with built-in VAD and CoreML ANE support. v1.9.1, 52.4k stars. (confidence: HIGH)
- silero-vad: `https://github.com/snakers4/silero-vad` — Pre-trained VAD model, <2MB, <1ms per frame, MIT licensed. 9.8k stars. whisper.cpp already bundles it as ggml format. (confidence: HIGH)
- MacPaw/OpenAI Swift SDK: `https://github.com/MacPaw/OpenAI` — Community-maintained Swift client for OpenAI API. 2.9k stars. Supports Chat Completions, streaming, structured outputs, function calling. (confidence: HIGH)
- Superwhisper: `https://superwhisper.com` — Market-leading macOS dictation + AI correction app. Validates the architecture pattern (global hotkey → ASR → LLM correction → in-place replacement). (confidence: MEDIUM)
- Apple AXUIElement Documentation: `https://developer.apple.com/documentation/applicationservices/axuielement` — Core Accessibility API for reading/writing UI element attributes. Requires `kAXTrustedCheckOptionPrompt` entitlement. (confidence: HIGH)

---

*Architecture research for: VoiceType — macOS voice dictation with AI correction*
*Researched: 2026-07-30*
