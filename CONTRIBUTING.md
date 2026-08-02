# 参与贡献

感谢你愿意为 VoiceType 做贡献！无论是报 bug、提新功能还是提交代码，都欢迎。

## 环境要求

- macOS 14+
- Xcode 命令行工具（`xcode-select --install`）
- Swift 6.x

## 本地构建与测试

```bash
swift build          # 构建
swift run            # 运行（菜单栏应用，需在图形界面环境）
swift test           # 运行测试
./scripts/build-app.sh     # 打包 .app → dist/VoiceType.app
./scripts/build-dmg.sh     # 生成 DMG 安装包 → dist/VoiceType.dmg
```

## 提交规范

- 分支：基于 `main` 新建分支，如 `feat/xxx` 或 `fix/xxx`
- 提交信息使用约定式提交（Conventional Commits）：
  - `feat:` 新功能
  - `fix:` 修 bug
  - `docs:` 文档
  - `refactor:` 重构
  - `test:` 测试
  - `chore:` 杂项
- 例如：`fix: hotkey 注册时序问题`

## 代码风格

- 跟随现有代码风格（Swift、4 空格缩进、中文注释）
- 新增功能尽量补充测试（Swift Testing，`Tests/VoiceTypeTests/`）
- 提交前跑 `swift test` 保证全绿

## 报告 Bug / 提需求

- Bug 请用 [Bug 模板](.github/ISSUE_TEMPLATE/bug_report.md)，附上日志（应用内「日志」窗口复制）
- 功能建议请用 [Feature 模板](.github/ISSUE_TEMPLATE/feature_request.md)

## 架构速览

- `AppCoordinator.swift`：中央状态机，所有子系统的唯一耦合点
- `Hotkeys/`：CGEvent 全局热键
- `Correction/`：大模型纠错引擎 + 动态模型目录
- `TextIO/`：辅助功能读写 + 剪贴板回退
- `Transcription/`：Apple 语音识别
- `UI/`：HUD 状态面板
- 改代码前先看 `HANDOFF.md` 的「关键设计决策」
