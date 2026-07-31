import Foundation

/// Typed errors for the VoiceType transcription subsystem.
///
/// All errors conform to `LocalizedError` with Chinese-language descriptions
/// suitable for user-facing error messages in the VoiceType menu bar / HUD.
enum TranscriptionError: Error, LocalizedError {
    /// The WhisperKit pipe has not been loaded — model download/initialization is pending.
    case modelNotDownloaded

    /// Model download from HuggingFace failed due to network or server error.
    case modelDownloadFailed(underlying: Error)

    /// WhisperKit inference failed during transcription.
    case transcriptionFailed(underlying: Error)

    /// Audio array is too short for meaningful transcription (< 300ms per PITFALLS.md §2).
    case audioTooShort

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "语音模型尚未下载完成，请等待模型下载完毕后再试"
        case .modelDownloadFailed(let underlying):
            return "语音模型下载失败：\(underlying.localizedDescription)"
        case .transcriptionFailed(let underlying):
            return "语音转录失败：\(underlying.localizedDescription)"
        case .audioTooShort:
            return "音频过短（不足300毫秒），请说完整句子后再试"
        }
    }

    var failureReason: String? {
        switch self {
        case .modelNotDownloaded:
            return "模型未就绪"
        case .modelDownloadFailed:
            return "网络连接失败或模型仓库不可用"
        case .transcriptionFailed:
            return "WhisperKit 推理过程出错"
        case .audioTooShort:
            return "音频时长不足"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotDownloaded:
            return "请检查网络连接，模型将自动在后台下载。您可以在菜单栏中查看下载进度。"
        case .modelDownloadFailed:
            return "请检查网络连接后重启应用，模型将自动重新下载。"
        case .transcriptionFailed:
            return "请重新按住热键说话，如持续失败请重启应用。"
        case .audioTooShort:
            return "请按住热键，说出完整的句子后松开。"
        }
    }
}
