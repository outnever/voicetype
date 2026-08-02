import SwiftUI

@main
struct VoiceTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // 初始化双通道日志（OSLog + 文件）——必须在任何 Logger 使用前调用
        Log.enableFileLogging()
    }

    var body: some Scene {
        MenuBarExtra("VoiceType", systemImage: coordinator.iconName) {
            MenuBarView()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.menu)

        Window("欢迎使用 VoiceType", id: "permission-gate") {
            PermissionGateView()
                .environmentObject(coordinator)
                .onAppear { WindowManager.ensureActiveApp() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("偏好设置", id: "settings") {
            SettingsView()
                .environmentObject(coordinator)
                .onAppear { WindowManager.ensureActiveApp() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("应用日志", id: "logs") {
            LogView()
                .onAppear { WindowManager.ensureActiveApp() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("帮助", id: "help") {
            HelpView()
                .onAppear { WindowManager.ensureActiveApp() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("关于 VoiceType", id: "about") {
            AboutView()
                .onAppear { WindowManager.ensureActiveApp() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Menu bar 应用默认不能成为前台应用——窗口打开后无法接收键盘输入。
/// 此方法临时将激活策略切换为 .regular（显示 Dock 图标），以便用户能正常打字。
/// 窗口全部关闭后（restoreMenuBarOnlyApp）恢复为 .accessory，隐藏 Dock 图标。
@MainActor
enum WindowManager {
    static func ensureActiveApp() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 当没有普通窗口可见时，恢复为菜单栏应用（隐藏 Dock 图标）。
    /// HUD 是 .floating 层级的浮窗，不算普通窗口，不影响判断。
    static func restoreMenuBarOnlyApp() {
        let hasRegularWindow = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
        if !hasRegularWindow && NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 供 OnboardingView 等访问共享实例。
    nonisolated(unsafe) static weak var shared: AppDelegate?

    /// 手动管理的窗口（新手引导、引导中的帮助窗口）——需强引用防止被释放。
    private var onboardingWindow: NSWindow?
    private var manualHelpWindow: NSWindow?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("VoiceType 已启动")

        // 任意窗口关闭后，若没有其他普通窗口，恢复菜单栏应用身份（隐藏 Dock 图标）。
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            WindowManager.restoreMenuBarOnlyApp()
        }

        // 首次运行显示新手引导。注意：AppCoordinator 由 SwiftUI 的 @StateObject 延迟创建，
        // 需等待场景建立后再访问（AppCoordinator.shared）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            WindowManager.ensureActiveApp()
            if !UserDefaults.standard.bool(forKey: Defaults.Key.onboardingCompleted) {
                self.showOnboarding()
            }
        }
    }

    // MARK: - 新手引导

    func showOnboarding() {
        guard onboardingWindow == nil, let coordinator = AppCoordinator.shared else { return }
        Log.app.info("新手引导：首次运行，显示引导窗口")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "新手引导"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView().environmentObject(coordinator))
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        WindowManager.ensureActiveApp()
    }

    func closeOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    // MARK: - 引导内帮助

    func showHelpFromOnboarding() {
        if let existing = manualHelpWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "帮助"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: HelpView())
        window.makeKeyAndOrderFront(nil)
        manualHelpWindow = window
        WindowManager.ensureActiveApp()
    }
}
