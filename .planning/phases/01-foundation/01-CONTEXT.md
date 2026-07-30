# Phase 1: Foundation - Context

**Gathered:** 2026-07-30
**Status:** Ready for planning

## Phase Boundary

搭建 VoiceType 的应用外壳与输入基础设施：菜单栏图标、启动权限流程、全局热键系统、音频采集管线。此阶段完成后，应用可启动、可授权、可检测热键、可采集音频——但不做任何语音识别或文字输入。

## Implementation Decisions

### 菜单栏交互

- **D-01:** 使用 SwiftUI `MenuBarExtra` 场景作为主入口，包含状态显示 + 偏好设置入口
- **D-02:** 独立设置窗口使用 SwiftUI `Settings` 场景，包含 API 密钥配置、热键显示、模型信息

### 热键

- **D-03:** 听写热键默认 Fn 键（hold-to-talk 模式）
- **D-04:** 纠错热键默认 Ctrl+Shift+C（press-to-trigger 模式）
- **D-05:** 热键注册使用 CGEvent.tapCreate（非 Carbon RegisterEventHotKey），需要 key-down 和 key-up 双事件
- **D-06:** 运行时检测权限丢失并提醒用户（watchdog: N 秒无事件 → 警告）

### 权限引导

- **D-07:** 首次启动分步引导：先请求麦克风权限，说明用途（"VoiceType 需要用麦克风将你说的转化成文字"），用户授予后 → 再请求辅助功能权限，说明用途（"需要辅助功能权限才能将文字输入到你正在用的应用中"）
- **D-08:** 权限状态始终在菜单栏图标上可见（绿色 = 全部就绪，橙色 = 缺一个，红色 = 全缺）

### 音频采集

- **D-09:** AVAudioEngine 作为音频采集框架，tap input node 获取 16kHz mono Float32 PCM
- **D-10:** 监听音频设备热插拔（AirPods 断开、USB 麦插入），自动切换输入设备

### 项目结构

- **D-11:** 按子系统分文件夹组织源码：
  - `App/` — @main entry, MenuBarExtra, Settings
  - `Hotkeys/` — CGEvent tap 封装
  - `Audio/` — AVAudioEngine 封装
  - `Settings/` — UserDefaults + Keychain wrapper
  - `Utilities/` — OSLog 封装、权限状态检查

### 密钥安全

- **D-12:** API 密钥存储使用 macOS Keychain（SecItem API），禁止存 UserDefaults 或 plist 明文

### Agent 的裁量空间

- 具体的 SwiftUI 视图层级和样式（在满足 MenuBarExtra + Settings window 前提下）
- OSLog 子系统和类别命名
- UserDefaults key 命名规范
- CGEvent tap 的具体创建参数（.cgSessionEventTap, .headInsertEventTap 选择）

## Canonical References

### 项目上下文
- `.planning/PROJECT.md` — 项目定义、核心价值、约束
- `.planning/REQUIREMENTS.md` § SHEL, § HOTK, § AUDI — Phase 1 覆盖的 10 项需求
- `.planning/ROADMAP.md` § Phase 1 — 阶段目标和成功标准
- `.planning/config.json` — 工作流配置（coarse 粒度、并行执行、adaptive 模型）

### 技术研究
- `.planning/research/STACK.md` — 技术栈推荐（Swift/SwiftUI、CGEvent、AVAudioEngine、Keychain）
- `.planning/research/ARCHITECTURE.md` § 2-3 — HotkeyManager 和 AudioCapture 组件设计
- `.planning/research/PITFALLS.md` § 4, § 7, § 10 — 热键权限丢失、主线程阻塞、音频设备热插拔陷阱

### 外部参考
- `README.md` — 用户视角的产品描述和热键预设

## Existing Code Insights

### Reusable Assets
- (None — greenfield project, this is the first phase)

### Established Patterns
- (None yet — Phase 1 establishes foundation patterns)

### Integration Points
- 后续 Phase 2 依赖此阶段产出的: HotkeyManager（供听写/纠错使用）、AudioCapture（供 VAD 和 WhisperKit 使用）、权限状态（供录制指示器和错误恢复使用）、Keychain wrapper（供 API 密钥读取使用）

## Specific Ideas

- README.md 中已暗示：听写热键 = Fn，纠错热键 = Ctrl+Shift+C，作为默认值
- 菜单栏图标应实时反映应用状态（空闲/录音中/转写中/纠错中），为后续阶段预留状态枚举

## Deferred Ideas

None — discussion stayed within phase scope

---

*Phase: 1-Foundation*
*Context gathered: 2026-07-30*
