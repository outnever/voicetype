import SwiftUI

/// 帮助窗口——快速上手、权限设置、配置大模型、使用示例、常用内容。
struct HelpView: View {
    var body: some View {
        TabView {
            quickStartTab
                .tabItem { Label("快速上手", systemImage: "bolt") }

            permissionsTab
                .tabItem { Label("权限设置", systemImage: "lock.shield") }

            configTab
                .tabItem { Label("配置大模型", systemImage: "cpu") }

            usageTab
                .tabItem { Label("使用示例", systemImage: "sparkles") }

            contentTab
                .tabItem { Label("常用内容", systemImage: "text.quote") }
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - 快速上手

    private var quickStartTab: some View {
        helpScroll {
            section("三步上手") {
                bullet("① 授权", "菜单栏图标 → 设置 → 权限，完成麦克风与辅助功能授权。")
                bullet("② 填 Key", "菜单栏图标 → 设置 → API 密钥，填入 DeepSeek 或其他供应商的 Key；可选在「模型」页选择模型。")
                bullet("③ 说话", "按住 Fn 说出指令，松开后自动执行。")
            }
            section("基本用法") {
                bullet("听写", "双击 Fn，用 macOS 系统听写输入文字到光标处。")
                bullet("纠错", "长按 Fn（或 ⌥+回车），说出「把 X 改成 Y」，松开即原地修正。")
                bullet("状态面板", "左下角面板实时显示识别内容和操作记录。")
            }
        }
    }

    // MARK: - 权限设置

    private var permissionsTab: some View {
        helpScroll {
            section("麦克风") {
                text("纠错录音需要麦克风权限。首次使用时在设置 → 权限中点击「请求麦克风权限」，系统会弹出授权框，选择允许。")
            }
            section("辅助功能（无障碍）") {
                text("VoiceType 通过 macOS 辅助功能接口读写任意应用的光标处文字。此权限必须在「系统设置 → 隐私与安全性 → 辅助功能」中手动勾选 VoiceType。")
                text("提示：若使用 swift run 运行，勾选的是终端应用；若安装 .app，勾选的是 VoiceType 本体。")
            }
            section("语音识别") {
                text("纠错指令的识别使用 Apple 语音识别服务。首次纠错时会弹出授权框；如果拒绝过，可在「系统设置 → 隐私与安全性 → 语音识别」中重新开启。")
            }
        }
    }

    // MARK: - 配置大模型

    private var configTab: some View {
        helpScroll {
            section("填写 API 密钥") {
                bullet("DeepSeek", "platform.deepseek.com 创建 Key，格式 sk-...。推荐，性价比高。")
                bullet("OpenAI", "platform.openai.com 创建 Key。")
                bullet("OpenRouter", "openrouter.ai 创建 Key，可聚合 DeepSeek、Gemini、Qwen 等几十种模型。")
            }
            section("选择模型") {
                text("在「模型」页可为每个供应商选择模型。DeepSeek 推荐 deepseek-chat；留空使用默认模型。修改后立即生效。")
            }
            section("常见问题") {
                bullet("提示未配置 API Key", "在设置 → API 密钥 中填写任一供应商的 Key。")
                bullet("提示大模型 API 错误", "检查网络连接、Key 是否有效、模型名是否拼写正确。")
            }
        }
    }

    // MARK: - 使用示例

    private var usageTab: some View {
        helpScroll {
            section("修改（把 X 改成 Y）") {
                example("「把窗间改成创建」")
                example("「把第二段的成本改成收益」")
                example("「把所有错别字都改一下」")
            }
            section("插入 / 新增（在光标处添加）") {
                example("「在光标处添加道德经的前五句」")
                example("「帮我写一段产品介绍文案」")
                text("插入不会删除已有内容，新内容添加到光标位置。")
            }
            section("删除") {
                example("「把刚才那一句删掉」")
                example("「删掉最后一行」")
                example("「把所有内容都删掉」")
            }
            section("全文操作") {
                example("「把全文每行之间加一个空行」")
                example("「去掉所有多余的空行」")
                example("「把全文的乱码清理掉」")
            }
            section("小技巧") {
                bullet("说人话即可", "不用记固定语法，怎么自然怎么说。")
                bullet("同音字自动纠正", "说「把快变成卖」也能推断出你其实想说「把块变成慢」。")
                bullet("结合上下文", "指令里的字被识别错了，AI 会结合上下文推断真实意图。")
            }
        }
    }

    // MARK: - 常用内容

    private var contentTab: some View {
        helpScroll {
            section("常用内容模板") {
                text("以下指令可用于快速输入大篇幅内容（在光标处插入）：")
                example("「在光标处插入《道德经》第一章」")
                example("「在光标处插入鲁迅的名言『其实地上本没有路，走的人多了，也便成了路』」")
                example("「在光标处写一份请假条的模板」")
                example("「在光标处写一段感谢信的开头」")
                example("「在光标处插入今日名言『知行合一』及出处王阳明」")
            }
            section("提示") {
                text("书籍片段、名言、公文模板等常见内容，直接说出书名或作者即可。若一次没插对，再说一次「把刚才插入的内容删掉」即可撤销。")
            }
        }
    }

    // MARK: - 组件

    private func helpScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func bullet(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.accentColor)
            (Text("**\(label)**：") + Text(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func example(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.callout)
                .monospaced()
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func text(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
