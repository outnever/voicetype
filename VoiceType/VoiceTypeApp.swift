import SwiftUI

@main
struct VoiceTypeApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
    }
}

/// Menu bar 应用默认不能成为前台应用——窗口打开后无法接收键盘输入。
/// 此方法临时将激活策略切换为 .regular（显示 Dock 图标），以便用户能正常打字。
@MainActor
enum WindowManager {
    static func ensureActiveApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("VoiceType 已启动")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            WindowManager.ensureActiveApp()

            for window in NSApp.windows where window.title.contains("欢迎") {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}
