import Foundation

/// Central state machine enum for VoiceType application lifecycle.
/// Used by AppCoordinator to drive UI state transitions.
enum AppState: Equatable {
    /// Application is idle, waiting for user input
    case idle
    /// User is holding the dictation hotkey, audio is being captured
    case recording
    /// WhisperKit is transcribing captured audio
    case transcribing
    /// LLM is correcting transcribed text
    case correcting
    /// An error occurred with a human-readable description
    case error(String)
}

/// 状态面板中的一条操作记录（用户输入/操作结果/错误）。
struct OperationLogItem: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let isError: Bool
}

extension PermissionStatus {
    /// 聚合权限状态的用户可读描述。
    var statusText: String {
        switch self {
        case .allGranted:  return "已就绪"
        case .partial:     return "权限不完整"
        case .noneGranted: return "未授权"
        }
    }
}
