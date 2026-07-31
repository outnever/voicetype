# Phase 2: Core Dictation - Context

**Gathered:** 2026-07-31
**Status:** Ready for planning

## Phase Boundary

用户按住 ⌥+空格 说话，松手后语音自动转录为带标点的文字，通过 AXUIElement 输入到任意应用的光标位置。这是 VoiceType 第一个可用的功能——离线语音输入。

## Implementation Decisions

### WhisperKit 模型

- **D-01:** 默认使用 `tiny` 模型开发迭代，生产使用 `large-v3-v20240930_626MB`
- **D-02:** 首次启动时异步下载模型（WhisperKit 内置下载器），显示进度条或状态文字
- **D-03:** 模型加载后缓存在内存中，不重复加载每次听写
- **D-04:** 模型下载/加载在后台线程执行，不阻塞菜单栏 UI（延续 Phase 1 的 SHEL-01 原则）

### VAD（语音活动检测）

- **D-05:** 使用 WhisperKit 内置 VAD（基于 silero-vad），`chunkingStrategy: .vad`
- **D-06:** 听写流程：按住热键开始录音 → VAD 检测到静默 × N 秒 → 自动停止录音 → 转录
- **D-07:** 同时支持手动释放热键立即转录（热键释放优先于 VAD 超时）

### 文字输入

- **D-08:** 主策略：AXUIElement 写入光标位置（`AXUIElementSetAttributeValue`）
- **D-09:** 回退策略：剪贴板粘贴（保存→写入转录文本→模拟 Cmd+V→恢复原剪贴板内容）
- **D-10:** 输入前检查：跳过密码字段（`kAXIsPasswordFieldAttribute`），不在安全输入区域操作

### 录音反馈

- **D-11:** 按住热键时显示 macOS 系统级 HUD 提示（半透明覆盖层），显示"🎤 录音中…"
- **D-12:** 转录完成后 HUD 自动消失，文字出现在光标处
- **D-13:** 菜单栏图标在录音时切换颜色/动画（复用 Phase 1 的 AppState 状态机制）

### 语言与标点

- **D-14:** 中英双语自动检测（Whisper large-v3 原生支持 99 种语言）
- **D-15:** 利用 Whisper 内置标点能力，不额外做标点后处理
- **D-16:** 去除填充词（"呃"、"嗯"、"um"、"uh"）——Whisper 天然过滤部分，剩余靠简单正则

### 错误处理

- **D-17:** 模型未下载时显示提示而非崩溃
- **D-18:** 音频设备不可用时提示用户检查麦克风
- **D-19:** AXUIElement 写入失败时自动回退到剪贴板策略，不报错

### Agent 的裁量空间

- WhisperKit 的具体 API 调用方式（v0.9.0+）
- VAD 静默阈值秒数（建议 1-2 秒）
- HUD 覆盖层的具体 UI 样式和动画
- 剪贴板回退的具体延迟时间（VAD/转录接口）
- 正则模式的精确写法
- TranscriptionService 与 AppCoordinator 的集成方式（复用 Phase 1 的 coordinator 回调模式）

## Canonical References

### 项目上下文
- `.planning/PROJECT.md` — 项目定义、核心价值
- `.planning/REQUIREMENTS.md` § DICT、§ UXFE — Phase 2 覆盖的 11 项需求
- `.planning/ROADMAP.md` § Phase 2 — 阶段目标和成功标准
- `.planning/phases/01-foundation/01-CONTEXT.md` — Phase 1 决策和组件接口

### 技术研究
- `.planning/research/STACK.md` — WhisperKit 0.9.0+, WhisperKit VAD, AXUIElement
- `.planning/research/ARCHITECTURE.md` § TranscriptionService, TextIO — 组件设计
- `.planning/research/PITFALLS.md` § 1 (AXUIElement 脆弱性)、§ 2 (Whisper 幻觉)、§ 5 (剪贴板破坏)

### Phase 1 产物
- `VoiceType/Audio/AudioCaptureService.swift` — AVAudioEngine 音频采集管线（16kHz mono PCM + RingBuffer）
- `VoiceType/Audio/AudioBuffer.swift` — 线程安全环形缓冲区
- `VoiceType/AppCoordinator.swift` — 中央状态机，已有 onDictationKeyDown/Up 回调钩子
- `VoiceType/Hotkeys/HotkeyManager.swift` — CGEvent 热键管理器

## Existing Code Insights

### Reusable Assets
- **AudioCaptureService** — 已有 `start()`/`stop()` 方法和 RingBuffer。Phase 2 在热键按下时调用 `start()`、释放时读取 RingBuffer 内容喂给 WhisperKit
- **AppCoordinator** — 已有 `onDictationKeyDown`/`onDictationKeyUp` 回调钩子和 `.recording` / `.idle` 状态。Phase 2 在回调中插入音频控制和转录逻辑
- **AppState** — 已有 `idle` / `recording` / `transcribing` / `correcting` 枚举。Phase 2 新增实际转录流程驱动

### Established Patterns
- 所有子系统通过 AppCoordinator 通信，不直接相互引用
- 异步初始化在 `Task.detached` 中执行
- 菜单栏图标在 1 秒内渲染

### Integration Points
- Phase 2 新增 `TranscriptionService` 组件，通过 AppCoordinator 与 AudioCaptureService 和 TextIO 桥接
- Phase 3（纠错）将复用此阶段的 TextIO 写入能力

## Specific Ideas

(None — following research recommendations)

## Deferred Ideas

(None — discussion stayed within phase scope)

---

*Phase: 2-Core-Dictation*
*Context gathered: 2026-07-31*
