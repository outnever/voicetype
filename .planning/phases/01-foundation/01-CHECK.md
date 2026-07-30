# Plan Check Report: Phase 1 — Foundation

**Verified:** 2026-07-30
**Gate type:** Revision Gate（修订门——产出品质审查）
**Status:** ⚠️ ISSUES FOUND — 1 blocker, 1 warning

---

## Executive Summary

对 Phase 1 的 3 份执行计划（01-01-PLAN.md, 01-02-PLAN.md, 01-03-PLAN.md）进行了目标逆向验证。计划结构完整、需求覆盖全面、12 项 CONTEXT.md 决策全部落实、架构分层合规、任务粒度合理、威胁模型到位。

**存在 1 个阻断项：** RESEARCH.md 的「## Open Questions」章节中 3 个问题均未标记为 RESOLVED。Plan Checker 要求所有研究问题在规划前完成解决。

---

## 1. Dimension 1: Requirement Coverage（需求覆盖）


| 需求 ID | 覆盖计划 | 覆盖任务 | 状态 |
|------------|----------|-----------|--------|
| SHEL-01 | 01-01 | Task 1, Task 2 | ✅ 已覆盖 |
| SHEL-02 | 01-01 | Task 2 | ✅ 已覆盖 |
| SHEL-03 | 01-01 | Task 3 | ✅ 已覆盖 |
| SHEL-04 | 01-01 | Task 3 | ✅ 已覆盖 |
| HOTK-01 | 01-02 | Task 1 | ✅ 已覆盖 |
| HOTK-02 | 01-02 | Task 1 | ✅ 已覆盖 |
| HOTK-03 | 01-02 | Task 1 | ✅ 已覆盖 |
| HOTK-04 | 01-02 | Task 2 | ✅ 已覆盖 |
| AUDI-01 | 01-03 | Task 1 | ✅ 已覆盖 |
| AUDI-02 | 01-03 | Task 2 | ✅ 已覆盖 |

**结果：** 10/10 需求已覆盖 ✅

---

## 2. Dimension 2: Task Completeness（任务完整性）


| 计划 | 任务 | Files | Action | Verify | Done | 状态 |
|------|------|-------|--------|--------|------|------|
| 01-01 | 1 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 01-01 | 2 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 01-01 | 3 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 01-02 | 1 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 01-02 | 2 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 01-03 | 1 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 01-03 | 2 | ✅ | ✅ | ✅ | ✅ | ✅ |

**结果：** 7/7 任务完整 ✅

---

## 3. Dimension 3: Dependency Correctness（依赖正确性）


```
01-01 (Wave 1, depends_on: [])
  ├── 01-02 (Wave 2, depends_on: [01-01])
  └── 01-03 (Wave 2, depends_on: [01-01])
```

- 无循环依赖 ✅
- 所有依赖引用有效 ✅
- Wave 编号一致 ✅
- 01-02 和 01-03 均依赖 01-01 提供的 AppCoordinator，依赖方向正确 ✅

**结果：** 依赖图有效 ✅

---

## 4. Dimension 4: Key Links Planned（关键连接）


| 计划 | 连接 | 状态 |
|------|------------|--------|
| 01-01 | VoiceTypeApp → AppCoordinator（@StateObject） | ✅ |
| 01-01 | MenuBarView → PermissionManager（via AppCoordinator @Published） | ✅ |
| 01-01 | SettingsView → KeychainStore（obfuscatedValue + store） | ✅ |
| 01-02 | HotkeyManager → AppCoordinator（回调钩子） | ✅ |
| 01-02 | HotkeyManager → Logging（Logger.hotkey） | ✅ |
| 01-03 | AudioCaptureService → AudioBuffer（RingBuffer.write） | ✅ |
| 01-03 | AudioCaptureService → Logging（Logger.audio） | ✅ |
| 01-03 | AudioCaptureService → AppCoordinator（NotificationCenter） | ✅ |

**结果：** 所有关键连接已规划 ✅

---

## 5. Dimension 5: Scope Sanity（范围合理性）


| 计划 | 任务数 | 文件数 | 评估 |
|------|--------|---------|-------|
| 01-01 | 3 | 14 | ✅ 合理 |
| 01-02 | 2 | 2 | ✅ 合理 |
| 01-03 | 2 | 3 | ✅ 合理 |

**结果：** 范围合理，无超预算风险 ✅

---

## 6. Dimension 6: Verification Derivation（验证推导）


### Plan 01-01 must_haves
- ✅ "启动 1 秒内看到菜单栏图标，颜色反映权限状态" — 用户可观测
- ✅ "顺序权限引导：先麦克风说明→授权→辅助功能说明→跳转系统设置" — 用户可观测
- ✅ "菜单栏→Settings→独立设置窗口，API 密钥脱敏显示" — 用户可观测
- ✅ "API 密钥存于 Keychain，不落 UserDefaults/plist" — 安全需求，具体可检查

### Plan 01-02 must_haves
- ✅ "从任意应用按住 Fn 键→检测按下/释放" — 用户可观测
- ✅ "从任意应用按下 Ctrl+Shift+C→检测触发" — 用户可观测
- ✅ "全局热键，所有应用均可触发" — 用户可观测
- ✅ "权限丢失 5 秒内检测并提醒" — 用户可观测

### Plan 01-03 must_haves
- ✅ "16kHz mono Float32 PCM 采集" — 技术指标，Phase 1 合理
- ✅ "设备热插拔自动切换，不崩溃不无声" — 用户可观测
- ✅ "500ms 内产生非零样本" — 性能指标

**结果：** must_haves 推导正确 ✅

---

## 7. Dimension 7: Context Compliance（上下文合规）


| 决策 | 描述 | 落实位置 | 状态 |
|------|-------------|----------------|--------|
| D-01 | MenuBarExtra 场景 | 01-01 Task 2 (VoiceTypeApp.swift) | ✅ |
| D-02 | Settings 场景 | 01-01 Task 3 (SettingsView) | ✅ |
| D-03 | Fn hold-to-talk | 01-02 Task 1 (HotkeyDefaults.dictation) | ✅ |
| D-04 | Ctrl+Shift+C press-to-trigger | 01-02 Task 1 (HotkeyDefaults.correction) | ✅ |
| D-05 | CGEvent.tapCreate（非 Carbon） | 01-02 Task 1 (RESEARCH.md Pattern 4) | ✅ |
| D-06 | Watchdog 权限监控 | 01-02 Task 2 (5s watchdog) | ✅ |
| D-07 | 顺序权限引导（麦克风→辅助功能） | 01-01 Task 2 (PermissionGateView) | ✅ |
| D-08 | 菜单栏图标颜色（绿/橙/红） | 01-01 Task 2 (PermissionManager.PermissionStatus) | ✅ |
| D-09 | AVAudioEngine / 16kHz mono Float32 | 01-03 Task 1 (AudioCaptureService) | ✅ |
| D-10 | 音频设备热插拔监控 | 01-03 Task 2 (startDeviceMonitoring) | ✅ |
| D-11 | 子系统文件夹结构 | 01-01 Task 1 (Xcode project setup) | ✅ |
| D-12 | Keychain (SecItem)，禁用 UserDefaults | 01-01 Task 3 (KeychainStore) | ✅ |

**结果：** 12/12 决策落实 ✅

---

## 8. Dimension 7b: Scope Reduction Detection（范围缩减检测）


扫描了所有计划的 `<action>` 部分，查找范围缩减语言（"v1"、"static for now"、"hardcoded"、"future enhancement" 等）：

- 仅在 SettingsView 的 Defaults.swift 中发现 "v2 可自定义" 注释——属于信息性标注，不属于范围缩减（热键默认值功能正常可用）。
- 未发现任何范围缩减。

**结果：** 无范围缩减 ✅

---

## 9. Dimension 7c: Architectural Tier Compliance（架构层级合规）


对照 RESEARCH.md § Architectural Responsibility Map：

| 能力 | 需求层级 | 实现层级 | 状态 |
|------------|-----------------|-----------------|--------|
| 菜单栏 UI | Presentation (SwiftUI) | 01-01 MenuBarView (SwiftUI) | ✅ |
| 热键注册 | Input Capture (CGEvent) | 01-02 HotkeyManager (CGEvent) | ✅ |
| 音频采集 | Input Capture (AVAudioEngine) | 01-03 AudioCaptureService | ✅ |
| 权限管理 | App Shell (TCC) | 01-01 PermissionManager | ✅ |
| Keychain 存储 | Data / Security | 01-01 KeychainStore | ✅ |
| 设置持久化 | App Shell (UserDefaults) | 01-01 SettingsStore | ✅ |
| 应用协调 | Orchestration (AppCoordinator) | 01-01 AppCoordinator | ✅ |
| 状态指示 | Presentation (SwiftUI) | 01-01 MenuBarView | ✅ |

**结果：** 所有能力分配到正确的架构层级 ✅

---

## 10. Dimension 9: Cross-Plan Data Contracts（跨计划数据契约）


### ⚠️ 共享文件修改冲突风险

**问题：** 计划 01-02 (Task 2, Step 3) 和 01-03 (Task 2, Step 3) 均在同一 Wave 2 中修改 `VoiceType/AppCoordinator.swift`：

| 计划 | 添加内容 | 位置 |
|------|-----------|------|
| 01-02 | `let hotkeyManager = HotkeyManager()`、`@Published var hotkeyTapActive`、回调钩子设置、`.hotkeyTapDisabled` 监听 | AppCoordinator 初始化块 |
| 01-03 | `let audioCapture = AudioCaptureService()`、`@Published var currentInputDevice`、音频设备通知监听、`startAudioCapture()`/`stopAudioCapture()` | AppCoordinator 初始化块 |

两个计划的修改是**加性的**（添加不同属性、监听不同通知），但执行时可能产生文件级合并冲突。如果 executor 逐文件写入而非追加，后执行的计划可能覆盖先执行的计划的修改。建议在 PLAN.md 中添加合并指引，或将 AppCoordinator 集成拆入独立的 Wave 3 计划。

**严重程度：** WARNING（不阻断执行，但需要 executor 注意处理合并）

**结果：** 1 个警告 ⚠️

---

## 11. Dimension 11: Research Resolution（研究问题解决）


### ❌ 未解决的研究问题

RESEARCH.md 第 792 行起存在「## Open Questions」章节，包含 3 个问题，**均未标记 RESOLVED**：

| # | 问题 | 状态 |
|---|------|--------|
| 1 | **Fn 键在 Touch Bar Mac 和第三方键盘上的行为** — 问题：Magic Keyboard 的 Fn 键发送 `.keyDown/.keyUp` 还是仅 `.flagsChanged`？ | ❌ 未解决 |
| 2 | **App Store vs. 直接分发所需的权限声明** — 问题：App Store 审核是否拒绝需要 Accessibility 权限的应用？ | ❌ 未解决 |
| 3 | **macOS 15 (Sequoia) 上 CGEvent tap 稳定性** — 问题：是否有新的 API 要求或权限声明？ | ❌ 未解决 |

虽然每个问题都附有 "Recommendation"，但 Plan Checker 的 Dimension 11 要求：
- 章节标题必须是 `## Open Questions (RESOLVED)`，**或**
- 每个问题必须有内联 `RESOLVED` 标记

当前状态：章节标题为 `## Open Questions`（无 RESOLVED 后缀），3 个问题均无 RESOLVED 标记。

**严重程度：** BLOCKER（阻断执行——研究问题未解决前不应进入规划阶段）

**修复建议：**
1. 将章节标题改为 `## Open Questions (RESOLVED)`
2. 对每个问题添加内联 RESOLVED 标记，如：
   ```markdown
   1. **Fn key behavior** — RESOLVED: Implement `flagsChanged` handler; test on target hardware during UAT.
   ```

**结果：** 1 个阻断 ❌

---

## 12. 其他维度

| 维度 | 状态 |
|-----------|--------|
| **Dimension 7a** (Context Compliance — Deferred Ideas) | ✅ 无延期想法混入 |
| **Dimension 8** (Nyquist Compliance) | ⏭️ 已跳过（`nyquist_validation: false` in config.json） |
| **Dimension 10** (AGENTS.md Compliance) | ⏭️ 已跳过（无可适用于计划验证的代码级规范） |
| **Dimension 12** (Pattern Compliance) | ⏭️ 已跳过（无 PATTERNS.md） |
| **Verify Command Format Sanity** | ✅ 所有 `<automated>` 命令无 `^` 锚点错误，无错误抑制模式 |
| **Numeric/Factual Claim Authority** | ✅ 计划与 RESEARCH.md 之间无数值/事实性不一致 |

---

## 综合结果

### 成功标准追溯

| # | 成功标准（来自 ROADMAP.md） | 实现位置 | 状态 |
|---|---------------------------|----------------|--------|
| 1 | 启动后 1 秒内看到菜单栏图标 | 01-01 Task 2（iconName 默认值 + 后台异步初始化） | ✅ |
| 2 | 首次启动顺序权限引导（麦克风→辅助功能） | 01-01 Task 2（PermissionGateView 分步引导） | ✅ |
| 3 | 从菜单栏打开设置窗口，配置 API 密钥和偏好 | 01-01 Task 3（SettingsView + SettingsStore） | ✅ |
| 4 | API 密钥存 Keychain，设置界面脱敏显示 | 01-01 Task 3（KeychainStore + obfuscatedValue） | ✅ |
| 5 | 从任意应用按住听写热键，检测按下/释放并切换状态 | 01-02 Task 1 & 2（Fn key + AppCoordinator state） | ✅ |

### 威胁模型覆盖

所有 3 份计划均包含完整的 STRIDE 威胁模型，总计 13 个威胁注册项（T-01-01 至 T-01-13），覆盖 Keychain 安全、权限提升、拒绝服务、信息披露等维度。所有 high 严重性威胁均有缓解方案。

### PITFALLS.md 预防措施

| Pitfall | 预防措施 | 状态 |
|---------|---------------|--------|
| Pitfall 1/4: 热键权限丢失 | Watchdog 5s 检查 + 事件心跳 + 菜单栏颜色指示 | ✅ |
| Pitfall 2/7: 主线程阻塞 | 异步 Task.detached 初始化 + 立即默认图标 | ✅ |
| Pitfall 3/10: 音频设备热插拔 | EngineConfigChange + RouteChange 监听 + 静音检测 | ✅ |
| Pitfall 4: Keychain 静默失败 | 所有 OSStatus 显式检查 + 明确错误枚举 | ✅ |

---

## 问题汇总

```yaml
issues:
  - plan: null
    dimension: research_resolution
    severity: blocker
    description: "RESEARCH.md '## Open Questions' section contains 3 unresolved questions (Fn key behavior, App Store entitlements, macOS 15 CGEvent tap stability). Section header lacks '(RESOLVED)' suffix, and no question has an inline RESOLVED marker."
    file: ".planning/phases/01-foundation/01-RESEARCH.md"
    section: "Open Questions (lines 792-807)"
    fix_hint: |
      1. Rename section to '## Open Questions (RESOLVED)'
      2. Add inline RESOLVED markers to each question, e.g.:
         "1. **Fn key behavior** — RESOLVED: implement flagsChanged handler; test during UAT."
         "2. **Entitlements** — RESOLVED: plan for DMG direct distribution as primary; App Store as secondary."
         "3. **macOS 15 stability** — RESOLVED: implement aggressive watchdog + re-enable logic; monitor beta changes."

  - plan: "01-02, 01-03"
    dimension: cross_plan_data_contracts
    severity: warning
    description: "Both Plan 01-02 (Task 2, Step 3) and Plan 01-03 (Task 2, Step 3) modify VoiceType/AppCoordinator.swift in Wave 2. Additions are non-overlapping (hotkey props vs audio props) but file-level merge conflicts could occur during parallel execution."
    files_affected: ["VoiceType/AppCoordinator.swift"]
    fix_hint: |
      Options:
      1. Add explicit merge guidance in both plans (e.g., "Append to init block, do not replace entire file")
      2. Extract AppCoordinator integration into a shared Wave 3 plan (Plan 01-04)
      3. Executor handles sequentially within Wave 2 (current GSD behavior for shared files)
```

---

## 建议

1 个阻断项需要解决后再进入执行阶段。警告项可在执行时通过 executor 的共享文件顺序化处理自动解决，但建议在计划阶段显式标注合并指引以降低风险。

**下一步：** 解决 RESEARCH.md 的 Open Questions 后，重新运行验证。
