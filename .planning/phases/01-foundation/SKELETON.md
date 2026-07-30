# Walking Skeleton — VoiceType

**Phase:** 1
**Generated:** 2026-07-30

## Capability Proven End-to-End

用户启动 VoiceType → 1 秒内看到菜单栏图标（绿色/橙色/红色反映权限状态）→ 菜单栏可打开设置窗口，输入并安全存储 API 密钥至 Keychain → Fn 热键在任意应用中可被检测（系统级 CGEvent tap）→ 麦克风音频可采集为 16kHz mono Float32 PCM。

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Swift 6.x + SwiftUI (macOS 14+) | 原生 macOS 集成——MenuBarExtra 场景、CGEvent、AVAudioEngine、AXUIElement 全为 Apple 原生 API。SwiftUI 声明式 UI + AppKit 选择性桥接用于系统级 API。 |
| UI Architecture | MenuBarExtra 场景（主入口）+ Settings 场景（独立设置窗口） | 菜单栏应用标准模式——无 Dock 图标，无 WindowGroup。纯后台 utility 应用，仅菜单栏可访问。 |
| State Management | @MainActor AppCoordinator（ObservableObject）——中央状态机 | 所有子系统通过 Coordinator 通信，子系统之间零直接依赖。单向数据流：子系统 → Notification/回调 → Coordinator → @Published → SwiftUI 视图。 |
| Hotkey System | CGEvent.tapCreate（`.cgSessionEventTap`）在专用 RunLoop 线程 | 现代 API（非 Carbon），支持 key-down 和 key-up 双事件（push-to-talk 必须）。专用线程避免阻塞主线程 UI。 |
| Audio Capture | AVAudioEngine input tap → 格式转换器 → RingBuffer（os_unfair_lock） | Apple 原生低延迟音频框架。格式转换器自动处理硬件采样率不匹配。RingBuffer 单生产者单消费者模式，os_unfair_lock 避免实时线程阻塞。 |
| Secret Storage | macOS Keychain（SecItem API）——`kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock` | 硬件加密保护。UserDefaults 明文存储不安全。`AfterFirstUnlock` 允许后台访问无需用户交互。 |
| Data layer | 无持久数据库——设置使用 @AppStorage（UserDefaults），密钥使用 Keychain | Phase 1 无复杂数据需求。Phase 2+ 如需模型管理/历史记录再引入。 |
| Auth | 无用户认证——仅 API 密钥用于服务到服务调用（GPT-4o/Claude） | VoiceType 为单用户本地工具，无多用户/登录需求。API 密钥属于用户自有 OpenAI/Anthropic 账户。 |
| Deployment target | macOS 14.0（Sonoma）+ .dmg 直接分发 | WhisperKit 要求 macOS 14.0+。v1 不计划上架 App Store（辅助功能权限应用审核不确定性大）。Xcode 17+ 构建，Swift 6 语言模式。 |
| Test strategy | 编译验证（xcodebuild build）+ 人工端到端验证（end-of-phase） | Phase 1 主要是系统 API 集成（CGEvent、AVAudioEngine、Keychain）——单元测试对这些 API 价值有限（需要 mock 大量系统态）。编译 + 人工 E2E 更适合此阶段。 |
| Directory layout | 按子系统分文件夹（App/, Hotkeys/, Audio/, Settings/, Utilities/） | 每个文件夹对应架构图中的组件边界。组件间零直接引用——所有通信通过 AppCoordinator。为 Phase 2-3 的独立扩展和测试建立模式。 |

## Stack Touched in Phase 1

- [x] Project scaffold — Xcode 17+ macOS App 项目，SPM 依赖（WhisperKit, MacPaw/OpenAI, swift-log），Swift 6，macOS 14.0 deployment target
- [x] Routing — MenuBarExtra 场景（应用主入口）+ Settings 场景（设置窗口）
- [ ] Database — Phase 1 无数据库需求（deferred）
- [x] UI — MenuBarView（状态+快捷操作）, PermissionGateView（顺序权限引导）, SettingsView（API 密钥配置）
- [ ] Deployment — Phase 1 仅本地 Xcode build 运行（deferred to later phase）
- [x] Secret storage — macOS Keychain（SecItem API）——1 real write（保存 API 密钥）+ 1 real read（脱敏显示）
- [x] System input — CGEvent tap（全局热键检测）——1 real input path
- [x] Audio pipeline — AVAudioEngine input tap → RingBuffer——1 real capture path

## Out of Scope (Deferred to Later Slices)

- 语音转文字（WhisperKit 模型加载与推理）—— Phase 2
- 语音活动检测（VAD）—— Phase 2
- 文字插入到任意应用（AXUIElement + 剪贴板回退）—— Phase 2
- AI 纠错（GPT-4o/Claude API 调用）—— Phase 3
- 可视化纠错预览（diff preview + accept/reject）—— Phase 3
- 撤销操作—— Phase 3
- 自定义热键—— v2（CONF-01）
- Whisper 模型选择（tiny/base/medium/large）—— v2（CONF-02）
- Windows 平台支持—— v2（WIN-01）
- App Store 分发—— 待研究（辅助功能权限审核政策不确定）

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- **Phase 2: Core Dictation** — 在 Phase 1 的 AppCoordinator 热键回调中接入 WhisperKit 转写+VAD，实现"按住 Fn 说话→松手出字"的完整听写循环。菜单栏图标新增 recording/transcribing 状态。
- **Phase 3: AI Correction** — 在 Phase 2 听写基础上叠加 AI 纠错通道：Ctrl+Shift+C 触发→读取光标上下文→录音转指令→LLM 纠错→原地替换文字。设置窗口中的 API 密钥开始实际使用。
