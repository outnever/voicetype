import Foundation
import Logging
import OSLog

/// Centralized logging configuration for VoiceType.
/// Uses Apple's swift-log (Logger type) with OSLog backend.
/// Subsystem: com.voicetype.app
///
/// 日志双通道：
/// 1. OSLog（系统日志，`log show --predicate 'subsystem == "com.voicetype.app"'` 查看）
/// 2. 文件（`~/Library/Logs/VoiceType/voicetype.log`，方便排查问题）
enum Log {
    /// 初始化日志系统——在 App 启动时调用一次。
    /// 同时启用 OSLog + 文件日志双通道。
    static func enableFileLogging() {
        // 确保日志目录存在
        let logURL = fileLogURL
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 截断超过 5MB 的旧日志
        if let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int,
           size > 5_000_000 {
            try? FileManager.default.removeItem(at: logURL)
        }

        LoggingSystem.bootstrap { label in
            MultiplexLogHandler([
                OSLogHandler(subsystem: "com.voicetype.app", category: label),
                FileLogHandler(label: label, fileURL: logURL),
            ])
        }

        Log.app.info("文件日志已启用: \(logURL.path)")
    }

    /// 文件日志路径：~/Library/Logs/VoiceType/voicetype.log
    static var fileLogURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appending(path: "Logs/VoiceType/voicetype.log")
    }

    /// General application-level logger (lifecycle, state transitions, UI events)
    static let app = Logger(label: "com.voicetype.app")

    /// Hotkey subsystem logger (CGEvent tap registration, key events, watchdog)
    static let hotkey = Logger(label: "com.voicetype.app.hotkey")

    /// Audio subsystem logger (AVAudioEngine lifecycle, device changes, buffer stats)
    static let audio = Logger(label: "com.voicetype.app.audio")

    /// Settings subsystem logger (preferences, API key storage)
    static let settings = Logger(label: "com.voicetype.app.settings")

    /// Permission subsystem logger (TCC status checks, permission requests)
    static let permission = Logger(label: "com.voicetype.app.permission")

    /// Transcription subsystem logger (model download, WhisperKit inference, filler word removal)
    static let transcription = Logger(label: "com.voicetype.app.transcription")

    /// TextIO subsystem logger (AXUIElement writes, clipboard operations, fallback chains)
    static let textIO = Logger(label: "com.voicetype.app.textio")

    /// Apple speech recognition subsystem logger (SFSpeechRecognizer session lifecycle)
    static let speech = Logger(label: "com.voicetype.app.speech")
}

// MARK: - File Log Handler

/// 文件日志处理器——把日志写入指定文件（追加模式，线程安全）。
private struct FileLogHandler: LogHandler {
    let label: String
    let fileURL: URL
    private let lock = NSLock()

    var logLevel: Logging.Logger.Level = .info
    var metadata: Logging.Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // 格式化: [时间] [级别] [子系统] 消息
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let time = formatter.string(from: Date())

        let levelStr = String(describing: level).uppercased()
        let line = "[\(time)] [\(levelStr)] [\(label)] \(message.description)\n"

        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            // 文件不存在——创建
            try? line.data(using: .utf8)?.write(to: fileURL)
        }
    }
}

// MARK: - OSLog Handler

/// OSLog 处理器——把 swift-log 输出到系统日志。
private struct OSLogHandler: LogHandler {
    let subsystem: String
    let category: String
    private let logger: os.Logger

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    var logLevel: Logging.Logger.Level = .info
    var metadata: Logging.Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        switch level {
        case .trace, .debug:
            logger.debug("\(message.description, privacy: .public)")
        case .info, .notice:
            logger.info("\(message.description, privacy: .public)")
        case .warning:
            logger.warning("\(message.description, privacy: .public)")
        case .error, .critical:
            logger.fault("\(message.description, privacy: .public)")
        }
    }
}
