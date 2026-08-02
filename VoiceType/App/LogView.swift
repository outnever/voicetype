import SwiftUI

/// 日志查看窗口——用户可查看并复制应用日志，便于提交 bug 报告。
///
/// 读取 `Log.fileLogURL`（~/Library/Logs/VoiceType/voicetype.log）的最后 300 行。
/// 提供「复制日志」一键拷贝到剪贴板，用户可直接粘贴到 Issue / 反馈里。
struct LogView: View {
    @State private var logContent: String = ""
    @State private var copied = false
    @State private var lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            logScrollView
            Divider()
            footer
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .onAppear(perform: reload)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.gearshape")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("应用日志")
                    .font(.headline)
                Text("排查问题用——如有异常，复制日志发给开发者")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                reload()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                copyLog()
            } label: {
                Label(copied ? "已复制" : "复制日志", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)
        }
    }

    // MARK: - 日志内容

    private var logScrollView: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(logContent.isEmpty ? "（暂无日志）" : logContent)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(Log.fileLogURL.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("日志文件路径")

            Spacer()

            if let updated = lastUpdated {
                Text("更新于 \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 动作

    /// 读取日志文件，展示最后 300 行。
    private func reload() {
        guard let data = try? Data(contentsOf: Log.fileLogURL),
              let full = String(data: data, encoding: .utf8) else {
            logContent = "（暂无日志）"
            return
        }
        let lines = full.split(separator: "\n", omittingEmptySubsequences: false)
        logContent = lines.suffix(300).joined(separator: "\n")
        lastUpdated = Date()
        copied = false
    }

    /// 复制当前展示的日志到剪贴板。
    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logContent, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copied = false
        }
    }
}
