import Testing
import Foundation
@testable import VoiceType
import WhisperKit

/// Task 1 tests for ModelDownloadManager, TranscriptionError, and filler word removal.

@Suite("ModelDownloadManager — Model State & Error Types")
struct ModelDownloadManagerTests {

    // MARK: - ModelState transitions (pure enum tests — no @MainActor needed)

    @Test("ModelState transitions to downloading with progress")
    func downloadingStateHasProgress() {
        let downloading = ModelDownloadManager.ModelState.downloading(progress: 0.5)
        switch downloading {
        case .downloading(let progress):
            #expect(progress == 0.5)
        default:
            #expect(Bool(false), "Expected .downloading state")
        }
    }

    @Test("ModelState ready is equatable")
    func readyStateExists() {
        #expect(ModelDownloadManager.ModelState.ready == .ready)
    }

    @Test("ModelState error carries message")
    func errorStateCarriesMessage() {
        let errorState = ModelDownloadManager.ModelState.error("网络错误")
        switch errorState {
        case .error(let message):
            #expect(message == "网络错误")
        default:
            #expect(Bool(false), "Expected .error state")
        }
    }

    // MARK: - ModelState Equatable

    @Test("ModelState Equatable — ready equals ready")
    func equatableReady() {
        #expect(ModelDownloadManager.ModelState.ready == ModelDownloadManager.ModelState.ready)
    }

    @Test("ModelState Equatable — downloading with same progress")
    func equatableDownloading() {
        #expect(
            ModelDownloadManager.ModelState.downloading(progress: 0.3)
            == ModelDownloadManager.ModelState.downloading(progress: 0.3)
        )
    }

    @Test("ModelState Equatable — different downloading progress not equal")
    func downloadingDifferentProgressNotEqual() {
        #expect(
            ModelDownloadManager.ModelState.downloading(progress: 0.3)
            != ModelDownloadManager.ModelState.downloading(progress: 0.7)
        )
    }

    @Test("ModelState Equatable — different states not equal")
    func differentStatesNotEqual() {
        #expect(ModelDownloadManager.ModelState.notLoaded != ModelDownloadManager.ModelState.ready)
    }

    // MARK: - @MainActor tests (require ModelDownloadManager instance)

    @Test("ModelState starts as notLoaded") @MainActor
    func initialStateIsNotLoaded() {
        let manager = ModelDownloadManager()
        #expect(manager.modelState == .notLoaded)
    }

    // MARK: - TranscriptionError

    @Test("TranscriptionError enum has all 4 cases")
    func transcriptionErrorCases() {
        let e1 = TranscriptionError.modelNotDownloaded
        let e2 = TranscriptionError.modelDownloadFailed(underlying: NSError(domain: "test", code: 1))
        let e3 = TranscriptionError.transcriptionFailed(underlying: NSError(domain: "test", code: 2))
        let e4 = TranscriptionError.audioTooShort

        #expect(e1.localizedDescription.count > 0)
        #expect(e2.localizedDescription.count > 0)
        #expect(e3.localizedDescription.count > 0)
        #expect(e4.localizedDescription.count > 0)
    }

    @Test("TranscriptionError.modelNotDownloaded has Chinese description")
    func modelNotDownloadedChineseDescription() {
        let error = TranscriptionError.modelNotDownloaded
        #expect(error.localizedDescription.contains("模型"))
    }

    @Test("TranscriptionError.audioTooShort has Chinese description")
    func audioTooShortChineseDescription() {
        let error = TranscriptionError.audioTooShort
        #expect(error.localizedDescription.contains("音频"))
    }

    // MARK: - Filler Word Removal

    @Test("removeFillerWords removes Chinese filler 呃 and 嗯")
    func removeChineseFillers() {
        let input = "呃 那个 我觉得 嗯 就是 这样"
        let result = removeFillerWords(from: input)
        #expect(!result.contains("呃"))
        #expect(!result.contains("嗯"))
    }

    @Test("removeFillerWords removes English filler um and uh")
    func removeEnglishFillers() {
        let input = "um this is uh a test"
        let result = removeFillerWords(from: input)
        #expect(!result.lowercased().contains("um"))
        #expect(!result.lowercased().contains("uh"))
    }

    @Test("removeFillerWords preserves normal text")
    func preservesNormalText() {
        let input = "你好 世界 hello world"
        let result = removeFillerWords(from: input)
        #expect(result.contains("你好"))
        #expect(result.contains("world"))
    }

    @Test("removeFillerWords trims whitespace")
    func trimsWhitespace() {
        let input = "  测试  "
        let result = removeFillerWords(from: input)
        #expect(result == "测试")
    }

    @Test("removeFillerWords collapses multiple spaces")
    func collapsesMultipleSpaces() {
        let input = "hello    world"
        let result = removeFillerWords(from: input)
        #expect(result == "hello world")
    }
}
