import Foundation
import ServiceManagement

/// 开机自启动管理（macOS 13+ 登录项）。
///
/// 使用 `SMAppService.mainApp` 注册/注销登录项。
/// 注意：仅对打包成 .app 的应用生效；`swift run` 调试时无效。
enum LaunchAtLoginManager {

    /// 是否已注册为登录项。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 注册开机自启动。
    /// - Throws: 注册失败（未打包为 .app 时也会失败）。
    static func enable() throws {
        do {
            try SMAppService.mainApp.register()
            Log.app.info("开机自启动已启用")
        } catch {
            Log.app.error("开机自启动注册失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 注销开机自启动。
    static func disable() {
        Task {
            do {
                try await SMAppService.mainApp.unregister()
                Log.app.info("开机自启动已关闭")
            } catch {
                Log.app.error("开机自启动注销失败: \(error.localizedDescription)")
            }
        }
    }

    /// 当前状态描述（用于设置页显示）。
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已启用"
        case .notRegistered: return "未启用"
        case .requiresApproval: return "等待系统批准（请在系统设置中允许）"
        case .notFound: return "未打包为 .app（swift run 模式不可用）"
        @unknown default: return "未知状态"
        }
    }
}
