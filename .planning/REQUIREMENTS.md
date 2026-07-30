# Requirements: VoiceType

**Defined:** 2026-07-30
**Core Value:** 说错了不用摸键盘——再按一下热键，说句人话就能改回来。

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Application Shell & Permissions

- [x] **SHEL-01**: User sees menu bar icon on app launch within 1 second
- [x] **SHEL-02**: User is guided through first-run permission flows (microphone + accessibility)
- [x] **SHEL-03**: User can access settings window from menu bar to configure preferences
- [x] **SHEL-04**: API keys stored securely in macOS Keychain (never in UserDefaults or plaintext)

### Audio & Hotkeys

- [x] **HOTK-01**: User can hold dictation hotkey to start recording, release to stop (push-to-talk)
- [x] **HOTK-02**: User can press correction hotkey to enter correction mode (separate from dictation)
- [x] **HOTK-03**: Hotkeys work globally across all applications (system-level CGEvent tap)
- [x] **HOTK-04**: App detects and alerts user when hotkey permissions are lost (e.g. after OS update)
- [x] **AUDI-01**: App captures audio from default microphone at 16kHz mono
- [x] **AUDI-02**: App handles audio device hot-plug gracefully (AirPods disconnect, USB mic unplug)

### Core Dictation

- [ ] **DICT-01**: User can hold dictation hotkey, speak, release, and transcribed text appears at cursor in any application
- [ ] **DICT-02**: VAD (Voice Activity Detection) auto-detects when user stops speaking, no manual stop required
- [ ] **DICT-03**: Dictation works offline using local Whisper model (no internet required)
- [ ] **DICT-04**: Transcription output includes auto-punctuation and capitalization
- [ ] **DICT-05**: Filler words ("um", "uh", "you know") are removed from output
- [ ] **DICT-06**: Text insertion works across all target apps via AXUIElement with clipboard fallback
- [ ] **DICT-07**: User sees a visual recording indicator (menu bar icon / HUD) during dictation
- [ ] **DICT-08**: Basic word error rate (WER) below 10-15% for Chinese and English dictation

### AI Correction

- [ ] **CORR-01**: User presses correction hotkey, speaks natural language correction command, AI replaces wrong text in-place
- [ ] **CORR-02**: Correction commands are freeform natural language (e.g. "把窗间改成创建", "第三个参数改成 userId")
- [ ] **CORR-03**: AI reads surrounding text context (cursor-adjacent characters) to understand what to fix
- [ ] **CORR-04**: Correction result replaces text in-place without disturbing surrounding content
- [ ] **CORR-05**: Correction output is structured (JSON) and substring-validated before applying to prevent overwrites
- [ ] **CORR-06**: User can undo last correction operation
- [ ] **CORR-07**: Correction works with both GPT-4o and Claude API backends
- [ ] **CORR-08**: User sees a visual diff preview before correction is applied (accept/reject)

### UX & Feedback

- [ ] **UXFE-01**: User always sees current app state (idle / recording / transcribing / correcting) via menu bar icon
- [ ] **UXFE-02**: Error states (audio failure, model load failure, permission loss) are surfaced to user with recovery guidance
- [ ] **UXFE-03**: Bilingual Chinese + English dictation and correction supported out of the box

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Configuration & Personalization

- **CONF-01**: User can configure custom dictation and correction hotkeys
- **CONF-02**: Power users can select Whisper model size (tiny/base/small/medium/large) for speed/accuracy tradeoff
- **CONF-03**: User can set language preferences (Chinese-only, English-only, mixed)

### Advanced Features

- **SNIP-01**: User can define voice-triggered snippet expansions (e.g. say "calendar" to insert scheduling link)
- **PERS-01**: App learns personal dictionary of user-specific words, names, and jargon over time
- **STYL-01**: Correction adapts tone/formality based on context (email vs chat vs document)

### Platform Expansion

- **WIN-01**: Windows platform support
- **MOBI-01**: Mobile companion app (iOS/iPadOS)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| AI content generation (write emails/code from voice) | Different product category — VoiceType corrects existing text, doesn't generate new content |
| Voice commands for app control ("open Chrome", "scroll down") | Completely different technical domain (AppleScript / UI automation) |
| Real-time streaming transcription (words appear as you speak) | Whisper architecture is fundamentally non-streaming; segment-based processing is the correct approach |
| Meeting transcription / multi-speaker diarization | MacWhisper's domain; different use case |
| Video/audio file transcription and subtitling | Different product category, requires file management UI |
| Persistent audio recording storage | Privacy liability; VoiceType processes and discards audio |
| Cross-device sync (iPhone, iPad) | Premature infrastructure complexity for v1; macOS-only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SHEL-01 | Phase 1 | Complete |
| SHEL-02 | Phase 1 | Complete |
| SHEL-03 | Phase 1 | Complete |
| SHEL-04 | Phase 1 | Complete |
| HOTK-01 | Phase 1 | Complete |
| HOTK-02 | Phase 1 | Complete |
| HOTK-03 | Phase 1 | Complete |
| HOTK-04 | Phase 1 | Complete |
| AUDI-01 | Phase 1 | Complete |
| AUDI-02 | Phase 1 | Complete |
| DICT-01 | Phase 2 | Pending |
| DICT-02 | Phase 2 | Pending |
| DICT-03 | Phase 2 | Pending |
| DICT-04 | Phase 2 | Pending |
| DICT-05 | Phase 2 | Pending |
| DICT-06 | Phase 2 | Pending |
| DICT-07 | Phase 2 | Pending |
| DICT-08 | Phase 2 | Pending |
| CORR-01 | Phase 3 | Pending |
| CORR-02 | Phase 3 | Pending |
| CORR-03 | Phase 3 | Pending |
| CORR-04 | Phase 3 | Pending |
| CORR-05 | Phase 3 | Pending |
| CORR-06 | Phase 3 | Pending |
| CORR-07 | Phase 3 | Pending |
| CORR-08 | Phase 3 | Pending |
| UXFE-01 | Phase 2 | Pending |
| UXFE-02 | Phase 2 | Pending |
| UXFE-03 | Phase 2 | Pending |

**Coverage:**

- v1 requirements: 29 total
- Mapped to phases: 29
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-30*
*Last updated: 2026-07-30 after initial definition*
