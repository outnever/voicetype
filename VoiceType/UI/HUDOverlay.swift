import SwiftUI

/// 浮动半透明状态覆盖层，显示录音/转录状态图标、文字和实时识别内容。
///
/// 由 `HUDWindowController` 管理可见性——此视图仅负责渲染内容，
/// 不自行控制显示/隐藏。文字和图标通过 `AppCoordinator` 的
/// Published 属性驱动状态更新。
///
/// D-11: 录音时显示"🎤 录音中…"
/// D-12: 转录时显示"📝 转录中…"，完成后自动消失
/// 纠错时显示实时识别的纠错指令（appleSpeech.liveText）
struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(.white)

                Text(hudMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            // 实时识别文本（纠错指令或听写内容）
            if !liveText.isEmpty {
                Text(liveText)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 最近一次修正结果（常驻显示）
            if !correctionMessage.isEmpty {
                Text(correctionMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
    }

    // MARK: - 状态衍生

    /// 从 `coordinator.state` 派生 HUD 显示文字。
    private var hudMessage: String {
        switch coordinator.state {
        case .recording:
            return "🎤 录音中…"
        case .transcribing:
            return "📝 转录中…"
        case .correcting:
            return "🛠 纠错中…"
        case .error(let msg):
            return String(msg.prefix(30))
        default:
            return ""
        }
    }

    /// 从 `coordinator.iconName` 派生图标——与菜单栏保持一致性。
    private var iconName: String {
        coordinator.iconName
    }

    /// 实时识别文本（Apple 语音识别的流式结果）。
    private var liveText: String {
        coordinator.appleSpeech.liveText
    }

    /// 最近一次修正结果（常驻显示）。
    private var correctionMessage: String {
        coordinator.lastCorrectionMessage
    }
}
