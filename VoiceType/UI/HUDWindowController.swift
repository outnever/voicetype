import AppKit
import SwiftUI

/// 管理 HUD 覆盖层（浮动状态窗口）的显示/隐藏生命周期。
///
/// 创建无边框、不抢焦点的浮动 NSWindow，显示在屏幕中央偏上的位置。
/// 通过 `show()` / `hide()` 方法控制可见性，窗口横跨所有桌面空间。
///
/// ## 窗口属性
///
/// - `.borderless` + `.nonactivatingPanel`：无标题栏，点击不切换焦点
/// - `.floating`：浮于所有普通窗口之上（CGWindowLevel ~1000）
/// - `.canJoinAllSpaces` + `.stationary` + `.ignoresCycle`：在所有桌面空间可见
/// - `.ultraThinMaterial` 背景由 `HUDOverlayView` 渲染
///
/// ## 设计决策（对应 RESEARCH.md Pattern 4）
///
/// - 通过 `init(coordinator:)` 接收 AppCoordinator 引用，而非使用单例
/// - `lazy` 延迟初始化——NSWindow 创建有副作用，推迟到首次使用
final class HUDWindowController: NSWindowController {

    /// 创建 HUD 窗口并绑定到指定的 AppCoordinator。
    ///
    /// 窗口属性在创建时一次性配置；位置在 `show()` 时动态更新以响应
    /// 屏幕变化（例如外接显示器拔出）。
    ///
    /// - Parameter coordinator: VoiceType 的中央状态机，HUD 通过
    ///   `@ObservedObject` 响应状态变化来更新图标和文字。
    init(coordinator: AppCoordinator) {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 浮于所有普通窗口之上
        window.level = .floating

        // 在所有桌面空间可见，不参与 Mission Control 或 Cmd+Tab 循环
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // 透明背景——实际外观由 SwiftUI 视图的 .ultraThinMaterial 提供
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.alphaValue = 0.9
        // 允许按住面板空白处拖动到任意位置（按钮/滚动区仍正常响应点击）
        window.isMovableByWindowBackground = true

        // 将 SwiftUI 视图嵌入 NSWindow
        window.contentView = NSHostingView(
            rootView: HUDOverlayView(coordinator: coordinator)
        )

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 可见性控制

    /// HUD 当前是否可见。
    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// 显示 HUD，位于主屏幕左下角（不遮挡中央内容）。
    ///
    /// 每次调用时重新计算位置，以便在外接显示器热插拔后正确布局。
    /// `orderFrontRegardless()` 确保即使应用不是前台应用，HUD 也能显示。
    func show() {
        guard let window else { return }

        // 左下角定位——避免遮挡屏幕中央的内容
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.minX + 24
            let y = screenRect.minY + 24
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFrontRegardless()
        Log.app.info("HUDWindowController: HUD shown")
    }

    /// 隐藏 HUD，从屏幕上移除。
    ///
    /// `orderOut(nil)` 将窗口从屏幕列表中移除。
    /// 下次 `show()` 时重新创建——无需保留隐藏的不可见窗口。
    func hide() {
        guard let window else { return }

        window.orderOut(nil)
        Log.app.info("HUDWindowController: HUD hidden")
    }
}
