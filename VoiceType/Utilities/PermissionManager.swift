import AVFoundation
import ApplicationServices
import Foundation
import Speech

/// Manages macOS TCC (Transparency, Consent, and Control) permission status for
/// microphone, speech recognition, and accessibility. Publishes status changes
/// via @Published for UI binding.
///
/// Permissions are checked sequentially per D-07 decision: microphone first (with
/// user-facing explanation), then accessibility (requiring manual System Settings
/// navigation). AXIsProcessTrusted() requires polling due to lack of callback.
@MainActor
final class PermissionManager: ObservableObject {
    @Published var microphoneGranted: Bool = false
    @Published var accessibilityGranted: Bool = false

    /// 语音识别权限（Apple SFSpeechRecognizer）——纠错指令识别需要。
    @Published var speechRecognitionGranted: Bool = false
    @Published var speechRecognitionStatus: String = "未请求"

    /// Pre-configured polling timer for accessibility permission.
    /// AXIsProcessTrusted() has no notification callback — we must poll.
    private var pollingTimer: Timer?

    /// Both permissions granted — application is fully authorized.
    var allPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    /// D-08: Evaluate the aggregate permission status for menu bar icon color.
    var permissionStatus: PermissionStatus {
        .evaluate(mic: microphoneGranted, ax: accessibilityGranted)
    }

    // MARK: - Microphone Permission

    /// Request microphone permission via AVFoundation TCC dialog.
    /// If already authorized, returns true immediately without prompting.
    /// If denied/restricted, returns false — user must enable in System Settings.
    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGranted = true
            Log.permission.info("Microphone permission already authorized")
            return true
        case .notDetermined:
            Log.permission.info("Requesting microphone permission")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneGranted = granted
            Log.permission.info("Microphone permission response: \(granted ? "granted" : "denied")")
            return granted
        case .denied, .restricted:
            microphoneGranted = false
            Log.permission.warning("Microphone permission denied or restricted")
            return false
        @unknown default:
            Log.permission.warning("Unknown microphone authorization status: \(status.rawValue)")
            return false
        }
    }

    // MARK: - Accessibility Permission

    /// Check current accessibility permission status.
    /// Returns the result of AXIsProcessTrusted() — the single source of truth
    /// for accessibility trust on macOS. Only logs on state change to avoid spam.
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        let previous = accessibilityGranted
        accessibilityGranted = trusted
        if trusted && !previous {
            Log.permission.info("辅助功能权限已获取")
        } else if !trusted && previous {
            Log.permission.warning("辅助功能权限已丢失")
        }
        return trusted
    }

    /// Start polling AXIsProcessTrusted() at the given interval.
    /// Accessibility permission has NO callback mechanism on macOS — polling is
    /// the only way to detect when the user enables it in System Settings.
    ///
    /// Call this after directing the user to System Settings > Privacy > Accessibility.
    func startAccessibilityPolling(interval: TimeInterval = 2.0) {
        pollingTimer?.invalidate()
        Log.permission.info("开始轮询辅助功能权限（每 \(interval) 秒）")
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.checkAccessibilityPermission()
                if self.accessibilityGranted {
                    self.stopAccessibilityPolling()
                }
            }
        }
    }

    /// Stop polling (e.g., when permission is granted or user dismisses the flow).
    func stopAccessibilityPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        Log.permission.info("辅助功能轮询已停止")
    }

    // MARK: - Initial Status Check

    /// Synchronously check all current permission statuses.
    /// Called during AppCoordinator initialization on a background task.
    func refreshAllStatuses() {
        // Microphone: check status synchronously (AVCaptureDevice.authorizationStatus is instant)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = (micStatus == .authorized)
        Log.permission.info("初始麦克风状态: \(micStatus.rawValue)")

        // Accessibility: AXIsProcessTrusted() is also synchronous
        accessibilityGranted = AXIsProcessTrusted()
        Log.permission.info("初始辅助功能状态: \(accessibilityGranted ? "已授权" : "未授权")")

        refreshSpeechStatus()
    }

    // MARK: - Speech Recognition Permission

    /// 刷新语音识别权限状态（SFSpeechRecognizer，同步查询）。
    func refreshSpeechStatus() {
        let status = SFSpeechRecognizer.authorizationStatus()
        speechRecognitionGranted = (status == .authorized)
        switch status {
        case .authorized:
            speechRecognitionStatus = "已授权"
        case .denied:
            speechRecognitionStatus = "已拒绝"
        case .restricted:
            speechRecognitionStatus = "受限"
        case .notDetermined:
            speechRecognitionStatus = "未请求"
        @unknown default:
            speechRecognitionStatus = "未知"
        }
    }

    /// 请求语音识别权限——内部使用 AppleSpeechService 的非隔离调用（避免 Swift 6 隔离断言崩溃）。
    /// - Returns: true 表示已授权
    func requestSpeechRecognitionPermission() async -> Bool {
        let granted = await AppleSpeechService.requestSpeechAuthorizationFromTCC()
        refreshSpeechStatus()
        Log.permission.info("语音识别权限请求结果: \(granted ? "granted" : "denied")")
        return granted
    }
}

// MARK: - Permission Status Model (D-08)

/// Aggregate permission status used to derive icon color in the menu bar.
/// - Green (allGranted): user can use all features
/// - Orange (partial): one permission is missing — app is partially functional
/// - Red (noneGranted): both permissions are missing — app cannot function
enum PermissionStatus {
    case allGranted
    case partial
    case noneGranted

    /// D-08: Color coding for menu bar icon — human-readable status.
    var iconColor: String {
        switch self {
        case .allGranted:  return "green"
        case .partial:     return "orange"
        case .noneGranted: return "red"
        }
    }

    /// Evaluate aggregate status from individual permission booleans.
    static func evaluate(mic: Bool, ax: Bool) -> PermissionStatus {
        switch (mic, ax) {
        case (true, true):   return .allGranted
        case (false, false): return .noneGranted
        default:             return .partial
        }
    }
}
