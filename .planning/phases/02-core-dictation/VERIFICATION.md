---
phase: 02-core-dictation
verified: 2026-07-31T12:37:20Z
status: gaps_found
score: 13/16 must-haves verified
behavior_unverified: 1 # ⚠️ PRESENT_BEHAVIOR_UNVERIFIED truths (present + wired, behavior not exercised)
overrides_applied: 0
gaps:
  - truth: "转录自动检测中英文（D-14）——实现强制 language: 'zh'，未启用 detectLanguage"
    status: failed
    reason: "TranscriptionService.swift 第 60 行硬编码 language: 'zh'（提交 5a01780 'force zh language'），替代了计划的 detectLanguage: true。简体中文识别质量提升（避免繁体/粤语），但英文听写路径未实现且未验证，UXFE-03 与 SC5 的双语承诺无法兑现"
    artifacts:
      - path: "VoiceType/Transcription/TranscriptionService.swift"
        issue: "DecodingOptions 使用 language: 'zh' 强制中文，无 detectLanguage 自动检测"
    missing:
      - "启用 detectLanguage: true（或提供语言设置项），英文听写实测验证"
  - truth: "中英文双语 WER 低于 15%（SC5 / DICT-08）"
    status: failed
    reason: "无任何 WER 基准测量证据（无基准脚本、无测试数据）；模型从计划的 large-v3 降级为 base（142MB）；英文路径因强制 zh 未验证。中文听写经真实用户测试可用，但 <15% WER 数值无从证实"
    artifacts:
      - path: "VoiceType/Transcription/ModelDownloadManager.swift"
        issue: "devModelName = 'openai_whisper-base'，计划与 D-01 预期为 tiny（开发）/ large-v3（生产）"
    missing:
      - "中英文各 20-30 句的 WER 实测（或基准脚本）；若英文暂不支持，需在产品文档中声明单语范围"
  - truth: "VAD 自动检测用户停止说话，无需手动释放（DICT-02）"
    status: partial
    reason: "仅实现热键释放即转录（D-07）；'静默 N 秒自动停止'（D-06）未实现。chunkingStrategy: .vad 仅用于推理时切分，不提供按住说话时的自动停止。REQUIREMENTS.md 已将 DICT-02 标记为 Pending（有文档记录的未完成项），但无后续阶段承接"
    artifacts:
      - path: "VoiceType/AppCoordinator.swift"
        issue: "onDictationKeyUp 是唯一转录触发路径，无 VAD 静默超时自动停止"
    missing:
      - "按住期间 VAD 静默超时自动停止（D-06），或正式将 DICT-02 移出 v1 范围并同步需求文档"
behavior_unverified_items:
  - truth: "VAD 分块（chunkingStrategy: .vad）在真实推理中正确切分语音/静默，产出准确分段"
    test: "在真实麦克风环境按住热键说一句带停顿的话，检查转录分段是否贴合语音边界"
    expected: "VAD 将停顿切为多个分段，每段文字完整无截断、无重复"
    why_human: "代码已设置 chunkingStrategy: .vad（存在且已接线），但单元测试无法运行真实 Core ML 推理；分块质量只有真实语音输入才能观测"
---

# Phase 2: Core Dictation 验证报告

**阶段目标（来自 ROADMAP.md）：** 用户按住听写热键说话，松手后语音自动转为带标点的文字并输入到任意应用的光标位置
**验证时间：** 2026-07-31T12:37:20Z
**状态：** gaps_found（核心目标达成，双语与 VAD 自动停止两项契约未兑现）
**重新验证：** 否（首次验证）

## 目标达成情况

### 核心结论

阶段目标本身（按住 Fn 说话 → 松手 → 带标点文字出现在光标处）**已实现并经真实用户测试验证**（任务上下文确认：Fn 按住说话→转录→光标处插入文字可用；模型从本地缓存离线加载；简体中文转换正常；AXUIElement 主策略 + 剪贴板回退均工作）。`swift build` 通过，39 个测试全部通过。

但 5 条成功标准中有 2 条未完全兑现：**双语自动检测**（实现强制中文，D-14 决策偏离）与 **WER < 15% 测量**（无基准数据）；11 项需求中 **DICT-02（VAD 自动停止）** 未实现（REQUIREMENTS.md 已如实标记 Pending）。

### 可观测真相

| # | 真相 | 状态 | 证据 |
|---|------|------|------|
| 1 | 模型加载（本地优先离线加载）并缓存 pipe 复用（D-01~D-03） | ✓ VERIFIED | `ModelDownloadManager.initialize()` 先查本地 `config.json` 再决定 `download: false/true`；`private var pipe` 缓存 + `getPipe()` 复用；本地缓存实测存在（base 154MB + tiny 74MB，含 5 个 Core ML 文件与 tokenizer 全套） |
| 2 | transcribe(Float32) 返回带标点文字，离线本地推理（DICT-03/04） | ✓ VERIFIED | `TranscriptionService.transcribe(audioArray:)` 经 WhisperKit pipe 推理（`task: .transcribe`），join 分段文本 |
| 3 | 自动检测中英文 + 填充词过滤（D-14, DICT-05） | ✗ FAILED | `language: "zh"` 硬编码（TranscriptionService.swift:60），无 detectLanguage；填充词正则（呃/嗯/那个/就是/um/uh/you know）已实现并有 5 个单元测试 |
| 4 | VAD 分块切分语音/静默（DICT-02, D-05） | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | `chunkingStrategy: .vad` 已设置（存在且接线），但无测试执行真实推理，分块质量未验证；DICT-02 的"自动停止"需求本身未实现（见 Gaps） |
| 5 | 模型加载不阻塞主线程（D-04） | ✓ VERIFIED | 全部 WhisperKit 操作在 `Task.detached(priority: .userInitiated)`，菜单栏即时渲染（Phase 1 已验证） |
| 6 | @Published modelState 供 UI 驱动（D-17 就绪） | ✓ VERIFIED | `ModelDownloadManager.modelState` + AppCoordinator 经 Combine `assign(to: &$modelState)` 镜像 |
| 7 | AXUIElement 主策略在原生 AppKit 应用光标处插入文字（D-08, DICT-06） | ✓ VERIFIED | `AccessibilityBridge.insertText` 用 `kAXSelectedTextAttribute` 写入；真实用户测试确认可用 |
| 8 | AX 失败时剪贴板回退：保存→写入→Cmd+V→恢复（D-09, D-19） | ✓ VERIFIED | `CompositeTextIO` 回退链 + `ClipboardBridge` 六步周期（100ms 写入/200ms 粘贴延迟）；真实用户测试确认回退工作 |
| 9 | 密码字段检测并跳过（D-10） | ✓ VERIFIED | 组合层先查 `isPasswordField()`（"AXIsPasswordField" 属性）再写入；有单元测试覆盖 |
| 10 | 原始剪贴板内容保留（PITFALLS §5） | ✓ VERIFIED | 保存→恢复周期 + 失败时抛 `clipboardRestoreFailed`（宁可留空不残留听写文本）；恢复行为需真实应用验证（见人工项 3） |
| 11 | HUD"🎤 录音中…/📝 转录中…"并自动消失（D-11/12） | ✓ VERIFIED | `HUDOverlayView` 状态派生消息；`HUDWindowController` show/hide 生命周期，成功/失败均 hide |
| 12 | 完整管线：Fn-down→录音→Fn-up→读缓冲→stop→转录→插入→HUD 隐藏（DICT-01） | ✓ VERIFIED | `AppCoordinator.setupHotkeyCallbacks()` 全管线接线；**read-before-stop 顺序正确**（先 `buffer.read()` 后 `audioCapture.stop()`，修复了 02-CHECK.md 的 BLOCKER）；`isDictating` 竞态守卫 |
| 13 | 菜单栏图标随状态切换（UXFE-01, D-13） | ✓ VERIFIED | `VoiceTypeApp.swift` `MenuBarExtra(systemImage: coordinator.iconName)` 动态图标；mic.fill → mic.fill.badge.ellipsis → arrow.triangle.2.circlepath |
| 14 | 错误状态显示中文提示与恢复指引（UXFE-02） | ✓ VERIFIED | 模型未就绪（"语音模型未就绪——请在启动后等待模型加载完成"）、麦克风不可用、转录失败、输入失败、热键权限丢失（Phase 1）均有中文消息 + 5 秒自动复位 |
| 15 | 300ms 最短音频时长强制（PITFALLS §2） | ✓ VERIFIED | 双重守卫：AppCoordinator 管线（`minSamples = sampleRate * 0.3`）+ TranscriptionService |
| 16 | 中英文双语听写 WER < 15%（SC5） | ✗ FAILED | 无 WER 测量；模型为 base 而非计划的 large-v3；英文路径因强制 zh 未验证 |

**得分：** 13/16 真相已验证（2 失败，1 行为未验证）

### 成功标准（ROADMAP 契约）

| # | 成功标准 | 状态 | 证据 |
|---|----------|------|------|
| 1 | 按住听写热键说话、松手，转录文字（含标点和大写）出现在光标位置 | ✓ 达成 | 全管线接线正确（读缓冲先于 stop），真实用户测试确认端到端可用 |
| 2 | 听写完全离线可用 | ✓ 达成 | 本地缓存优先加载路径（`download: false`），模型文件实测在本地；联网仅首次下载需要（hf-mirror 镜像） |
| 3 | 菜单栏图标实时反映状态（空闲/录音中/转录中/插入文字） | ✓ 达成 | 动态 iconName 驱动；HUD 补充录音/转录提示；"插入文字"阶段由 HUD 消失 + 就绪图标体现 |
| 4 | 错误时显示具体原因与修复指引 | ✓ 达成 | 四类错误路径均有中文消息与恢复动作（等待模型/检查麦克风/重试/检查权限） |
| 5 | 中英文双语听写，WER < 15% | ✗ 未达成 | 强制 zh 使英文路径未实现；无 WER 基准测量（见 Gaps #2） |

### 需求覆盖

| 需求 | 状态 | 证据 |
|------|------|------|
| DICT-01 按住说话松手出字 | ✓ SATISFIED | 管线完整 + 真实测试验证 |
| DICT-02 VAD 自动检测停止 | ✗ BLOCKED | 仅热键释放触发；REQUIREMENTS.md 已标 Pending（见 Gaps #3） |
| DICT-03 离线听写 | ✓ SATISFIED | 本地缓存加载路径 + 模型文件在盘 |
| DICT-04 自动标点与大小写 | ✓ SATISFIED | Whisper transcribe 任务原生输出 |
| DICT-05 填充词去除 | ✓ SATISFIED | 正则后处理 + 单元测试 |
| DICT-06 AX + 剪贴板回退跨应用插入 | ✓ SATISFIED | 双策略 + 组合回退链 + 真实测试 |
| DICT-07 录音可视化指示 | ✓ SATISFIED | HUD + 菜单栏图标 |
| DICT-08 WER < 10-15% | ? NEEDS HUMAN | 无测量数据；base 模型中文实测可用但未量化 |
| UXFE-01 菜单栏状态实时反馈 | ✓ SATISFIED | 动态图标 + 状态消息 |
| UXFE-02 错误状态 + 恢复指引 | ✓ SATISFIED | 中文错误消息 + 自动复位 |
| UXFE-03 中英双语开箱即用 | ? NEEDS HUMAN | 中文可用（真实测试）；英文因强制 zh 未验证 |

**孤儿需求：** 无——11 项需求全部由 3 个 PLAN 承接（与 02-CHECK.md 一致）。

### CONTEXT.md 决策合规（D-01~D-19）

| 决策 | 状态 | 说明 |
|------|------|------|
| D-01 tiny 开发 / large-v3 生产 | ⚠️ 偏离 | 默认模型为 `openai_whisper-base`（代码注释说明：tiny 中文差、base 是准确率/速度平衡点）；`modelName` 参数保留两条路径。计划本身已先行偏离（默认 large-v3），最终实现再降为 base。合理但需文档化 |
| D-02 异步下载 + 进度 | ⚠️ 部分 | 状态文字"正在准备语音模型…"有展示；`downloading(progress:)` 分支从未发射（WhisperKit 内部下载未接进度回调）。"进度条**或**状态文字"口径下可接受 |
| D-03 内存缓存 pipe | ✓ | `private var pipe` + `getPipe()` |
| D-04 后台线程不阻塞 | ✓ | `Task.detached(priority: .userInitiated)` |
| D-05 内置 VAD | ✓ | `chunkingStrategy: .vad` |
| D-06 VAD 静默自动停止 | ✗ 未实现 | 仅 D-07 路径（松手即转录） |
| D-07 松手立即转录 | ✓ | Fn up → read → stop → transcribe |
| D-08 AXUIElement 主策略 | ✓ | `kAXSelectedTextAttribute` 写入 |
| D-09 剪贴板回退 | ✓ | 保存→写入→Cmd+V→恢复（100/200ms） |
| D-10 密码字段跳过 | ✓ | 组合层守护 + AX 属性检测 |
| D-11 HUD 录音提示 | ✓ | "🎤 录音中…" |
| D-12 转录完成 HUD 自动消失 | ✓ | 成功/失败均 hide |
| D-13 菜单栏图标随状态切换 | ✓ | 三态图标切换 |
| D-14 中英双语自动检测 | ✗ 偏离 | 强制 `language: "zh"`（提交 5a01780），未用 detectLanguage。为简体准确率牺牲了英文路径（见 Gaps #1） |
| D-15 Whisper 内置标点 | ✓ | transcribe 任务原生标点 |
| D-16 填充词去除 | ✓ | 正则后过滤（保守：不滤 like） |
| D-17 模型未就绪给提示 | ✓ | 录音前模型守卫 + 中文错误 |
| D-18 麦克风不可用给提示 | ✓ | start() 失败 → "麦克风不可用: …" |
| D-19 AX 失败自动回退 | ✓ | CompositeTextIO 回退链 |

**18/19 项决策落实或可接受偏离；D-14 为实质性偏离，D-06 未实现。**

### 关键链路验证

| 起点 | 终点 | 经由 | 状态 |
|------|------|------|------|
| HotkeyManager.handleFn (Fn flagsChanged) | AudioCaptureService.start() | AppCoordinator.onDictationKeyDown（主线程分发） | ✓ WIRED |
| RingBuffer.read() | stop() | AppCoordinator.onDictationKeyUp 顺序：**先读后停**（CHECK.md BLOCKER 已修复） | ✓ WIRED |
| TranscriptionService | WhisperKit pipe | `pipe.transcribe(audioArray:decodeOptions:)`（模式匹配确认） | ✓ WIRED |
| DecodingOptions | VAD | `chunkingStrategy: .vad` | ✓ WIRED |
| CompositeTextIO | AccessibilityBridge → ClipboardBridge | 密码守护 → AX → 剪贴板回退 | ✓ WIRED |
| AppCoordinator.modelState | MenuBarView.statusMessage | Combine `$modelState.sink` | ✓ WIRED |
| coordinator.iconName | MenuBarExtra 图标 | `systemImage: coordinator.iconName` | ✓ WIRED |
| HUDWindowController | AppCoordinator.state | @ObservedObject + show()/hide() | ✓ WIRED |

### 数据流追踪（Level 4）

| 组件 | 数据变量 | 数据源 | 真实数据 | 状态 |
|------|----------|--------|----------|------|
| TranscriptionService | audioArray | AudioCaptureService RingBuffer（真实 AVAudioEngine tap → 16kHz Float32） | ✓ | ✓ FLOWING |
| 模型 | pipe | 本地缓存（config.json + 5 个 .mlmodelc + tokenizer）或 hf-mirror 下载 | ✓ | ✓ FLOWING |
| TextIO.insertText | text | transcribe 返回值（非硬编码） | ✓ | ✓ FLOWING |
| 剪贴板回退 | NSPasteboard | 保存→写入→恢复 真实周期 | ✓ | ✓ FLOWING |

### 行为抽查（Step 7b）

| 行为 | 命令 | 结果 | 状态 |
|------|------|------|------|
| 项目可编译 | `swift build` | Build complete! 0 错误 | ✓ PASS |
| 测试套件全绿 | `swift test` | 39 tests in 7 suites passed | ✓ PASS |
| 填充词过滤 | 单元测试（removeFillerWords × 5） | 5/5 通过（中英填充词 + 空白规整） | ✓ PASS |
| 回退链逻辑 | 单元测试（CompositeTextIO × 6） | 6/6 通过（主路径/回退/全失败/密码守护） | ✓ PASS |
| 错误守卫 | 单元测试（transcribe 无模型/过短音频） | 通过（modelNotDownloaded / audioTooShort） | ✓ PASS |
| 离线模型缓存 | `du -sh ~/Documents/huggingface/...` | base 154MB + tiny 74MB，含 tokenizer 全套 | ✓ PASS |

### 探针执行（Step 7c）

本阶段 PLAN 的 verify 命令均为 `swift build`，未声明探针脚本。`scripts/download-model.sh` 为运维辅助脚本（hf-mirror 模型下载），非验收探针——已检查其存在与内容（tokenizer 全套文件已含 2026-07-31 的修复提交）。

### 反模式扫描

| 文件 | 行 | 模式 | 严重度 | 说明 |
|------|----|------|--------|------|
| VoiceType/AppCoordinator.swift | 341 | 过时注释 | ℹ️ | 注释写 "CORRECTION: Ctrl+Shift+C"，实际热键已改为 ⌥+回车（提交 5c63125，规避输入法冲突）——仅注释过期，无功能影响 |
| .planning/REQUIREMENTS.md | 追踪表 | 状态滞后 | ℹ️ | DICT-03/04/05/08、UXFE-03 复选框为 [x] 但追踪表仍标 Pending——需求文档内部不一致，建议同步 |

**无 TBD/FIXME/XXX 标记；无空实现、无硬编码空数据、无 console.log 占位。**

### 人工验证清单

**1. 英文听写实测（对应 Gaps #1）**

**操作：** 按住听写热键说一句英文（如 "Hello, how are you today?"）
**预期：** 转录出正确英文文本；若强制 zh 导致英文输出乱码/中文化，则确认英文路径当前不可用
**为何需人工：** 强制 `language: "zh"` 对英文语音的实测影响只有真实麦克风 + 真实模型推理才能观测

**2. WER 基准测量（对应 Gaps #2）**

**操作：** 中英文各 20-30 句标准句子，逐句听写并人工统计词错率
**预期：** 中英文 WER 均 < 15%
**为何需人工：** 无基准脚本可程序化验证；<15% 是数值契约，只能人工实测

**3. 剪贴板回退恢复验证**

**操作：** 先复制一段文字，在 AX 不生效的应用（如某些终端或 Electron 应用）中听写
**预期：** 文字粘贴成功，且事后剪贴板内容仍是预先复制的那段文字
**为何需人工：** 保存→恢复周期依赖真实 NSPasteboard 与窗口服务器时序

**4. HUD 视觉与跨空间显示**

**操作：** 在双显示器/多桌面环境下听写，观察 HUD 位置、透明度、跨 Space 可见性
**预期：** HUD 居中偏上、半透明、录音与转录消息正确切换、完成后消失
**为何需人工：** 窗口层级与视觉效果无法 grep 验证

**5. 菜单栏图标实时切换**

**操作：** 听写全程观察菜单栏图标
**预期：** 空闲（mic.fill）→ 录音（mic.fill.badge.ellipsis）→ 转录（arrow.triangle.2.circlepath）→ 就绪
**为何需人工：** 系统托盘渲染需运行时观察

### 差距总结

**核心目标已达成**，但验证发现 2 项契约未兑现 + 1 项需求未实现：

1. **双语自动检测缺失（D-14/UXFE-03/SC5 部分）**——实现为提升简体中文准确率强制 `language: "zh"`（提交 5a01780），放弃了 detectLanguage 自动检测。若英文听写是 v1 承诺，需改回自动检测或提供语言选项；若接受单语 v1，建议在 VERIFICATION.md 增加 override 正式记录该决策。**建议行动：真实麦克风英文实测一次，再决定改代码或接受单语。**
2. **WER < 15% 无测量证据（DICT-08/SC5）**——计划模型为 large-v3，实际为 base（142MB）；无任何基准数据支撑 SC5 数值。中文实测可用，但"<15%"无法证实。**建议行动：中英文各 20 句实测，记录 WER 数据；或把 SC5 改为可验证的中文 WER 条款。**
3. **DICT-02（VAD 自动停止）未实现**——仅热键释放触发转录（D-07），按住时无"静默 N 秒自动停止"。REQUIREMENTS.md 已如实标记 Pending，但无后续阶段承接（Phase 3 为 AI 纠错）。**建议行动：正式将 DICT-02 移出 v1 范围并更新需求文档，或在 Phase 3 后追加小任务。** 注意：阶段目标（松手出字）本身不依赖此项，此差距不阻塞核心听写功能。

**关于 02-CHECK.md 的 BLOCKER：** 已确认在实现中修复——`AppCoordinator.swift` 第 250-258 行先 `buffer.read(count:)` 后 `audioCapture.stop()`（`RingBuffer.read` 为非消费性读取，`stop()` 才 reset）。转录管线不会拿到空音频。

---

_验证时间：2026-07-31T12:37:20Z_
_验证者：gsd-verifier（目标回溯式验证：代码证据为准，SUMMARY 声明仅作参考）_
