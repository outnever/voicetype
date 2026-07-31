import SwiftUI

/// 浮动半透明状态覆盖层，显示录音/转录状态图标和文字。
///
/// 由 `HUDWindowController` 管理可见性——此视图仅负责渲染内容，
/// 不自行控制显示/隐藏。文字和图标通过 `AppCoordinator` 的
/// Published 属性驱动状态更新。
///
/// D-11: 录音时显示"🎤 录音中…"
/// D-12: 转录时显示"📝 转录中…"，完成后自动消失
struct HUDOverlayView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(.white)

            Text(hudMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 180, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
    }

    // MARK: - 状态衍生

    /// 从 `coordinator.state` 派生 HUD 显示文字。
    ///
    /// - `.recording` → "🎤 录音中…" (D-11)
    /// - `.transcribing` → "📝 转录中…" (D-12)
    /// - `.error(let msg)` → 截断的错误消息
    /// - 其他 → 空字符串（不显示）
    private var hudMessage: String {
        switch coordinator.state {
        case .recording:
            return "🎤 录音中…"
        case .transcribing:
            return "📝 转录中…"
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
}
