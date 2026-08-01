# Phase 2 Plan Verification — 02-CHECK.md

**Phase:** 02-core-dictation
**Verified:** 2026-07-31
**Plans checked:** 02-01, 02-02, 02-03
**Gate type:** Revision Gate (plan-checker → revise → re-check, max 3 iterations)
**Status:** ❌ ISSUES FOUND — 1 BLOCKER, 2 WARNINGS

---

## Requirement Coverage

All 11 phase requirements (DICT-01~08, UXFE-01~03) trace to plan tasks:

| Requirement | Plan(s) | Tasks | Status |
|-------------|---------|-------|--------|
| DICT-01 (hold→speak→release→text) | 02-03 | Task 2 | ✅ Covered |
| DICT-02 (VAD auto-detection) | 02-01 | Task 2 | ✅ Covered |
| DICT-03 (offline dictation) | 02-01 | Task 1,2 | ✅ Covered |
| DICT-04 (auto-punctuation/caps) | 02-01 | Task 2 | ✅ Covered |
| DICT-05 (filler word removal) | 02-01 | Task 1,2 | ✅ Covered |
| DICT-06 (cross-app text insertion) | 02-02 | Task 1,2 | ✅ Covered |
| DICT-07 (visual recording indicator) | 02-03 | Task 1 | ✅ Covered |
| DICT-08 (<15% WER bilingual) | 02-01 | Task 2 | ✅ Covered |
| UXFE-01 (menu bar state reflection) | 02-03 | Task 3 | ✅ Covered |
| UXFE-02 (error state + recovery) | 02-03 | Task 2,3 | ✅ Covered |
| UXFE-03 (bilingual out-of-box) | 02-01 | Task 2 | ✅ Covered |

**Verdict:** All 11 requirements covered. ✅

---

## Success Criteria Coverage

| # | Success Criterion | Plans | Verdict |
|---|-------------------|-------|---------|
| 1 | Hold Fn → speak → release → text at cursor with punctuation | 02-03 (pipeline) + 02-02 (insertion) + 02-01 (transcription) | ⚠️ See BLOCKER below |
| 2 | Fully offline dictation | 02-01 (WhisperKit local) | ✅ |
| 3 | Menu bar icon reflects recording/transcribing/idle | 02-03 Task 3 | ✅ |
| 4 | Errors show Chinese recovery guidance | 02-03 Task 2,3 (error paths) | ✅ |
| 5 | Bilingual Chinese+English <15% WER | 02-01 Task 2 (large-v3, detectLanguage) | ✅ |

**Verdict:** SC 2-5 structurally addressed. SC 1 is blocked by the integration bug (see BLOCKER). ⚠️

---

## CONTEXT.md Decision Compliance

All 19 locked decisions (D-01~D-19) checked:

| Decision | Plan | Task | Verdict |
|----------|------|------|---------|
| D-01 (tiny dev, large-v3 prod) | 02-01 | Task 1 | ⚠️ WARNING — see below |
| D-02 (async download with progress) | 02-01 | Task 1 | ✅ |
| D-03 (cache model in memory) | 02-01 | Task 1 | ✅ |
| D-04 (background thread, no blocking) | 02-01 | Task 1,3 | ✅ |
| D-05 (WhisperKit built-in VAD) | 02-01 | Task 2 | ✅ |
| D-06 (VAD silence + manual release) | 02-03 | Task 2 | ✅ |
| D-07 (hotkey release immediate transcribe) | 02-03 | Task 2 | ✅ |
| D-08 (AXUIElement primary strategy) | 02-02 | Task 1 | ✅ |
| D-09 (clipboard fallback) | 02-02 | Task 2 | ✅ |
| D-10 (skip password fields) | 02-02 | Task 1,2 | ✅ |
| D-11 (HUD "录音中…") | 02-03 | Task 1 | ✅ |
| D-12 (HUD auto-dismiss) | 02-03 | Task 2 | ✅ |
| D-13 (menu bar icon per state) | 02-03 | Task 3 | ✅ |
| D-14 (bilingual auto-detect) | 02-01 | Task 2 | ✅ |
| D-15 (Whisper built-in punctuation) | 02-01 | Task 2 | ✅ |
| D-16 (filler word removal) | 02-01 | Task 1 | ✅ |
| D-17 (model not loaded → prompt) | 02-01, 02-03 | Task 1,2 | ✅ |
| D-18 (audio device unavailable → prompt) | 02-03 | Task 2 | ✅ |
| D-19 (AX fails → auto fallback) | 02-02, 02-03 | Task 2 | ✅ |

**Verdict:** 18/19 decisions clearly respected. D-01 has a WARNING.

---

## ISSUES FOUND

### 🔴 BLOCKER (must fix before execution)

**1. [Integration Correctness] Dictation pipeline reads audio buffer AFTER `stop()` resets it — transcription will ALWAYS receive empty audio**

- **Plan:** 02-03
- **Task:** 2 (AppCoordinator dictation pipeline)
- **Severity:** BLOCKER
- **Description:**

  Plan 03 Task 2 implements the dictation pipeline as:
  ```swift
  self.audioCapture.stop()                                    // ← calls buffer.reset()!
  let audioSamples = self.audioCapture.buffer.read(count: …)  // ← reads EMPTY buffer
  ```

  Phase 1's `AudioCaptureService.stop()` (line 196 of `AudioCaptureService.swift`) calls `buffer.reset()`, which zeros out the RingBuffer (readIndex=0, writeIndex=0, count=0, all `storage[i]=nil`). The subsequent `buffer.read()` returns an empty array `[]`. The 300ms minimum check will always fail, and NO transcription will ever occur.

  **Root cause:** The plan was written without checking the Phase 1 implementation of `stop()`. The assumption was that `stop()` only stops the audio engine while preserving the captured samples.

- **Fix options:**

  **Option A (recommended):** Flip the order — read BEFORE stop:
  ```swift
  self.audioCapture.stopEngineOnly()  // stop tap but don't reset buffer
  let audioSamples = self.audioCapture.buffer.read(count: AudioConstants.maxBufferCapacity)
  self.audioCapture.buffer.reset()    // clean up after reading
  ```
  This requires either adding `stopEngineOnly()` to AudioCaptureService or modifying `stop()` to accept a `preserveBuffer: Bool` parameter.

  **Option B:** Read before calling stop(), then stop after:
  ```swift
  let audioSamples = self.audioCapture.buffer.read(count: AudioConstants.maxBufferCapacity)
  self.audioCapture.stop()
  ```
  Race condition risk: the audio tap could still be writing to the buffer during the read. Safe if read+stop are on the same thread, but fragile.

  **Option C:** Modify Phase 1's `AudioCaptureService.stop()` to NOT reset the buffer, and add a separate `resetBuffer()` call. Then Plan 03 calls `stop()` → `read()` → `resetBuffer()`.

  **Option D:** Use `AudioCaptureService.readSamples(count:)` before calling `stop()`. This method exists (line 215 of AudioCaptureService.swift) and reads without consuming — but it's also subject to the same ordering constraint.

  **Preferred fix:** Option A — add a lightweight method to AudioCaptureService that stops the engine/tap without resetting the buffer, or extend Plan 01 to split `stop()` into `stop()` (engine only) and `reset()` (buffer). This preserves the clean separation of concerns.

- **Impact if not fixed:** Dictation never produces text. Phase 2 functionally broken at the core loop. Execution would waste context.

---

### 🟡 WARNINGS (should fix; execution could proceed with caution)

**1. [Context Compliance - D-01] ModelDownloadManager defaults to large-v3, but CONTEXT.md D-01 specifies "默认使用 tiny 模型开发迭代"**

- **Plan:** 02-01
- **Task:** 1 (ModelDownloadManager)
- **Severity:** WARNING
- **Description:**

  D-01 is a locked decision: "默认使用 `tiny` 模型开发迭代，生产使用 `large-v3-v20240930_626MB`". The plan's `ModelDownloadManager.initialize()` defaults to:
  ```swift
  func initialize(modelName: String = "openai_whisper-large-v3-v20240930_626MB") async
  ```
  The default is large-v3, not tiny. Both model paths are supported (the `modelName` parameter is fully configurable), so the "both paths must be supported" requirement of D-01 is satisfied. However, the default value contradicts the decision.

  **Mitigating factor:** Phase 2 requires bilingual dictation with <15% WER (DICT-08, SC5). The tiny model cannot achieve this accuracy for Chinese+English code-switching. The planner likely chose large-v3 as the practical production default for a deliverable MVP. But D-01 is explicit about defaults.

- **Fix:** Add a comment explaining the deviation: "D-01 specifies tiny as default for development iterations; Phase 2 MVP uses large-v3 for sufficient accuracy. The tiny model remains available via `initialize(modelName: "openai_whisper-tiny")`." Or align the default to tiny and let the AppCoordinator override to large-v3 for Phase 2.

---

**2. [Research Resolution] RESEARCH.md Open Questions lack formal RESOLVED markers**

- **Plan:** N/A (phase-level artifact)
- **Severity:** WARNING
- **Description:**

  RESEARCH.md has a `## Open Questions` section with three questions. The section heading lacks the `(RESOLVED)` suffix, and individual questions lack inline `RESOLVED` markers. All three questions have substantive resolutions (clear recommendations that the plans incorporate):
  1. WhisperKit API exact labels → "实现时根据 Xcode 自动补全确认" ✅ substance resolved
  2. VAD silence threshold → "先用 WhisperKit 默认参数" ✅ substance resolved
  3. AXUIElement vs clipboard fallback timing → "Phase 2 mvp 先实现简单回退" ✅ substance resolved

- **Fix:** Change the heading to `## Open Questions (RESOLVED)` and add `RESOLVED:` prefix to each question's recommendation line. This is a 30-second fix in RESEARCH.md.

---

## Plan Summary

| Plan | Tasks | Files Modified | Wave | Dependencies | Verdict |
|------|-------|---------------|------|-------------|---------|
| 02-01 | 3 | 4 | 1 | none | ✅ Valid (1 warning) |
| 02-02 | 2 | 4 | 1 | none | ✅ Valid |
| 02-03 | 3 | 4 | 2 | 02-01, 02-02 | ❌ BLOCKER (integration bug) |

---

## Dimension-by-Dimension Report

| Dimension | Status | Notes |
|-----------|--------|-------|
| 1. Requirement Coverage | ✅ PASS | All 11 requirements traced to tasks |
| 2. Task Completeness | ✅ PASS | All 8 tasks have Files + Action + Verify + Done |
| 3. Dependency Correctness | ❌ BLOCKER | Plan 03 → Phase 1 integration: buffer read-after-reset bug |
| 4. Key Links Planned | ✅ PASS | All artifacts properly wired |
| 5. Scope Sanity | ✅ PASS | 8 tasks / ~12 files across 3 plans — within budget |
| 6. Verification Derivation | ✅ PASS | Truths are user-observable; artifacts+links support them |
| 7. Context Compliance | ⚠️ WARNING | D-01 default model deviates from locked decision |
| 7b. Scope Reduction | ✅ PASS | No scope reduction language detected |
| 7c. Architectural Tier | ✅ PASS | All capabilities assigned to correct tiers |
| 8. Nyquist Compliance | ⏭️ SKIPPED | `nyquist_validation: false` in config.json |
| 9. Cross-Plan Data Contracts | ✅ PASS | Float32 audio + String text contracts consistent |
| 10. AGENTS.md Compliance | ✅ PASS | All platform/stack constraints respected |
| 11. Research Resolution | ⚠️ WARNING | Open Questions lack formal RESOLVED markers |
| 12. Pattern Compliance | ⏭️ SKIPPED | No PATTERNS.md for this phase |
| Verify Command Format | ✅ PASS | All use simple `swift build` — no regex/pipe issues |

---

## Recommendation

**1 BLOCKER** requires plan revision before execution can proceed. The dictation pipeline in Plan 03 Task 2 must be corrected to read the audio buffer BEFORE calling `stop()`, or Phase 1's `AudioCaptureService.stop()` must be modified to preserve the buffer.

**2 WARNINGS** are non-blocking but should be addressed:
- Align ModelDownloadManager's default model with D-01 or document the deviation
- Mark RESEARCH.md Open Questions as formally resolved

**Next step:** Return to planner (max 3 revision loops per Revision Gate). Fix the BLOCKER first, then address warnings. Re-run `/gsd-plan-phase 2` for re-verification.

---

*Plan check completed: 2026-07-31*
*Gate: Revision Gate — iteration 1 of 3*
