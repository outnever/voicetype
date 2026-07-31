---
phase: 02-core-dictation
plan: 01
subsystem: Transcription
tags: [speech-to-text, whisperkit, model-download, filler-words, bilingual]
requires: []
provides: [TranscriptionService, ModelDownloadManager, TranscriptionError]
affects: [AppCoordinator, Logging]
tech-stack:
  added: [WhisperKit 0.18.0 (argmax-oss-swift), swift-testing, Combine]
  patterns: [@MainActor ObservableObject singleton, Task.detached inference, @preconcurrency import]
key-files:
  created:
    - VoiceType/Transcription/TranscriptionService.swift
    - VoiceType/Transcription/TranscriptionError.swift
    - VoiceType/Transcription/ModelDownloadManager.swift
  modified:
    - VoiceType/Utilities/Logging.swift
    - VoiceType/AppCoordinator.swift
    - Package.swift
    - VoiceType/TextIO/AccessibilityBridge.swift
decisions:
  - "WhisperKit 0.18.0 convenience init(model:verbose:logLevel:download:) used — computeOptions defaults to .cpuAndNeuralEngine on macOS 14+"
  - "@preconcurrency import WhisperKit to handle non-Sendable pipe in Task.detached"
  - "TranscriptionError Equatable via case-only comparison (ignores underlying Error value)"
  - "ModelDownloadManager.initialize(idempotent) — duplicate calls skip if already .ready or .downloading"
  - "Model state sync via Combine pipeline: modelDownloadManager.$modelState.assign(to: &$modelState)"
metrics:
  duration: TBD
  completed_date: 2026-07-31
status: complete
---

# Phase 02 Plan 01: Transcription Pipeline Summary

**One-liner:** Offline speech-to-text transcription service wrapping WhisperKit 0.18.0 with async model download, VAD-based chunking, bilingual auto-detection, and filler word removal — wired into AppCoordinator for Phase 2 dictation pipeline.

## Tasks Completed

| # | Task | Type | Commits | Key Files |
|---|------|------|---------|-----------|
| 1 | ModelDownloadManager + TranscriptionError + Logging | tdd | f7add34 (RED), 4bf5352 (GREEN), 28656a4 (fix) | ModelDownloadManager.swift, TranscriptionError.swift, Logging.swift, ModelDownloadManagerTests.swift |
| 2 | TranscriptionService.transcribe(audioArray:) | tdd | 235df01 (RED), 8089fdd (GREEN) | TranscriptionService.swift, TranscriptionServiceTests.swift |
| 3 | Wire into AppCoordinator | auto | 37c033f | AppCoordinator.swift |

## Key Deliverables

### TranscriptionError.swift
- 4 typed error cases: `modelNotDownloaded`, `modelDownloadFailed(underlying:)`, `transcriptionFailed(underlying:)`, `audioTooShort`
- All conform to `LocalizedError` with Chinese descriptions and `failureReason`/`recoverySuggestion`
- Custom `Equatable` — cases with `Error` associated values compared by case label only

### ModelDownloadManager.swift
- `@MainActor final class ModelDownloadManager: ObservableObject`
- `@Published var modelState: ModelState` — reactive state for UI (notLoaded / downloading(progress:) / loading(String) / ready / error(String))
- `func initialize(modelName:) async` — idempotent async model download + loading via `Task.detached`
- `func getPipe() -> WhisperKit?` — returns cached pipe for transcription
- **D-04 compliant:** All WhisperKit operations in `Task.detached(priority: .userInitiated)` — never blocks main thread

### TranscriptionService.swift
- `@MainActor final class TranscriptionService: ObservableObject`
- `func transcribe(audioArray: [Float]) async throws -> String`
- **Guard 1:** Model-ready check → throws `.modelNotDownloaded`
- **Guard 2:** Minimum 300ms audio duration → throws `.audioTooShort` (PITFALLS.md §2)
- **Inference:** `DecodingOptions(task: .transcribe, detectLanguage: true, skipSpecialTokens: true, chunkingStrategy: .vad)` in `Task.detached(priority: .userInitiated)`
- **Post-processing:** `removeFillerWords()` regex filter for Chinese (呃, 嗯, 那个, 就是) and English (um, uh, you know) fillers
- **D-14:** bilingual auto-detection via `detectLanguage: true`
- **D-05:** VAD chunking via `chunkingStrategy: .vad`

### Logging.swift
- `static let transcription = Logger(label: "com.voicetype.app.transcription")` — new label for model download, inference, and filler word removal logging

### AppCoordinator Integration
- `modelDownloadManager` and `transcriptionService` instances owned by AppCoordinator
- `@Published var modelState` mirrors ModelDownloadManager state via Combine pipeline
- `modelDownloadManager.initialize()` called in `initializeSubsystems()` after permissions — model download starts in background, menu bar stays responsive

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Pre-existing `kAXIsPasswordFieldAttribute` missing from ApplicationServices**
- **Found during:** Task 1 (Plan 02-02 code committed earlier blocked my build)
- **Fix:** Defined private constant `"AXIsPasswordField" as CFString` locally in AccessibilityBridge.swift
- **Files modified:** `VoiceType/TextIO/AccessibilityBridge.swift`
- **Commit:** 4bf5352

**2. [Rule 3 — Blocking] Pre-existing Swift 6 concurrency errors in AccessibilityBridge**
- **Found during:** Task 1 (CFString, AXUIElement non-Sendable in strict concurrency)
- **Fix:** Added `@preconcurrency import ApplicationServices` and `nonisolated(unsafe)` on the constant
- **Files modified:** `VoiceType/TextIO/AccessibilityBridge.swift`
- **Commit:** 4bf5352

**3. [Rule 1 — Bug] Task.detached closure signature needed explicit throw/return types**
- **Found during:** Task 2 GREEN
- **Fix:** Changed `{ ... }` to `{ () throws -> [TranscriptionResult] in ... }` with explicit type annotation
- **Files modified:** `VoiceType/Transcription/TranscriptionService.swift`
- **Commit:** 8089fdd

**4. [Rule 1 — Bug] Test file accidentally deleted during git add**
- **Found during:** Task 1 GREEN commit
- **Fix:** Restored from previous commit (f7add34), re-applied GREEN edits
- **Commit:** 28656a4

### WhisperKit 0.18.0 API Adaptations

- **Plan specifies `WhisperKit(WhisperKitConfig(...))`** → Used convenience init `WhisperKit(model:verbose:logLevel:download:)` which internally creates a `WhisperKitConfig`.
- **Plan specifies `computeUnits: .cpuAndNeuralEngine`** → Default `ModelComputeOptions` already uses `.cpuAndNeuralEngine` for audio encoder on macOS 14+ — no override needed.
- **Plan specifies `DecodingOptions(chunkingStrategy: .vad, skipSpecialTokens: true, detectLanguage: true)`** → Parameter order adjusted: `skipSpecialTokens` must precede `chunkingStrategy` in initializer.
- **`transcribe(audioArray:decodeOptions:)` returns `[TranscriptionResult]`** → Each `TranscriptionResult` has `.text` and `.segments`; joined all segment texts.

## Test Coverage

**29 tests across 5 suites, all passing:**

| Suite | Tests | Focus |
|-------|-------|-------|
| ModelDownloadManager — Model State & Error Types | 16 | ModelState transitions, Equatable, TranscriptionError Chinese descriptions, filler word regex |
| TranscriptionService — Structure & Error Handling | 5 | modelNotDownloaded guard, audioTooShort guards, ObservableObject conformance |
| AccessibilityBridge (Plan 02-02) | 5 | TextIOProtocol conformance, error handling, password field detection |
| TextInsertionError (Plan 02-02) | 3 | LocalizedError conformance |
| TextIOProtocol (Plan 02-02) | 0 (compiled) | Protocol type checking |

**TDD Gate Compliance:**
- RED commits: f7add34 (Task 1), 235df01 (Task 2)
- GREEN commits: 4bf5352 (Task 1), 8089fdd (Task 2)
- No REFACTOR phase needed — code was clean on first GREEN pass

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: info_disclosure | VoiceType/Transcription/TranscriptionService.swift | Transcribed text held in-memory after RingBuffer read — no audio persisted to disk (as designed per T-02-01 mitigation) |
| threat_flag: info_disclosure | VoiceType/Utilities/Logging.swift | Log.transcription logs character count and duration but never raw text — T-02-05 mitigation verified in implementation |

## Known Stubs

None — all code is fully implemented with production-ready error handling. Model download state is reactive via `@Published modelState` and consumed by AppCoordinator; UI integration will be in Plan 03.

## Self-Check

All files exist and are committed:
- `VoiceType/Transcription/TranscriptionService.swift` — ✓ committed in 8089fdd
- `VoiceType/Transcription/TranscriptionError.swift` — ✓ committed in 4bf5352
- `VoiceType/Transcription/ModelDownloadManager.swift` — ✓ committed in 4bf5352
- `VoiceType/Utilities/Logging.swift` — ✓ modified in 4bf5352
- `VoiceType/AppCoordinator.swift` — ✓ modified in 37c033f
- `Tests/VoiceTypeTests/ModelDownloadManagerTests.swift` — ✓ committed in f7add34/28656a4
- `Tests/VoiceTypeTests/TranscriptionServiceTests.swift` — ✓ committed in 235df01

Build: `swift build` — 0 errors ✓
Tests: `swift test` — 29 passed, 0 failed ✓

## Self-Check: PASSED
