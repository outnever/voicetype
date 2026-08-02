# VoiceType 已知问题

## 2026-08-01：新增内容场景无法区分「插入」与「替换全文」

**现象**：在已有文本的输入框中说"在鼠标位置添加/插入 XX 内容"，应用把原文全部删掉、替换成新内容，而非在光标处插入。

**根因**（两层）：

1. 读取层面：`CorrectionEngine.correct()` 调 `textIO.readContext()`（AccessibilityBridge.swift:159）读取的是**整个输入框全文**（`kAXValueAttribute`），既不读光标位置（`kAXSelectedTextRange`），也没有"光标附近上下文"概念。
2. 处理层面：LLM 只有三模式，其中"新增内容"（模式三，CorrectionEngine.swift:226）规定仅在**上下文为空或很短**时返回 `full_text`。上下文非空时，LLM 判成模式二（全文性操作）→ `replaceAllText()`（Cmd+A 全选 → 写入）→ 原文被覆盖。

**底层已有能力**：`textIO.insertText()`（AccessibilityBridge.swift:54）通过 AX `kAXSelectedTextAttribute` 在光标处插入、保留其他内容——纠错流程从未调用它。

**拟修复方案**（未实施）：
- 给 LLM 提示词新增「模式四：插入内容」→ `{"mode":"insert","insert_text":"..."}`
- `correct()` 遇到 `mode == "insert"` 时调用 `textIO.insertText(insert_text)`，在光标处插入、保留原文
- （可选）`readContext()` 同时返回光标位置，供插入/上下文边界判断

**状态**：✅ 已解决（2026-08-01）

**实际解决方案**：
- LLM 提示词把「新增内容」改为模式三 `insert` → `{"mode":"insert","insert_text":"..."}`，明确"添加/插入/追加/写一段"类指令无论上下文空不空都走 insert
- `CorrectionEditResponse` 新增 `insert_text` 字段（向后兼容）
- `CorrectionEngine.correct()` 处理 `mode == "insert"`：调 `textIO.insertText()` 在光标处插入，不删除已有内容

## 2026-08-01：Web 应用（opencode web）中纠错失败——无法定位当前应用

**现象**：在 opencode 的 web 窗口中长按 Fn 纠错，提示"纠错失败，无法定位当前应用"。

**日志**：`AXUIElement: no focused application — appResult=-25212`（`kAXErrorNoValue`）。

**根因**（两层）：

1. Web 应用 AX 限制：浏览器里的自定义编辑器（opencode web 用 CodeMirror 类控件）不暴露标准 AX 文本元素，`AXUIElementCopyAttributeValue` 拿不到聚焦应用/元素。这是 PITFALLS.md §1 记录的已知局限（Electron/浏览器/终端支持差）。
2. 读路径无回退：写路径有剪贴板回退（`insertText` AX 失败 → Cmd+V），但 `readContext()` 只委托给 AX（CompositeTextIO.swift:470），读不到就整体抛错 → `CorrectionEngine.correct()` 在第一步终止。

**拟缓解方向**（未实施）：
- 给读路径加剪贴板回退：Cmd+A 全选 → Cmd+C 复制 → 读回 → 恢复选区（`ClipboardBridge` 增加 `readContext()`）
- 把 `readContext()` 失败从"硬失败"降级为"空上下文"，让"新增内容"类指令仍可在光标处插入（配合 insert 模式修复）

**状态**：✅ 已解决（2026-08-01）

**实际解决方案**：
- `ClipboardBridge.readContext()`：Cmd+A 全选 → Cmd+C 复制 → 读回 → 恢复原剪贴板
- `CompositeTextIO.readContext()`：AX 优先 → 失败回退剪贴板 → 彻底失败返回空串（不抛错），使新增内容指令仍可在光标处插入
- 注：Web 应用中"精确替换"仍受限于 AX（replaceText 无剪贴板等价物），insert 与听写可用

