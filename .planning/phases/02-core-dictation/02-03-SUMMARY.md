---
phase: 02-core-dictation
plan: 03
subsystem: ui
tags: [swiftui, nswindow, hud, dictation, pipeline, sf-symbols, mainactor]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: AudioCaptureService, AppCoordinator, HotkeyManager, MenuBarView, AppState, Logging
  - phase: 02-core-dictation
    plan: 02-01
    provides: TranscriptionService, ModelDownloadManager, TranscriptionError
  - phase: 02-core-dictation
    plan: 02-02
    provides: TextIOProtocol, CompositeTextIO, AccessibilityBridge, ClipboardBridge, TextInsertionError
provides:
  - Floating HUD overlay window (recording/transcribing status with SF Symbol icons)
  - Full dictation pipeline: hotkey → audio capture → ring buffer read → model-ready guard → transcription → text insertion → HUD lifecycle
  - State-driven menu bar icon transitions (mic.fill → mic.fill.badge.ellipsis → arrow.triangle.2.circlepath)
  - Model-loading progress via @Published modelState → statusMessage
  - Race condition guard (isDictating) per T-02-12
  - Error states with Chinese-language messages and 5-second auto-recovery
affects: [03-ai-correction, 04-settings]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "@MainActor Task pattern for main-thread UI updates after async work"
    - "Lazy HUDWindowController — NSWindow creation deferred to first use"
    - "Dual guard (30 FPS at coordinator level + TranscriptionService) for 300ms minimum audio"

key-files:
  created:
    - VoiceType/UI/HUDOverlay.swift
    - VoiceType/UI/HUDWindowController.swift
  modified:
    - VoiceType/AppCoordinator.swift
    - VoiceType/App/MenuBarView.swift
    - VoiceType/TextIO/TextIOProtocol.swift
    - VoiceType/TextIO/AccessibilityBridge.swift
    - VoiceType/TextIO/ClipboardBridge.swift

key-decisions:
  - "HUDWindowController takes AppCoordinator via init(coordinator:) — cleaner lifecycle than singleton"
  - "TextIOProtocol marked @MainActor — all implementors (AX, Clipboard) require main thread; fixes Swift 6 data-race warnings"
  - "300ms minimum audio enforced at two levels (AppCoordinator pipeline guard + TranscriptionService.transcribe()) — prevents Whisper hallucinations on ultra-short input"
  - "isDictating flag prevents overlapping dictation pipelines (T-02-12 mitigation)"
  - "Error states auto-reset to .idle after 5 seconds via Task.sleep (UXFE-02)"
  - "Ring buffer read BEFORE audioCapture.stop() — stop() calls buffer.reset() which clears data"

patterns-established:
  - "Task { @MainActor in }: non-isolated service calls captured before Task, UI mutations in @MainActor body"
  - "Lazy HUD window pattern: show() recomputes screen center each time (hotplug-safe)"
  - "Model state gating: .ready guard in onDictationKeyDown prevents recording when model unavailable"

requirements-completed: [DICT-01, DICT-07, UXFE-01, UXFE-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "HUD overlay window — recording/transcribing status with SF Symbol icons and Chinese-language messages"
    requirement: DICT-07
    verification:
      - kind: other
        ref: "swift build"
        status: pass
    human_judgment: true
    rationale: "Visual HUD correctness (positioning, transparency, Spaces visibility) requires runtime testing on macOS with actual screen geometry"
  - id: D2
    description: "Full dictation pipeline — hotkey → audio → transcribe → insert → HUD lifecycle"
    requirement: DICT-01
    verification:
      - kind: other
        ref: "swift build"
        status: pass
    human_judgment: true
    rationale: "End-to-end dictation requires actual hardware (microphone, WhisperKit model download, accessibility permissions) — not testable in CI"
  - id: D3
    description: "State-driven menu bar icon transitions and model-loading progress UX"
    requirement: [UXFE-01, UXFE-02]
    verification:
      - kind: other
        ref: "swift build"
        status: pass
    human_judgment: true
    rationale: "Menu bar icon rendering and model download progress require runtime with actual WhisperKit model download + system menu bar"

# Metrics
duration: 15min
completed: 2026-07-31
status: complete
---

# Phase 2 Plan 3: Dictation Pipeline & HUD Summary

**Full dictation loop wired into AppCoordinator with floating HUD overlay, state-driven menu bar icons, and Chinese-language error recovery**

## Performance

- **Duration:** 15min
- **Started:** 2026-07-31T09:06:37Z
- **Completed:** 2026-07-31T09:21:37Z
- **Tasks:** 3
- **Files created:** 2
- **Files modified:** 5

## Accomplishments

- Created HUD overlay (floating NSWindow with `.ultraThinMaterial` background, state-driven icon + message displayed across all Spaces)
- Wired complete dictation pipeline: Fn-down → audio capture start → HUD("🎤 录音中…") → Fn-up → ring buffer read → audio capture stop → transcribe → text insert → HUD("📝 转录中…") → HUD hide → idle
- Implemented model-ready guard + 300ms minimum audio enforcement + race condition prevention (isDictating flag)
- State-driven menu bar icon transitions: `mic.fill` (idle) → `mic.fill.badge.ellipsis` (recording) → `arrow.triangle.2.circlepath` (transcribing)
- Model-loading progress feeds `statusMessage` reactively via Combine `$modelState` sink
- Error states surface Chinese-language messages with 5-second auto-recovery timer
- Added `@MainActor` to `TextIOProtocol` and all implementations (Swift 6 concurrency correctness)

## Task Commits

Each task was committed atomically:

1. **Task 1: HUD Overlay** - `5a749f7` (feat: add HUD overlay — recording/transcribing status floating window)
2. **Task 2: AppCoordinator dictation pipeline** - `10f031b` (feat: wire full dictation pipeline into AppCoordinator)
3. **Task 3: State-driven UI** - `4e2c15d` (feat: state-driven menu bar UI — dynamic icon + status color)

## Files Created/Modified

- `VoiceType/UI/HUDOverlay.swift` - SwiftUI view: state-driven recording/transcribing status icon + message with `.ultraThinMaterial` background
- `VoiceType/UI/HUDWindowController.swift` - NSWindow lifecycle manager: `.floating` level, `.canJoinAllSpaces`, `show()`/`hide()` with dynamic screen centering
- `VoiceType/AppCoordinator.swift` - Heavily modified: full dictation pipeline replacing Phase 1 stubs; added `textIO`, `hudController`, `isDictating` guard, model state subscriber, 5s error auto-reset
- `VoiceType/App/MenuBarView.swift` - Enhanced status section: dynamic `Image(systemName:)` from coordinator.iconName; composite statusColor (permissions + run state)
- `VoiceType/TextIO/TextIOProtocol.swift` - Added `@MainActor` to protocol (Swift 6 correctness)
- `VoiceType/TextIO/AccessibilityBridge.swift` - Added `@MainActor` to AccessibilityBridge + CompositeTextIO
- `VoiceType/TextIO/ClipboardBridge.swift` - Added `@MainActor` to ClipboardBridge

## Decisions Made

- **HUDWindowController uses init(coordinator:) pattern** — AppCoordinator is not a singleton; cleaner lifecycle than shared instance
- **TextIOProtocol marked @MainActor** — all real implementors (AXUIElement, NSPasteboard, CGEvent) require main thread; fixes Swift 6 sendable warnings
- **300ms audio guard at two levels** — AppCoordinator pipeline checks before starting transcription (avoids wasted work), TranscriptionService checks before inference (safety net)
- **Ring buffer read BEFORE stop()** — per plan and CONTEXT.md critical ordering requirement (stop() → reset() clears data)
- **isDictating race guard** — prevents rapid Fn-press from starting overlapping pipelines (T-02-12 mitigation, per threat model)
- **Error auto-reset via Task.sleep** — more Swifty than DispatchQueue.main.asyncAfter; integrates cleanly with async Task context

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TextIOProtocol lacked @MainActor causing Swift 6 data-race errors**
- **Found during:** Task 2 (AppCoordinator dictation pipeline)
- **Issue:** Calling `self.textIO.insertText()` from a nonisolated `Task` triggered Swift 6's `#SendingRisksDataRace` diagnostic — MainActor-isolated `self.textIO` sent to nonisolated method
- **Fix:** Added `@MainActor` to `TextIOProtocol` protocol declaration and all three conforming types (`AccessibilityBridge`, `ClipboardBridge`, `CompositeTextIO`). Changed `Task { ... await MainActor.run { ... } }` to `Task { @MainActor in ... }` for clean isolation
- **Files modified:** `VoiceType/TextIO/TextIOProtocol.swift`, `VoiceType/TextIO/AccessibilityBridge.swift`, `VoiceType/TextIO/ClipboardBridge.swift`, `VoiceType/AppCoordinator.swift`
- **Verification:** `swift build` passes with zero concurrency warnings
- **Committed in:** `10f031b` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug/correctness)
**Impact on plan:** Essential for Swift 6 compilation. No scope creep — just correcting isolation annotations that were implicitly required by the underlying APIs.

## Known Stubs

- **Correction hotkey callback** (`AppCoordinator.swift`, `setupHotkeyCallbacks()` → `onCorrectionKeyPress`): Phase 3 placeholder — transitions to `.correcting` state with 3-second auto-reset. Intentionally deferred per plan instructions ("unchanged Phase 3 placeholder").

## Issues Encountered

None — build passed on first attempt after the @MainActor fix.

## User Setup Required

None — no external service configuration required for this plan. All changes are internal Swift code.

## Next Phase Readiness

- Dictation pipeline complete — Phase 3 (AI Correction) can build on `textIO.insertText()` for in-place text correction
- `onCorrectionKeyPress` callback stub ready for Phase 3 wiring
- HUD pattern reusable for correction status display (different icon/message)
- `CompositeTextIO` fallback chain handles AX → clipboard transparently for correction text insertion

---
*Phase: 02-core-dictation*
*Completed: 2026-07-31*
