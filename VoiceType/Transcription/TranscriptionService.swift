import Foundation
@preconcurrency import WhisperKit

// MARK: - Transcription Service

/// Wraps WhisperKit for offline speech-to-text transcription.
///
/// Architecture:
/// - Does NOT own pipe creation — delegates to `ModelDownloadManager` (D-03).
/// - `transcribe(audioArray:)` runs Whisper inference in `Task.detached` (PITFALLS.md §7, §12).
/// - Applies filler word removal post-processing (D-16, DICT-05).
/// - Auto-detects Chinese/English via `detectLanguage: true` (D-14).
/// - Uses WhisperKit built-in VAD via `chunkingStrategy: .vad` (D-05).
@MainActor
final class TranscriptionService: ObservableObject {

    // MARK: - Dependencies

    /// Reference to the shared ModelDownloadManager holding the cached WhisperKit pipe.
    private let modelDownloadManager: ModelDownloadManager

    // MARK: - Initialization

    init(modelDownloadManager: ModelDownloadManager) {
        self.modelDownloadManager = modelDownloadManager
        Log.transcription.info("TranscriptionService initialized")
    }

    // MARK: - Transcription

    /// Transcribes a Float32 mono 16kHz audio array to text.
    ///
    /// - Parameter audioArray: Float32 PCM samples from AudioCaptureService RingBuffer.
    /// - Returns: Punctuated, filler-word-filtered text string.
    /// - Throws: `.modelNotDownloaded` if model isn't ready, `.audioTooShort` if <300ms,
    ///           `.transcriptionFailed` on WhisperKit inference error.
    func transcribe(audioArray: [Float]) async throws -> String {
        // Guard: model must be loaded
        guard let pipe = modelDownloadManager.getPipe() else {
            throw TranscriptionError.modelNotDownloaded
        }

        // Guard: minimum 300ms audio (PITFALLS.md §2)
        let minimumSamples = Int(AudioConstants.sampleRate * 0.3)  // 4800 samples at 16kHz
        guard audioArray.count >= minimumSamples else {
            throw TranscriptionError.audioTooShort
        }

        let startTime = Date()
        Log.transcription.info("TranscriptionService: transcribing \(audioArray.count) samples (\(Float(audioArray.count) / Float(AudioConstants.sampleRate))s)")

        // Run Whisper inference in Task.detached to avoid blocking the main thread
        // (PITFALLS.md §7, §12). WhisperKit is not Sendable, but @preconcurrency
        // suppresses the warning — the pipe is accessed only from the detached task.
        let resultText: String
        do {
            let results = try await Task.detached(priority: .userInitiated) { () throws -> [TranscriptionResult] in
                let options = DecodingOptions(
                    task: .transcribe,
                    detectLanguage: true,        // D-14: auto-detect Chinese/English
                    skipSpecialTokens: true,
                    chunkingStrategy: .vad      // D-05: built-in VAD segmentation
                )

                Log.transcription.info("WhisperKit: starting transcription with VAD chunking")

                return try await pipe.transcribe(
                    audioArray: audioArray,
                    decodeOptions: options
                )
            }.value

            // Join all segment texts
            let rawText = results.map { $0.text }.joined(separator: "")
            Log.transcription.info("WhisperKit: transcription complete — \(results.count) segments, \(rawText.count) chars")
            resultText = rawText
        } catch {
            Log.transcription.error("TranscriptionService: inference failed — \(error.localizedDescription)")
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }

        // Post-process: remove filler words
        let cleanedText = removeFillerWords(from: resultText)

        let duration = Date().timeIntervalSince(startTime)
        Log.transcription.info("TranscriptionService: transcription finished — \(cleanedText.count) chars in \(String(format: "%.2f", duration))s")

        return cleanedText
    }
}
