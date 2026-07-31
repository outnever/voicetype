import Foundation
@preconcurrency import WhisperKit

// MARK: - Model Download Manager

/// Manages the WhisperKit model lifecycle: async download from HuggingFace,
/// caching in memory, and exposing reactive state for UI observation.
///
/// Architecture (per CONTEXT.md D-01 through D-04, RESEARCH.md):
/// - All WhisperKit config/loading happens in `Task.detached` — never blocks @MainActor.
/// - The `@Published modelState` allows UI to observe progress without blocking.
/// - Cached `pipe` instance is reused for all transcription calls (D-03).
/// - Model downloads automatically from HuggingFace on first launch (D-02).
@MainActor
final class ModelDownloadManager: ObservableObject {

    // MARK: - Published State

    /// Observable model lifecycle state for UI-driven status display.
    @Published var modelState: ModelState = .notLoaded

    // MARK: - Private State

    /// Cached WhisperKit pipe instance — loaded once, reused for all transcriptions.
    private var pipe: WhisperKit?

    // MARK: - Model State

    /// Represents the lifecycle of the WhisperKit model.
    enum ModelState: Equatable {
        /// No model has been loaded yet — app just launched.
        case notLoaded
        /// Model files are being downloaded from HuggingFace.
        /// - Parameter progress: Download progress fraction (0.0 to 1.0).
        case downloading(progress: Double)
        /// Model has been downloaded and is being loaded into memory / specialized for this device.
        /// - Parameter message: Human-readable status for UI display.
        case loading(String)
        /// Model is fully loaded and ready for transcription.
        case ready
        /// An error occurred during download or loading.
        /// - Parameter message: Human-readable error description for UI display.
        case error(String)
    }

    // MARK: - Initialization

    /// 使用 HuggingFace 镜像下载模型（国内可直连，无需翻墙）。
    /// hf-mirror.com 是 HuggingFace 官方认可的镜像站。
    private static let hfMirrorURL = "https://hf-mirror.com"

    /// 开发默认使用 tiny 模型（75MB）——下载快、够测试。
    /// 生产环境切换为 "openai_whisper-large-v3-v20240930_626MB"。
    private static let devModelName = "openai_whisper-tiny"

    /// 下载并加载 WhisperKit 模型。
    ///
    /// - Parameter modelName: HuggingFace 模型标识。
    /// - Note: 通过 HF_ENDPOINT 环境变量指向 hf-mirror.com，国内可直连。
    func initialize(modelName: String = ModelDownloadManager.devModelName) async {
        // Guard against duplicate calls — if already downloading or ready, skip.
        switch modelState {
        case .ready, .downloading:
            Log.transcription.info("ModelDownloadManager: already \(modelState) — skipping initialize()")
            return
        default:
            break
        }

        Log.transcription.info("ModelDownloadManager: starting model initialization for \(modelName)")
        modelState = .loading("正在准备语音模型…")

        do {
            let newPipe = try await Task.detached(priority: .userInitiated) {
                Log.transcription.info("WhisperKit: initializing with model \(modelName)")

                // 通过 modelEndpoint 指定 HuggingFace 镜像（国内可直连，无需翻墙）
                let config = WhisperKitConfig(
                    model: modelName,
                    modelEndpoint: ModelDownloadManager.hfMirrorURL,
                    verbose: false,
                    logLevel: .error,
                    download: true
                )
                let pipe = try await WhisperKit(config)
                Log.transcription.info("WhisperKit: model initialized successfully — \(modelName)")
                return pipe
            }.value

            self.pipe = newPipe
            self.modelState = .ready
            Log.transcription.info("ModelDownloadManager: model ready — pipe cached for transcription")

        } catch {
            Log.transcription.error("ModelDownloadManager: model initialization failed — \(error.localizedDescription)")
            self.modelState = .error(error.localizedDescription)
        }
    }

    // MARK: - Pipe Access

    /// Returns the cached WhisperKit pipe, or `nil` if the model hasn't been loaded yet.
    ///
    /// Used by `TranscriptionService` to access the shared pipe instance.
    func getPipe() -> WhisperKit? {
        return pipe
    }
}

// MARK: - Filler Word Removal

/// Removes common Chinese and English filler words from transcribed text.
///
/// WhisperKit's large-v3 model handles most filler word suppression natively (D-16, DICT-05).
/// This regex is a post-filter for edge cases — it does NOT over-aggressively filter
/// common English words like "like" to avoid false positives in legitimate use.
///
/// - Parameter text: The raw transcribed text from WhisperKit.
/// - Returns: Cleaned text with filler words removed, double spaces collapsed, and whitespace trimmed.
func removeFillerWords(from text: String) -> String {
    var result = text

    let fillerPatterns: [(pattern: String, replacement: String)] = [
        // Chinese fillers
        ("\\b呃+\\b", ""),
        ("\\b嗯+\\b", ""),
        ("\\b那个\\b", ""),
        ("\\b就是\\b", ""),
        // English fillers (conservative — like is NOT filtered due to high false-positive rate)
        ("\\bum\\b", ""),
        ("\\buh\\b", ""),
        ("\\byou know\\b", ""),
    ]

    for (pattern, replacement) in fillerPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }
    }

    // Clean up double spaces and trim
    result = result.replacingOccurrences(
        of: "\\s{2,}",
        with: " ",
        options: .regularExpression
    )
    return result.trimmingCharacters(in: .whitespaces)
}
