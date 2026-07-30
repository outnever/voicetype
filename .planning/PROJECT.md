# VoiceType

## What This Is

VoiceType 是一个 macOS 系统级语音输入与 AI 纠错工具。用户按住热键说话即可将语音转为文字输入到任意应用；当语音识别出错时，按纠错键说出"把 X 改成 Y"的自然语言指令，AI 就能原地修正错误文字——全程无需碰键盘。

## Core Value

说错了不用摸键盘——再按一下热键，说句人话就能改回来。

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 听写模式：按住热键说话，松手后语音转文字，输入到当前光标位置
- [ ] 纠错模式：按下纠错热键，说出自然语言纠错指令，AI 自动修正之前输入的错误文字
- [ ] 系统级热键监听：全局捕获按键，不限于特定应用
- [ ] 语音转文字：使用 Whisper 本地模型，离线可用
- [ ] 语音活动检测（VAD）：自动判断用户是否说完，使用 silero-vad
- [ ] AI 纠错：将上下文文字 + 纠错指令发给大模型，原地替换修正结果
- [ ] 文字读写：通过辅助功能接口（无障碍 API）和剪贴板，读写任意应用的输入框内容

### Out of Scope

- 语音编程助手（AI 自动生成代码）—— 本项目只做修正已有文字，不生成新内容
- 语音操控电脑（控制窗口、点击菜单等）—— 只负责文字输入和纠错
- Windows 平台 —— v1 仅 macOS
- 移动端 —— v1 仅桌面端

## Context

- 语音识别引擎：Whisper 本地模型（离线可用）
- 大模型 API：GPT-4o 或 Claude API（云服务）
- 语音活动检测：silero-vad（本地运行）
- 目标平台：macOS（后续扩展到 Windows）
- 工作原理：捕获光标附近上下文 → 语音转文字 → AI 分析纠错意图 → 原地替换
- 通用性要求：不限于特定编辑器，通过操作系统级 API 工作

## Constraints

- **平台**: macOS 优先，v1 不在 Windows 上实现
- **AI 依赖**: 纠错功能依赖云端大模型 API（GPT-4o 或 Claude），需要网络连接
- **离线能力**: 语音转文字（Whisper）和 VAD（silero-vad）本地运行，无需网络
- **权限**: 需要 macOS 辅助功能权限（无障碍 API）和麦克风权限

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| macOS 优先 | 单一平台先验证核心体验，降低初期复杂度 | — Pending |
| Whisper 本地模型做语音识别 | 离线可用、延迟可控 | — Pending |
| 云端大模型做纠错 | 自然语言纠错需要强语义理解，本地模型尚不够 | — Pending |
| 系统级 API 而非编辑器插件 | 保证通用性，任意应用都能用 | — Pending |
| 自然语言纠错指令（非固定命令） | 降低用户学习成本，说人话就能纠错 | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-30 after initialization*
