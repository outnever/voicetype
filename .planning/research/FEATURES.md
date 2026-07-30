# Feature Research: VoiceType

**Domain:** macOS voice dictation with AI-powered correction
**Researched:** 2026-07-30
**Confidence:** MEDIUM

**Note on confidence:** Sources are official product pages (Wispr Flow, MacWhisper, Superwhisper), GitHub repositories (whisper.cpp, silero-vad), and technical documentation — all authoritative for feature claims. Cross-referenced across multiple independent products to validate patterns. Provider-level classification is LOW for webfetch but source-level quality is HIGH for official sources.

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing any of these = product feels broken or incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Global hotkey activation (hold-to-talk) | Every dictation tool (Wispr Flow, Superwhisper, MacWhisper, macOS built-in) uses Fn key or custom shortcut. Users expect to trigger dictation without touching mouse. | MEDIUM | Requires CGEvent event tap or Carbon global hotkey registration. Must coexist with other apps' hotkeys. |
| Voice-to-text transcription (speech → typed text) | Core function. All competitors do this. MacWhisper uses local Whisper, Superwhisper/Wispr Flow use hybrid local+cloud. | MEDIUM | whisper.cpp with Core ML provides ~3x speedup on Apple Silicon. Model choice (base vs small vs medium) trades accuracy for latency. |
| Text insertion at cursor in any app | Wispr Flow works in Slack, Gmail, Cursor, Notion — "any app with a text field." Superwhisper same claim. Users expect universal insertion. | MEDIUM | macOS Accessibility API (AXUIElement) or clipboard paste. Accessibility API is more reliable for targeting exactly where cursor is. |
| Push-to-talk VAD (auto-detect speech end) | Users don't want to manually stop recording. Wispr Flow auto-detects end of speech. silero-vad is industry standard for this. | LOW | silero-vad: <1ms per 30ms audio chunk, 2MB model, 8kHz/16kHz rates. whisper.cpp has native VAD integration (`--vad` flag). |
| Auto-punctuation and capitalization | macOS built-in dictation does this. Wispr Flow does it. Table stakes for text quality. | LOW | Whisper models natively predict punctuation. Some post-processing may be needed for consistency. |
| Basic accuracy (WER < 10-15%) | Users will abandon if transcription is frequently wrong. This is the fundamental quality bar. | DEPENDS | Whisper base.en model is ~12% WER on clean speech. small.en drops to ~8%. medium drops to ~6%. Model selection is a key tradeoff. |
| Filler word removal ("um", "uh", "you know") | Wispr Flow explicitly markets this. Users expect clean output, not raw transcript. | LOW | Can be done at Whisper level (model does this naturally to some degree) or post-processing. |
| Audio input from default microphone | Users expect it to "just work" with built-in mic or headset. | LOW | Standard AVAudioEngine / AudioUnit capture at 16kHz mono. |
| Visual/audio feedback (recording indicator) | Users need to know when the system is listening. Essential usability. | LOW | macOS menu bar icon, overlay, or HUD indicating listening state. |
| Permission handling (mic, accessibility) | macOS requires explicit permissions. App must gracefully request and guide users. | LOW | Standard macOS permission flows. Accessibility permission is the tricky one — many users won't know how to grant it. |

### Differentiators (Competitive Advantage)

Features that set VoiceType apart. These justify why users would choose VoiceType over Wispr Flow, Superwhisper, or MacWhisper.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Dedicated correction hotkey** (separate from dictation) | This is VoiceType's signature feature. Press one key for dictation, another to say "fix X to Y." No other competitor has a dedicated correction mode — they do everything in one flow or require manual text selection + retype. | HIGH | Requires: detecting active app cursor position, reading surrounding text context, sending to LLM with natural language instruction, replacing text in-place. Multi-step pipeline. |
| **Natural language AI correction commands** | "把 X 改成 Y" — freeform natural language, not rigid commands. Wispr Flow has "backtrack" (instant undo of last utterance) but NOT freeform correction of arbitrary text already on screen. This is a genuine differentiator. | HIGH | Prompt engineering is critical: must send context window + user instruction and get back only the corrected text fragment. Must respect exact cursor position. |
| **Offline-first dictation** (Whisper local, no cloud for transcription) | Privacy advantage. MacWhisper does this but is transcription-focused, not dictation-focused. Wispr Flow and Superwhisper use cloud models. VoiceType's dictation works offline; only correction uses cloud. | MEDIUM | Requires bundling whisper.cpp + ggml model. Disk: base.en ~142MB, small.en ~466MB. Memory: base ~388MB, small ~852MB at runtime. |
| **Context-aware correction** (reads surrounding text for context) | When user says "change 'teh' to 'the'", the LLM sees the full sentence/paragraph around cursor, not just the target words. This enables smarter corrections (e.g., knowing "read" should be "red" based on surrounding words). | HIGH | Requires Accessibility API to read text before/after cursor. Must handle edge cases: no text near cursor, text in non-standard UI elements. |
| **Seamless inline text replacement** | Correction result appears in-place, not in a separate window. User doesn't leave their flow. | MEDIUM | Accessibility API or clipboard-based replacement. Must preserve cursor position after replacement. |
| **Bilingual/multilingual dictation** (Chinese + English primary) | Superwhisper and Wispr Flow support 100+ languages but don't specialize. VoiceType can win by being excellent at Chinese dictation + English, with correction supporting mixed-language text. | MEDIUM | Whisper large-v3 supports 99 languages including Chinese. Quality varies by language. Chinese-specific post-processing may be needed. |

### Anti-Features (Deliberately NOT Building)

Features that seem attractive but would dilute VoiceType's focus, create complexity without value, or are better left to other tools.

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| AI content generation (write emails, code, essays from voice prompts) | Users often ask "can it write a message for me?" | This makes VoiceType an AI writing tool, not a dictation+correction tool. Massive scope creep. Wispr Flow does AI auto-edits but not generation. Apple Intelligence already does this. | Focus on correction of existing text. Let users use ChatGPT/Claude/Copilot for generation. |
| Voice commands for app control ("open Chrome", "scroll down") | macOS has a history of voice control systems | This is a completely different technical domain (AppleScript, UI automation). High complexity, low overlap with dictation. | Use macOS built-in Voice Control for this. VoiceType stays focused on text I/O. |
| Real-time streaming transcription (words appear as you speak) | Looks impressive in demos. | Whisper is fundamentally non-streaming — it works on audio segments. Real-time streaming would require a completely different ASR architecture (like DeepSpeech or proprietary cloud APIs). Adds massive latency/accuracy tradeoffs. | Use segment-based processing (dictate → release key → brief pause → text appears). Acceptable latency for dictation use case. |
| Multi-speaker diarization (identify who said what) | Useful for meeting transcription. | Whisper.cpp has experimental tinydiarize but it's not production-ready. Adds complexity without serving the dictation+correction use case. | This is MacWhisper's domain (transcription tool). VoiceType is for solo dictation. |
| Video/audio file transcription and subtitling | MacWhisper has this as a core feature. | Completely different product category. Would require file management UI, export formats, timeline editing. | Use MacWhisper for file transcription. VoiceType stays focused on live dictation. |
| Persistent audio recording storage | Users might want to review what they said. | Privacy risk: storing voice recordings creates a data liability. VoiceType's value is text output, not audio archiving. | Transient audio — process and discard. If users need recordings, use a dedicated voice memo app. |
| Custom voice commands/triggers (snippet expansion) | Wispr Flow has a "Snippets" feature where saying "calendar" inserts a scheduling link. | This is text expansion, not dictation correction. While useful, it's a separate product feature that would distract from the core correction pipeline in v1. | Low-priority v2 feature. Once core correction works, snippet expansion is a natural extension. |
| Cross-device sync (iPhone, iPad, Windows) | Wispr Flow markets this heavily. | Significant infrastructure complexity (cloud sync, multiple codebases). Premature for v1. | v1: macOS only. If validated, mobile companion could be a future milestone. |

## Feature Dependencies

```
Natural Language AI Correction
    ├──requires──> Context-Aware Text Reading (Accessibility API read)
    │                  └──requires──> Accessibility Permission
    ├──requires──> Inline Text Replacement (Accessibility API write)
    │                  └──requires──> Accessibility Permission
    ├──requires──> LLM Integration (GPT-4o or Claude API)
    │                  └──requires──> Network connectivity
    └──requires──> Dedicated Correction Hotkey
                       └──requires──> Global Hotkey System

Push-to-Talk Dictation
    ├──requires──> Global Hotkey System (dictation hotkey)
    ├──requires──> Audio Capture (microphone)
    │                  └──requires──> Microphone Permission
    ├──requires──> Local Whisper Inference (whisper.cpp + Core ML)
    ├──requires──> VAD (silero-vad) for auto-end detection
    └──requires──> Text Insertion at Cursor
                       └──requires──> Accessibility Permission

Offline-First Dictation
    └──requires──> Local Whisper Inference
                       └──requires──> Bundled ggml model file
```

### Dependency Notes

- **AI Correction requires Accessibility API:** Unlike dictation (which can fall back to clipboard paste), correction MUST read surrounding text and replace text in-place. This means the Accessibility permission is non-optional for the correction feature.
- **LLM integration is the only cloud dependency:** Everything else (audio capture, VAD, Whisper inference) runs locally. This means dictation works fully offline; only correction needs network.
- **Global hotkey system is shared infrastructure:** Both dictation and correction hotkeys use the same event tap / hotkey registration system. Build once, configure twice.

## MVP Definition

### Launch With (v1)

Minimum viable product — what's needed to validate the concept.

- [ ] **Push-to-Talk Dictation** — Core function. Hold hotkey, speak, release, text appears at cursor. Must work in any app. This is the "must work before anything else."
- [ ] **Global Hotkey System** — Both dictation and correction rely on this. Build once with two configurable shortcuts.
- [ ] **VAD-based Auto-End Detection** — Automatic speech end detection so users don't need to time their release. silero-vad integration is well-established and low complexity.
- [ ] **Natural Language AI Correction** — The signature differentiator. Press correction hotkey, speak "把 X 改成 Y", AI fixes text in-place. This validates the core value proposition.
- [ ] **Context-Aware Text Reading** — Required by correction. Read text around cursor for LLM context.
- [ ] **Inline Text Replacement** — Required by correction. Replace text at cursor position without disturbing surrounding content.

### Add After Validation (v1.x)

Features to add once core dictation+correction is working and validated.

- [ ] **Filler Word Removal** — Post-process Whisper output to strip "um", "uh", etc. Low complexity, high polish value.
- [ ] **Auto-Punctuation Enhancement** — Whisper does basic punctuation; enhance for edge cases (Chinese punctuation, mixed-language).
- [ ] **Visual Recording Indicator** — Menu bar icon or overlay showing "listening" / "processing" / "done" states.
- [ ] **Configurable Hotkeys** — Let users change dictation and correction hotkeys from settings.
- [ ] **Model Selection** — Let power users choose Whisper model size (tiny/base/small/medium) for speed vs accuracy tradeoff.

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Snippet/Template Expansion** — Voice shortcuts for frequently used text. (Wispr Flow-style "say 'calendar' → insert scheduling link")
- [ ] **Personal Dictionary** — Learn user-specific words, names, and jargon over time.
- [ ] **Multi-Language Support** — Extend beyond Chinese+English to broader language support.
- [ ] **Style/Tone Adaptation** — Adjust output formality based on context (email vs chat vs document).
- [ ] **Cross-App Profiling** — Different correction behavior in code editors vs email vs chat.
- [ ] **Windows Support** — Port to Windows after macOS validated.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Push-to-Talk Dictation | HIGH | MEDIUM | P1 |
| Global Hotkey System | HIGH | MEDIUM | P1 |
| VAD Auto-End Detection | HIGH | LOW | P1 |
| Natural Language AI Correction | HIGH (differentiator) | HIGH | P1 |
| Context-Aware Text Reading | HIGH (enables correction) | HIGH | P1 |
| Inline Text Replacement | HIGH (enables correction) | MEDIUM | P1 |
| Offline-First (Local Whisper) | MEDIUM | MEDIUM | P1 |
| Filler Word Removal | MEDIUM | LOW | P2 |
| Auto-Punctuation Enhancement | MEDIUM | LOW | P2 |
| Visual Recording Indicator | MEDIUM | LOW | P2 |
| Configurable Hotkeys | LOW | LOW | P2 |
| Model Selection | LOW | LOW | P2 |
| Snippet/Template Expansion | MEDIUM | MEDIUM | P3 |
| Personal Dictionary | LOW | MEDIUM | P3 |
| Style/Tone Adaptation | LOW | HIGH | P3 |
| Windows Support | HIGH | HIGH | P3 |

**Priority key:**
- P1: Must have for launch (v1 MVP)
- P2: Should have, add when possible (v1.x)
- P3: Nice to have, future consideration (v2+)

## Competitor Feature Analysis

| Feature | Wispr Flow | Superwhisper | MacWhisper | Apple Dictation (built-in) | VoiceType |
|---------|------------|--------------|------------|----------------------------|-----------|
| Global push-to-talk | Yes (⌥+Space) | Yes | Yes (dictation mode) | Yes (Fn key) | Yes |
| System-wide text insertion | Yes (all apps) | Yes (all apps) | Yes | Yes (all apps) | Yes |
| Local/offline dictation | No (cloud hybrid) | No (cloud) | Yes (local Whisper) | Yes (on-device) | **Yes (local Whisper)** |
| AI auto-edits/cleanup | Yes (filler removal, format) | Yes (polish mode) | No (raw transcript) | No | P2 (filler removal) |
| **Dedicated correction hotkey** | No | No | No | No | **Yes (signature)** |
| **Natural language "fix X to Y"** | No (only backtrack) | No (only retype) | No | No | **Yes (signature)** |
| Personal dictionary | Yes | Yes | No | No | P3 |
| Snippet expansion | Yes | Unknown | No | No | P3 |
| Multi-language | 100+ languages | Yes | 100+ languages | Yes | P3 (CN+EN first) |
| File transcription | No | No | Yes (core feature) | No | No (anti-feature) |
| Meeting recording | No | No | Yes | No | No (anti-feature) |
| Cross-device sync | Yes (Mac, Win, iOS, Android) | Mac, Win, iOS | Mac only | Apple ecosystem only | macOS only (v1) |
| Developer code-aware dictation | Yes (syntax, filenames) | Unknown | No | No | No |

**Key insight:** No existing competitor offers a dedicated AI correction mode with natural language "fix this text" commands. Wispr Flow's "backtrack" only handles immediate corrections (undo last utterance). This is VoiceType's clear differentiator.

## Sources

- **Wispr Flow product page** (https://wisprflow.ai, https://wisprflow.ai/features): Feature list including AI Auto Edits, personal dictionary, snippet library, backtrack, auto punctuation, filler removal, styles, 100+ languages, developer syntax awareness. Primary source for competitor feature set. Confidence: HIGH (official product page).
- **Superwhisper product page** (https://superwhisper.com): AI voice-to-text, system-wide integration, polish mode. Confidence: MEDIUM (official page but truncated fetch).
- **MacWhisper product page** (https://macwhisper.com): Local Whisper transcription, dictation mode, speaker recognition, AI summaries, custom prompts, batch processing, meeting recording. Primary source for transcription-focused competitor. Confidence: HIGH (official product page).
- **whisper.cpp GitHub** (https://github.com/ggml-org/whisper.cpp): Model sizes, Core ML support, VAD integration, streaming capabilities, quantization options. Primary source for technical constraints. Confidence: HIGH (official repository).
- **silero-vad GitHub** (https://github.com/snakers4/silero-vad): Performance (<1ms per chunk), model size (~2MB), accuracy, supported sample rates (8kHz/16kHz), MIT license. Primary source for VAD capabilities. Confidence: HIGH (official repository).

---
*Feature research for: VoiceType — macOS voice dictation with AI-powered correction*
*Researched: 2026-07-30*
