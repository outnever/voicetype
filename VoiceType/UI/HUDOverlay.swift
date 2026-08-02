import SwiftUI

/// 浮动半透明状态面板——左下角常驻。
///
/// 展示：
/// - 顶部：当前状态 + 实时识别文本
/// - 中部：操作历史（最近的输入与操作，可滚动）
/// - 底部：最近一次错误条（几秒后自动隐藏，由 AppCoordinator 管理）
///
/// 完整日志见菜单栏「日志」。
struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection

            if !liveText.isEmpty {
                Text(liveText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !coordinator.operationHistory.isEmpty {
                Divider()
                    .overlay(Color.white.opacity(0.2))

                historySection
            }

            if let error = coordinator.currentError {
                errorStrip(error)
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
    }

    // MARK: - 头部

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 20))
                .foregroundColor(.white)

            Text(headerMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 操作历史

    private var historySection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(coordinator.operationHistory) { item in
                        historyRow(item)
                            .id(item.id)
                    }
                }
            }
            .frame(height: historyAreaHeight)
            .onChange(of: coordinator.operationHistory.count) { _, _ in
                if let first = coordinator.operationHistory.first {
                    withAnimation {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    private func historyRow(_ item: OperationLogItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(timeString(item.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 52, alignment: .leading)

            Text(item.message)
                .font(.system(size: 12))
                .foregroundColor(item.isError ? .red : .white.opacity(0.92))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 操作历史区域高度——按条数自适应，最多约 7 行。
    private var historyAreaHeight: CGFloat {
        let rowHeight: CGFloat = 20
        let shown = min(coordinator.operationHistory.count, 7)
        return CGFloat(shown) * rowHeight + 6
    }

    // MARK: - 错误条

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.25))
        )
        .transition(.opacity)
    }

    // MARK: - 状态衍生

    private var headerMessage: String {
        switch coordinator.state {
        case .recording:
            return "🎤 录音中…"
        case .transcribing:
            return "📝 转录中…"
        case .correcting:
            return "🛠 纠错中…"
        case .error(let msg):
            return String(msg.prefix(30))
        case .idle:
            return coordinator.operationHistory.isEmpty ? "就绪" : "VoiceType"
        }
    }

    private var iconName: String {
        coordinator.iconName
    }

    private var liveText: String {
        coordinator.appleSpeech.liveText
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
