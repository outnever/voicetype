# VoiceType 项目交接文档

> **交接日期**: 2026-08-01
> **交接机器**: Mac mini (nobotdeMac-mini) → MacBook Air
> **代码位置**: 本地 `/Users/nobot/opencode/voicetype`，远程 NAS Gitea

---

## 1. 项目是什么

VoiceType 是 macOS 系统级语音纠错工具：
- **听写**：交给 macOS 系统（双击 Fn，系统原生）
- **纠错**：长按 Fn（或自定义热键）说话 → Apple 语音识别指令 → 大模型修正 → 精确替换光标处文字

一句话：**说错了不用摸键盘，说句人话就能改回来。**

## 2. 接手机器需要的环境

| 依赖 | 版本 | 检查命令 |
|------|------|---------|
| macOS | 14+ | 系统设置 |
| Xcode 命令行工具 | 任意新版 | `xcode-select --install` |
| Swift | 6.x（当前 6.3.3） | `swift --version` |
| Xcode | 当前 26.6（CLT 足够，完整 Xcode 非必需） | `xcodebuild -version` |
| git | 任意 | `git --version` |
| 外置麦克风 | 推荐（内置麦也行） | — |

> 用 `swift build` / `swift run` 即可，不需要完整 Xcode。

## 3. 拉取代码

```bash
git clone ssh://git@192.168.3.17:3022/nobot/voicetype.git
cd voicetype
```

**如果 SSH 连不上 NAS**（MacBook Air 没有 NAS 的 SSH 配置）：
1. 复制 Mac mini 的 `~/.ssh/id_ed25519` 公钥/私钥到 MacBook Air（或重新生成后到 NAS Gitea 设置里添加）
2. 或直接复制项目文件夹（含 `.git`）整个拷贝

**NAS 连接信息**（写进 `~/.ssh/config`）：
```
Host nas-gitea
    HostName 192.168.3.17
    Port 3022
    User git
    IdentityFile ~/.ssh/id_ed25519
```

## 4. 首次运行配置

```bash
swift build       # 首次会拉取 SPM 依赖（WhisperKit 等，需网络，国内需能访问 GitHub）
swift run         # 图形界面下运行（菜单栏应用）
```

首次使用三步：
1. **API Key**：菜单栏图标 → 偏好设置 → API 密钥 → 填 DeepSeek（或其他）Key
   - 存储在 `~/Library/Application Support/VoiceType/api-keys.json`（明文，勿外传）
   - 旧版钥匙串里的 Key 会自动迁移
2. **权限授权**：
   - 麦克风（弹窗）
   - 语音识别（弹窗）
   - 辅助功能：`swift run` 模式下给**终端**授权；打包成 `.app` 后给 VoiceType 授权
3. **测试**：双击 Fn 听写 / 长按 Fn 说"把 X 改成 Y"纠错

## 5. 项目结构

```
voicetype/
├── Package.swift                  # SPM 依赖（WhisperKit/OpenAI/swift-log）
├── VoiceType/
│   ├── VoiceTypeApp.swift         # @main 入口 + 日志初始化
│   ├── AppCoordinator.swift       # 中央状态机（所有子系统的唯一耦合点）
│   ├── App/                       # 菜单栏 UI、设置窗口、权限引导
│   ├── Hotkeys/                   # CGEvent 热键（Fn 长按 / ⌥+回车 / ⌃+空格）
│   ├── Transcription/             # Apple 语音识别（SFSpeechRecognizer）+ WhisperKit(未启用)
│   ├── Correction/                # 大模型纠错引擎（双模式：edits/full_text）
│   ├── TextIO/                    # AXUIElement + 剪贴板回退（读/插/精确替换/全选替换）
│   ├── Audio/                     # AVAudioEngine 采集（流式喂给识别器）
│   ├── Settings/                  # 配置存储（UserDefaults + 配置文件）、Keychain(已弃用)、登录项
│   ├── UI/                        # HUD 常驻面板（状态+实时识别+修正结果）
│   └── Utilities/                 # 日志（OSLog+文件）、提示音
├── scripts/
│   ├── build-app.sh               # .app 打包（release 构建+图标+ad-hoc签名）
│   ├── gen-icon.py                # 图标生成
│   └── download-model.sh          # 旧版 Whisper 模型下载（已不使用）
├── Tests/VoiceTypeTests/          # 39 个测试
├── .planning/                     # GSD 规划文档（PROJECT/REQUIREMENTS/ROADMAP/研究）
└── README.md                      # 使用文档
```

## 6. 核心架构速览

```
用户按热键（长按Fn/⌥+回车）
  → HotkeyManager 检测（CGEvent tap）
  → AppleSpeechService 流式识别纠错指令（SFSpeechRecognizer, zh-CN）
  → CorrectionEngine:
      ├─ 读取光标上下文（TextIO.readContext, AXUIElement）
      ├─ 发大模型（DeepSeek 优先，OpenAI 兼容 API）
      ├─ 双模式：edits（局部片段精确替换）/ full_text（全文操作/新增内容）
      ├─ 校验（original 必须逐字存在于上下文，防幻觉）
      └─ 替换（TextIO.replaceText / replaceAllText）
  → HUD 面板显示结果（常驻，左下角）
```

**关键设计决策**（改代码前必读）：
- 听写完全交系统（双击 Fn），VoiceType 只做纠错
- 热键事件：Fn 透传（不消费，保系统听写）；⌥+回车/⌃+空格 消费（防透传进应用）
- 大模型只返回"改哪段、改成什么"（JSON），替换在本地执行——保证只动指定片段
- 同音字纠错：提示词让大模型结合上下文推断（"把快变成卖"→"把块变成慢"）
- API Key 明文存配置文件（个人工具，非分发）

## 7. 常用命令

```bash
swift build                          # 构建
swift run                            # 运行
swift test                           # 测试（39 个）
./scripts/build-app.sh               # 打包 .app → dist/VoiceType.app
tail -f ~/Library/Logs/VoiceType/voicetype.log   # 实时看日志
```

## 8. 已知注意事项

1. **`swift run` 模式**：
   - 辅助功能权限授权给终端
   - 开机自启动不可用（需 .app）
   - HUD 面板、提示音正常
2. **打包 .app 后**：
   - 首次打开右键 → 打开（Gatekeeper 绕过），或 `xattr -cr /Applications/VoiceType.app`
   - 辅助功能列表出现 VoiceType 本体
3. **中文输入法冲突**：纠错热键避开 Ctrl+Shift（会被输入法拦截为切换）；默认 Fn 长按无冲突
4. **Apple 识别**：需网络（Apple 服务器），单次最长 1 分钟，偶尔返回空（提示重试即可）
5. **配置文件**：`~/Library/Application Support/VoiceType/api-keys.json` 是明文，勿提交/外传
6. **日志**：`~/Library/Logs/VoiceType/voicetype.log`，排查问题先看这里

## 9. Git 工作流

- 分支：`main`，直接提交推送
- 远程：`ssh://git@192.168.3.17:3022/nobot/voicetype.git`（NAS Gitea，私有）
- 提交后记得 `git push`
- `.build/` 已 gitignore；`dist/` 未 ignore（打包产物，可忽略或加 ignore）

## 10. 后续规划（未完成项）

- 跨平台（Windows/Linux）——需抽象语音识别/热键/文本读写三层接口，**建议 v2 再做**
- 离线模式（WhisperKit 已集成未启用）——用户已确认不需要，放后续
- Claude 后端（现有多供应商：DeepSeek/OpenAI/OpenRouter）
- 纠错历史、diff 预览（低优先）

## 11. 快速验证清单（接机后跑一遍）

1. `swift build` 通过
2. `swift test` 39 个全绿
3. `swift run` 菜单栏出现图标
4. 双击 Fn → 系统听写正常
5. 长按 Fn → HUD 面板出现 + 开始音
6. 说"把X改成Y" → 精确替换 + 完成音
7. 配置 API Key 后纠错可用
