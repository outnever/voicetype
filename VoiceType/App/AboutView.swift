import SwiftUI

/// 关于窗口——应用信息、版本、链接。
struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            appIcon

            Text("VoiceType")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("版本 \(appVersion)（\(buildNumber)）")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("macOS 系统级语音输入与 AI 纠错工具。\n按住热键说话即可输入，说错了再按一下，说句人话就能改回来。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("听写：双击 Fn（macOS 系统原生）")
                Text("纠错：长按 Fn 说话")
                Text("基于 Apple 语音识别 + 大模型纠错")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Button("访问 GitHub 项目") {
                if let url = URL(string: "https://github.com/outnever/voicetype") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)

            Spacer()
        }
        .padding(32)
        .frame(width: 360, height: 460)
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [.blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)

            Image(systemName: "mic.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}
