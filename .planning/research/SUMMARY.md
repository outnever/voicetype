# Project Research Summary

**Project:** VoiceType
**Domain:** macOS voice dictation with AI-powered correction
**Researched:** 2026-07-30
**Confidence:** HIGH

## Executive Summary

VoiceType is a macOS menu bar utility that combines on-device speech-to-text (via WhisperKit) with cloud AI correction (GPT-4o or Claude). Its signature differentiator is a **dedicated correction hotkey** — users press one key to dictate, another to say "fix X to Y" in natural language, and the AI surgically corrects text in-place. No existing competitor (Wispr Flow, Superwhisper, MacWhisper, Apple Dictation) offers this two-hotkey dictation+correction pattern.

Experts in this domain build such tools as native Swift/SwiftUI apps, not with Electron or Python. The critical architectural insight is that **four independent subsystems must work before you can ship anything useful**: audio capture, global hotkeys, text I/O via macOS Accessibility API, and local Whisper inference. Each has different permission requirements and failure modes. The recommended approach is to build them in parallel, integrate through a central coordinator (mediator pattern), and defer the AI correction pipeline until the core dictation loop is solid — correction is additive and doesn't block dictation.

The top three risks are: (1) **Accessibility API fragility** — AXUIElement works differently (or not at all) across apps like VS Code, Chrome, and Terminal, requiring a multi-strategy fallback chain from day one. (2) **Whisper hallucination on short audio** — the model expects complete utterances; push-to-talk requires a "record-until-silence, then transcribe" architecture, not real-time streaming. (3) **LLM overwrite disasters** — the correction model must be constrained to return only the corrected span via structured JSON output with exact substring validation, never freeform text.

## Key Findings

### Recommended Stack

VoiceType is a native macOS app built in Swift 6.x with SwiftUI. No Electron, no Python, no cross-platform framework — the app must access Carbon/CGEvent, AXUIElement, Core Audio, and Core ML/ANE directly, and only native code eliminates bridging overhead for these system APIs.

**Core technologies:**
- **Swift 6.x + SwiftUI (macOS 14+):** Native integration with system APIs, first-class concurrency, `MenuBarExtra` scene for menu bar app support. AppKit used selectively for global hotkeys (CGEvent) and accessibility (AXUIElement) — SwiftUI still needs AppKit bridging for these.
- **WhisperKit ≥0.9.0:** On-device speech-to-text via Core ML on Apple Neural Engine (ANE). Swift-native, built-in VAD chunking, automatic model download. Model: `large-v3-v20240930_626MB` for production, `tiny` for development. Offline-capable — dictation works without internet.
- **AVAudioEngine:** Real-time microphone capture at 16kHz mono Float32 PCM. Built-in macOS framework, no external dependency. Tap the input node for low-latency audio buffers.
- **CGEvent.tapCreate (CoreGraphics):** Global hotkey monitoring with both key-down and key-up events — essential for "hold to talk, release to stop." More modern than deprecated Carbon `RegisterEventHotKey`. Requires Accessibility permission.
- **AXUIElement (ApplicationServices):** Read/write text in any app's text field via accessibility API. Primary text I/O strategy. `NSPasteboard` serves as clipboard-based fallback.
- **MacPaw/OpenAI Swift SDK:** GPT-4o integration for AI correction. Mature, maintained, supports streaming and structured outputs. Anthropic Claude accessed via a thin ~200-line `URLSession` wrapper since no maintained Swift SDK exists.

**What we deliberately avoid:** Electron/Tauri (no system API access), Apple SFSpeechRecognizer (network-dependent, 1-minute limit), Python subprocess (fragile packaging, IPC latency), any unmaintained Anthropic SDK.

### Expected Features

**Must have (table stakes — missing any = product feels broken):**
- Global push-to-talk hotkey with hold-and-release pattern — users expect to trigger dictation without touching the mouse
- Voice-to-text transcription with <10-15% WER (Word Error Rate) — the fundamental quality bar
- Text insertion at cursor in any application — Works in Slack, Gmail, VS Code, Notion, browser inputs
- VAD-based auto-end detection — users don't want to manually stop recording
- Auto-punctuation and capitalization — Whisper models handle most of this natively
- Filler word removal ("um", "uh", "you know") — users expect clean output
- Visual/audio recording indicator — users must know when the system is listening
- Graceful permission handling — macOS requires mic + accessibility permissions; app must guide users

**Should have (differentiators — why users choose VoiceType):**
- **Dedicated correction hotkey** — separate from dictation. This is the signature feature no competitor has
- **Natural language AI correction** — "把 X 改成 Y" style freeform commands, not rigid syntax
- **Offline-first dictation** — local Whisper inference means dictation works without internet; only correction uses cloud
- **Context-aware correction** — reads surrounding text (500 chars) so the LLM understands what you meant
- **Seamless inline text replacement** — corrections appear in-place, not in a separate window
- **Bilingual Chinese + English** — primary target languages with mixed-language support

**Defer (v2+ — don't dilute v1 focus):**
- AI content generation (write emails, code from voice) — scope creep, different product category
- Voice commands for app control ("open Chrome") — completely different technical domain
- Real-time streaming transcription — Whisper is fundamentally non-streaming; segment-based is acceptable
- Multi-speaker diarization — meeting transcription is MacWhisper's domain
- File transcription/subtitling — different product category
- Snippet/template expansion (P3, natural v2 extension once correction works)
- Cross-device sync (iPhone, iPad, Windows) — premature infrastructure complexity for v1

### Architecture Approach

VoiceType follows a **layered architecture with a central coordinator (mediator pattern)**. Five horizontal layers — Presentation (SwiftUI), Orchestration (AppCoordinator state machine), Input Capture (hotkeys + audio + VAD), Speech Processing (WhisperKit), Intelligence (LLM correction), and Text I/O (accessibility + clipboard) — are wired together by a single `AppCoordinator` actor. Subsystems never reference each other directly; the coordinator is the only coupling point. This enables independent testing, phased development, and clean fallback chains.

**Major components:**
1. **HotkeyManager** — Global hotkey registration via CGEvent tap. Two distinct hotkeys for dictation and correction modes. Must detect permission loss at runtime.
2. **AudioCapture** — AVAudioEngine wrapper producing 16kHz mono Float32 PCM. Must handle device hot-plug (AirPods disconnect, USB mic unplug). Includes silence detection guard.
3. **VADEngine** — Voice activity detection via WhisperKit's built-in silero-vad. Accumulates speech segments until user releases hotkey or silence threshold met. Requires adaptive thresholding for different acoustic environments.
4. **TranscriptionService** — WhisperKit wrapper. Model loading on background threads only. Caches model in memory (never reloads per dictation). Push-to-release architecture (never real-time streaming).
5. **CorrectionEngine** — LLM correction pipeline. Constructs context window (500 chars around cursor) + user's correction instruction. Returns structured JSON with original/replacement/confidence fields. Substring-validates before applying. Includes undo buffer.
6. **TextIO (AccessibilityBridge + ClipboardBridge)** — Protocol-based strategy selection. Primary: AXUIElement direct manipulation. Fallback: NSPasteboard with clipboard save-and-restore. Probes text field capabilities at runtime. Never operates on password fields.
7. **AppCoordinator** — Central `@MainActor` state machine. Orchestrates dictation flow (idle→recording→transcribing→inserting→idle) and correction flow (idle→readingContext→recordingCorrection→transcribing→correcting→replacing→idle). Thin router — logic lives in subsystems.
8. **MenuBarApp + Settings** — SwiftUI MenuBarExtra scene, settings window, HUD overlay. Permissions gate view on first launch. Settings stored in UserDefaults/@AppStorage; API keys in Keychain only.

### Critical Pitfalls

The full PITFALLS.md documents 12 pitfalls. These are the top 5 that shape architecture decisions, not just implementation details:

1. **Accessibility API fragility across apps** — AXUIElement works differently (or not at all) in Electron apps, terminal emulators, and custom-drawn UIs. **Prevention:** Multi-strategy fallback chain (AX → clipboard-save-restore → keystroke simulation) designed from day one. Test against a matrix of 8+ target apps, not just TextEdit. Runtime probes for `kAXSelectedTextRangeAttribute`, `kAXValueAttribute`, `kAXSelectedTextAttribute` before assuming they work.

2. **Whisper hallucination on short/streaming audio** — Feeding short chunks to Whisper produces nonsensical or repeated output (the "ghost output" problem). Especially severe on pre-Sonoma macOS with Core ML. **Prevention:** Push-to-release architecture — VAD accumulates speech until hotkey release, then sends the complete utterance to Whisper in one shot. Set minimum audio duration (300ms). Reject ultra-short clips. Never attempt real-time streaming transcription.

3. **LLM overwrites unrelated text** — The correction model, given context + instruction, tends to "improve" everything it sees, not just the target error. This destroys user trust. **Prevention:** Structured JSON output only (`{original, replacement, confidence}`). Exact substring match validation before applying. Visual diff preview with accept/reject. Mandatory undo buffer. Prompt guardrails: "ONLY change the exact text specified."

4. **Hotkey registration breaks silently after OS updates** — macOS revokes Accessibility/Input Monitoring permissions on major and minor updates. CGEvent taps fail silently — no error, just no events. **Prevention:** Runtime event tap health check (watchdog: no events in N seconds → alert). Permission status always visible in menu bar icon. Test with `tccutil reset Accessibility` to simulate revocation. Use `SMAppService` to register as login item so app restarts after updates.

5. **Clipboard-based text insertion corrupts user data** — Using clipboard as a scratchpad destroys whatever the user had copied, causes visible paste artifacts, and fails in password fields. **Prevention:** AXUIElement is always the primary strategy. Clipboard fallback MUST save and restore original contents. Never operate on `kAXIsPasswordFieldAttribute` fields. Add 100-200ms delay between clipboard write and paste event.

## Implications for Roadmap

Based on architecture build-order dependencies, feature priority (P1/P2/P3), and pitfall prevention requirements, the suggested phase structure is:

### Phase 1: Application Shell & Permissions
**Rationale:** Every other phase depends on the app being launchable, permissions grantable, and settings storable. The menu bar must appear within 1 second of launch (Pitfall 7 — no main-thread blocking). This phase also establishes the logging infrastructure all other phases use.
**Delivers:** MenuBarExtra app with settings window, first-run permission flow (mic + accessibility), Keychain API key storage, UserDefaults wrapper, OSLog-based structured logging, SMAppService login item registration.
**Addresses:** Visual recording indicator (status only), permission handling, settings infrastructure.
**Uses:** SwiftUI MenuBarExtra, AppKit (selective), swift-log.
**Avoids:** Pitfall 7 (main-thread model loading — no model code in this phase at all).

### Phase 2: Audio Capture & Global Hotkeys
**Rationale:** AudioCapture and HotkeyManager are the two foundation subsystems with zero code dependencies on each other or anything else — they can be built and tested in parallel. Both require specific macOS permission handling that must be proven before layering dictation on top.
**Delivers:** CGEvent-based global hotkey system with two configurable shortcuts (dictation + correction), AVAudioEngine audio capture pipeline at 16kHz mono Float32, audio device hot-plug handling, input silence detection guard, runtime event tap health check.
**Addresses:** Global hotkey activation, audio input from default microphone, push-to-talk key-down/key-up detection.
**Uses:** CGEvent.tapCreate, AVAudioEngine, Core Audio (AudioToolbox for device monitoring).
**Avoids:** Pitfall 4 (hotkey permission revocation — watchdog from day one), Pitfall 10 (audio device hot-plug — route change notifications), Pitfall 1 (permission lifecycle — not text I/O yet but permission patterns established).

### Phase 3: Core Dictation Pipeline
**Rationale:** This is where the product becomes usable — the first "hold key, speak, text appears" loop. Depends on AudioCapture (Phase 2) for audio buffers and HotkeyManager (Phase 2) for triggers. VAD and Text I/O must ship together because audio-to-text is worthless without text insertion. WhisperKit integration is the most technically complex subsystem — it deserves a dedicated phase.
**Delivers:** VADEngine (WhisperKit built-in VAD with adaptive thresholding), WhisperKit TranscriptionService (model download, async loading, caching, tiny model default), AccessibilityBridge (AXUIElement read/write with capability probing), ClipboardBridge (save-and-restore fallback), CompositeTextIO (strategy selection protocol), full push-to-talk dictation flow.
**Addresses:** Voice-to-text transcription, text insertion at cursor, VAD auto-end detection, auto-punctuation/capitalization, offline-first dictation, basic accuracy (WER target).
**Uses:** WhisperKit ≥0.9.0, AXUIElement, NSPasteboard.
**Avoids:** Pitfall 2 (Whisper hallucination — push-to-release architecture, 300ms minimum duration, no streaming), Pitfall 5 (clipboard corruption — save-and-restore, AX primary), Pitfall 1 (accessibility fragility — multi-strategy from day one, app compatibility matrix testing), Pitfall 6 (VAD thresholds — adaptive noise floor sampling, configurable sensitivity), Pitfall 11 (mixed language — multilingual model, language hint), Pitfall 12 (resource starvation — background QoS for inference).

### Phase 4: AppCoordinator & Basic UX
**Rationale:** With all subsystems built, the coordinator wires them into coherent flows. The menu bar UI needs to reflect live state. This phase also ships the recording indicator and basic error handling — the product now "feels" like a real app rather than a collection of libraries.
**Delivers:** AppCoordinator state machine (idle/recording/transcribing/inserting states), MenuBarView with live status display, HUD overlay for recording state, basic error recovery (audio failure, model load failure, permission loss), filler word removal post-processing.
**Addresses:** Visual/audio feedback (recording indicator), filler word removal.
**Uses:** All subsystems from Phases 1-3 integrated via coordinator.
**Avoids:** Pitfall 7 (coordinator must not block — all subsystem calls are async), Pitfall 12 (UI thread isolation from inference confirmed).

### Phase 5: AI Correction Pipeline
**Rationale:** The signature differentiator. Depends on TextIO (Phase 3) for context reading and text replacement, TranscriptionService (Phase 3) for transcribing the correction command, and AppCoordinator (Phase 4) for flow orchestration. This is an additive phase — the product already works for dictation; correction makes it special. Defers well because dictation validates the core audio→text pipeline independently.
**Delivers:** CorrectionEngine with structured JSON output enforcement, LLM client (MacPaw/OpenAI for GPT-4o, URLSession-based ClaudeClient), context window prompt template (500 chars, instruction/data separation), substring validation before applying corrections, visual diff preview with accept/reject, undo buffer for corrections (last N operations), full correction flow (correction hotkey → context read → record instruction → AI correct → replace in-place).
**Addresses:** Dedicated correction hotkey, natural language AI correction, context-aware correction, inline text replacement.
**Uses:** MacPaw/OpenAI Swift SDK, URLSession (for Claude), optional local LLM endpoint.
**Avoids:** Pitfall 3 (LLM overwrite — structured JSON, substring validation, diff preview, undo), Pitfall 8 (latency >2s — pipeline parallelization, timeout/fallback, streaming UX states, connection keep-alive), Pitfall 9 (prompt injection — instruction/data separation, text substitution only, zero-execution principle).

### Phase 6: Polish & Configuration
**Rationale:** Once core dictation and correction work, polish the experience. Configurable hotkeys, model selection for power users, multi-language toggle, and the remaining P2 features. This phase is stretch — it ships what's ready but shouldn't block launch.
**Delivers:** Configurable hotkeys UI, model selection (tiny/base/small/medium/large) with download progress, language preference (Chinese/English/mixed), auto-punctuation enhancement for mixed-language, personal dictionary infrastructure (P3 — basic version only), settings persistence.
**Addresses:** Configurable hotkeys, model selection, multi-language support (basic).
**Uses:** Existing settings infrastructure from Phase 1.

### Phase Ordering Rationale

- **Phases 1-2 can overlap partially** — the menu bar shell needs to exist before hotkeys and audio are tested end-to-end, but hotkey and audio code can start in parallel.
- **Phase 3 is the critical path** — it has the most technical risk (WhisperKit integration, accessibility API across apps, VAD tuning). Everything else depends on dictation working. No user value ships before this phase completes.
- **Phase 4 gates the first "dogfoodable" build** — before Phase 4, subsystems work in isolation but not as a coherent product. After Phase 4, you can actually use VoiceType for dictation. This is the first milestone worth showing to anyone.
- **Phase 5 is additive and defers well** — the product ships dictation without correction. Correction is what makes VoiceType special, but it doesn't block dictation validation. This independence is architecturally intentional (see Architecture anti-pattern 1: tight coupling).
- **Phase 6 is pure hedge** — ship what's ready, defer the rest. Model selection and language preferences are high-value but low-risk (all infrastructure exists from Phase 3).

### Research Flags

Phases likely needing deeper research during planning (`/gsd-plan-phase --research-phase`):
- **Phase 3 (Core Dictation):** WhisperKit integration specifics (exact API surface, model loading behavior on different Apple Silicon generations, Core ML compilation quirks), AXUIElement behavior across the 8+ app compatibility matrix, VAD adaptive thresholding algorithm specifics. This is the highest-risk phase.
- **Phase 5 (AI Correction):** Prompt engineering for structured JSON output reliability, LLM latency characteristics under real network conditions, Claude API edge cases, optimal context window size through A/B testing.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Shell & Permissions):** Well-documented SwiftUI MenuBarExtra pattern, standard macOS permission flows.
- **Phase 2 (Audio & Hotkeys):** AVAudioEngine and CGEvent taps are extensively documented with established patterns.
- **Phase 4 (Coordinator & UX):** Standard SwiftUI state management, coordinator pattern is straightforward routing.
- **Phase 6 (Polish):** Pure configuration/integration work — no novel technical challenges.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All core recommendations verified against official GitHub READMEs and documentation. WhisperKit, MacPaw/OpenAI, system frameworks all confirmed. Only MEDIUM item is soffes/HotKey (aging, Carbon dependency). |
| Features | MEDIUM | Competitor features confirmed via official product pages (Wispr Flow, MacWhisper). Differentiator classification is well-supported by cross-referencing all competitors. Table stakes represent industry consensus. Weak point: no direct user research — features are inferred from competitors and domain expertise, not validated with target users. |
| Architecture | HIGH | Patterns validated against multiple existing products (Superwhisper, MacWhisper). Component boundaries follow established macOS utility app architecture. State machine flows are deterministic and well-specified. Build order dependencies are logically sound. |
| Pitfalls | MEDIUM | Top pitfalls are drawn from well-documented failure modes in macOS accessibility, Whisper, VAD, and LLM integration. HIGH confidence in the existence of each pitfall. MEDIUM confidence in specific macOS version behaviors (OS update permission behavior evolves). LOW confidence in real-world acoustic environment VAD performance — needs empirical validation. |

**Overall confidence:** HIGH for technical decisions, MEDIUM for UX and user-facing behavior. The architecture, stack, and features are well-understood from existing products and documentation. The primary gaps are empirical: real-world VAD performance in varied acoustic environments, AXUIElement behavior across the full app compatibility matrix, and LLM correction quality on naturally occurring (not synthetic) errors.

### Gaps to Address

- **VAD threshold values for target environments:** Research provides the parameters to tune but not the values. Must be empirically tested in quiet office, café, and open-plan environments during Phase 3 planning.
- **App compatibility matrix completeness:** Architecture calls for testing against 8+ apps. The exact list and priority order needs defining during Phase 3 planning. Some apps (Figma, Adobe) may have undocumented AX limitations.
- **LLM correction accuracy on mixed Chinese/English:** Prompt engineering for bilingual correction is untested. The prompt template from ARCHITECTURE.md is a starting point but needs A/B testing with real bilingual errors during Phase 5 planning.
- **WhisperKit vs whisper.cpp fallback trigger:** The exact conditions for falling back from WhisperKit to whisper.cpp (latency thresholds, hallucination rate thresholds) need definition during Phase 3.
- **User preference defaults:** Model size, VAD sensitivity, hotkey defaults, and language preferences — these need user validation that can only happen after dogfooding. Set conservative defaults; make everything configurable in Phase 6.

## Sources

### Primary (HIGH confidence)
- [WhisperKit GitHub (argmaxinc/argmax-oss-swift)](https://github.com/argmaxinc/argmax-oss-swift) — v0.9.0 features, model catalog, Core ML integration, built-in VAD
- [whisper.cpp GitHub (ggml-org/whisper.cpp)](https://github.com/ggml-org/whisper.cpp) — v1.9.1, Core ML support, VAD integration, model sizes, documented limitations
- [MacPaw/OpenAI GitHub](https://github.com/MacPaw/OpenAI) — SDK capabilities, streaming, structured outputs, custom host configuration
- [silero-vad GitHub (snakers4/silero-vad)](https://github.com/snakers4/silero-vad) — Performance characteristics, model size, parameters, MIT license
- [Wispr Flow product page](https://wisprflow.ai) — Competitor feature set verification
- [MacWhisper product page](https://macwhisper.com) — Competitor feature set verification

### Secondary (MEDIUM confidence)
- [Superwhisper product page](https://superwhisper.com) — Competitor feature set (truncated fetch)
- [soffes/HotKey GitHub](https://github.com/soffes/HotKey) — Global hotkey wrapper pattern (aging library, Carbon dependency)
- Apple AXUIElement Documentation — API model confirmed, but current macOS behavior inferred from community knowledge
- Anthropic Swift SDK search — confirmed absence of maintained SDK (negative finding, HIGH confidence in absence)

### Tertiary (LOW confidence)
- Real-world VAD acoustic environment performance — parameters documented but specific threshold values need empirical validation
- macOS accessibility API behavior post-Sonoma — documentation is pre-Sonoma; current TCC (Transparency, Consent, and Control) behavior from community knowledge
- LLM correction quality on mixed Chinese/English — prompt template proposed but untested on real bilingual errors

---
*Research completed: 2026-07-30*
*Ready for roadmap: yes*
