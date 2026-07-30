# Roadmap: VoiceType

## Overview

VoiceType 从零开始构建——一个 macOS 系统级语音输入与 AI 纠错工具。三个阶段递进交付：先搭建应用框架与输入通道（菜单栏、权限、热键、音频），再实现核心听写循环（按住说话、松手出字），最后注入标志性的 AI 纠错能力（说句人话就能改回来）。每个阶段在上一阶段基础上叠加，不做返工。

## Phases

- [ ] **Phase 1: Foundation** - 应用框架、权限流程、全局热键、音频采集全部就绪
- [ ] **Phase 2: Core Dictation** - 按住热键说话，松手后语音转文字输入到任意应用
- [ ] **Phase 3: AI Correction** - 按纠错键说出自然语言指令，AI 原地修正错误文字

## Phase Details

### Phase 1: Foundation

**Goal**: 用户能够启动应用、授予权限、配置设置，且全局热键和音频采集通道正常工作
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: SHEL-01, SHEL-02, SHEL-03, SHEL-04, HOTK-01, HOTK-02, HOTK-03, HOTK-04, AUDI-01, AUDI-02
**Success Criteria** (what must be TRUE):

  1. 用户启动应用后 1 秒内看到菜单栏图标
  2. 首次启动时，用户被引导完成麦克风和辅助功能（无障碍 API）权限授予流程
  3. 用户可以从菜单栏打开设置窗口，配置 API 密钥和偏好设置
  4. 用户保存的 API 密钥存储在 macOS 钥匙串中，设置界面仅显示脱敏信息
  5. 用户从任意应用按住听写热键，应用能正确检测按键按下与释放并切换状态

**Plans**: 2/3 plans executed

Plans:

- [x] 01-01-PLAN.md — App Shell: Xcode 工程、菜单栏、权限引导、设置窗口、Keychain 密钥存储（SHEL-01~04）
- [ ] 01-02-PLAN.md — Hotkey System: CGEvent tap 全局热键（Fn + Ctrl+Shift+C）+ Watchdog 权限监控（HOTK-01~04）
- [x] 01-03-PLAN.md — Audio Capture: AVAudioEngine 音频采集管线（16kHz mono）+ 设备热插拔处理（AUDI-01~02）

**UI hint**: yes

### Phase 2: Core Dictation

**Goal**: 用户按住听写热键说话，松手后语音自动转为带标点的文字并输入到任意应用的光标位置
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: DICT-01, DICT-02, DICT-03, DICT-04, DICT-05, DICT-06, DICT-07, DICT-08, UXFE-01, UXFE-02, UXFE-03
**Success Criteria** (what must be TRUE):

  1. 用户从任意应用按住听写热键说话、松手，转录文字（含标点和大写）出现在当前光标位置
  2. 听写完全离线可用——无需网络连接即可完成语音转文字
  3. 菜单栏图标在听写过程中实时反映应用状态（空闲 / 录音中 / 转录中 / 插入文字）
  4. 发生错误时（麦克风故障、模型未加载、权限丢失），应用显示具体错误原因并给出修复指引
  5. 中英文双语听写均支持，基础词错率（WER）低于 15%

**Plans**: TBD
**UI hint**: yes

### Phase 3: AI Correction

**Goal**: 用户按下纠错热键，用自然语言说出"把 X 改成 Y"，AI 在原文中精准替换错误文字
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: CORR-01, CORR-02, CORR-03, CORR-04, CORR-05, CORR-06, CORR-07, CORR-08
**Success Criteria** (what must be TRUE):

  1. 用户按下纠错热键，用自然语言说出纠错指令（如"把窗间改成创建"），AI 在原文中原地替换错误文字
  2. 纠错指令为自由格式自然语言，无需记忆固定语法或命令
  3. 用户看到改动前后的可视化对比预览（diff preview），并可以选择接受或拒绝
  4. 用户可以撤销最近一次纠错操作，文字恢复至纠错前状态
  5. 纠错功能同时支持 GPT-4o 和 Claude API 后端

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/3 | In Progress|  |
| 2. Core Dictation | 0/0 | Not started | - |
| 3. AI Correction | 0/0 | Not started | - |
