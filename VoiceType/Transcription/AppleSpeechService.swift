import Foundation
import Speech
import AVFoundation

/// Apple SFSpeechRecognizer 封装——流式语音识别。
///
/// 相比 WhisperKit 离线方案：
/// - 零模型下载（Apple 云端识别，免费）
/// - 流式识别（边说边出字）
/// - 简体中文默认输出（zh-CN），无需简繁转换
/// - 天然跨 Apple 设备（iOS/macOS 统一框架）
///
/// 局限：需要网络；单次最长 1 分钟；有请求频率配额。
@MainActor
final class AppleSpeechService: ObservableObject {

    // MARK: - Published State

    /// 识别权限是否已授予
    @Published var isAuthorized: Bool = false

    /// 实时部分识别结果（流式）
    @Published var liveText: String = ""

    // MARK: - Private State

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isSessionActive = false

    // MARK: - 权限

    /// 请求语音识别权限（TCC）。
    /// - Returns: true 表示已授权
    func requestAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            isAuthorized = true
            return true
        case .notDetermined:
            // 注意：TCC 的 completion handler 在后台队列调用。
            // 不能在 handler 里直接 continuation.resume——resume 触发 MainActor
            // 隔离断言（_dispatch_assert_queue → swift_task_checkIsolatedSwift），
            // Swift 6.3 工具链下直接 SIGTRAP 崩溃（实测）。
            // 先跳到主队列再 resume：主队列即 MainActor 执行器，断言通过。
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    let authorized = (status == .authorized)
                    DispatchQueue.main.async {
                        continuation.resume(returning: authorized)
                    }
                }
            }
            isAuthorized = granted
            return granted
        case .denied, .restricted:
            Log.speech.warning("语音识别权限被拒绝")
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 会话

    /// 开始一个流式识别会话。
    ///
    /// - Parameter locale: 识别语言，默认取设置中的语言（默认简体中文）。
    /// - Returns: 音频缓冲区识别请求——调用方需把音频 buffer 持续 `append` 进来。
    /// - Throws: `SpeechServiceError.unavailable` 如果识别器不可用。
    func startSession(locale: Locale? = nil) throws -> SFSpeechAudioBufferRecognitionRequest {
        let effectiveLocale = locale ?? SpeechLanguageSettings.current.locale
        guard let recognizer = SFSpeechRecognizer(locale: effectiveLocale), recognizer.isAvailable else {
            Log.speech.error("SFSpeechRecognizer 不可用（locale: \(effectiveLocale.identifier)）")
            throw SpeechServiceError.unavailable
        }

        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true   // 流式部分结果
        request.taskHint = .dictation               // 听写场景优化

        self.recognitionRequest = request
        self.liveText = ""
        isSessionActive = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.liveText = result.bestTranscription.formattedString
                Log.speech.debug("部分识别: \"\(self.liveText)\"")
            }

            if let error {
                Log.speech.warning("识别回调错误: \(error.localizedDescription)")
            }

            if result?.isFinal == true {
                self.isSessionActive = false
            }
        }

        Log.speech.info("Apple 语音识别会话已开始（\(effectiveLocale.identifier)）")
        return request
    }

    /// 结束会话并返回最终识别文本。
    ///
    /// 内部等待最终结果落地（最多 3 秒），返回当前最佳文本。
    /// - Returns: 最终识别文本（可能为空字符串）。
    func finishSession() async -> String {
        guard isSessionActive else {
            let stale = liveText
            cleanup()
            return stale
        }

        // 标记音频结束，让识别器产出最终结果
        recognitionRequest?.endAudio()

        // 等待最终结果（轮询 liveText + isFinal 状态，最多 3 秒）
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            if !isSessionActive { break }
        }

        let final = liveText
        cleanup()
        Log.speech.info("识别会话结束，最终文本: \"\(final)\"")
        return final
    }

    /// 取消当前会话（用户放弃输入）。
    func cancelSession() {
        recognitionTask?.cancel()
        cleanup()
    }

    // MARK: - Cleanup

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        isSessionActive = false
    }
}

// MARK: - 错误

enum SpeechServiceError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "语音识别服务不可用（请检查网络或系统设置）"
        }
    }
}
