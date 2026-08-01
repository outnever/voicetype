import AppKit

/// 录音提示音管理。
///
/// - 开始录音：短"嘀"（上扬音效）
/// - 结束录音：短"嘀"（低沉音效）
/// - 纠错完成：柔和提示
///
/// 使用系统内置音效（NSSound），无需额外资源文件。
enum SoundManager {

    /// 开始录音提示。
    static func playStartSound() {
        // "Pop" 或 "Tink"——轻快上扬
        NSSound(named: "Tink")?.play()
    }

    /// 结束录音提示。
    static func playStopSound() {
        // "Pop"——短促
        NSSound(named: "Pop")?.play()
    }

    /// 纠错完成提示。
    static func playCompleteSound() {
        NSSound(named: "Glass")?.play()
    }

    /// 错误提示。
    static func playErrorSound() {
        NSSound(named: "Sosumi")?.play()
    }
}
