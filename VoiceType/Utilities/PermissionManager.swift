import AVFoundation
import ApplicationServices
import Foundation

/// Manages macOS TCC (Transparency, Consent, and Control) permission status for
/// microphone and accessibility. Publishes status changes via @Published for UI binding.
///
/// Permissions are checked sequentially per D-07 decision: microphone first (with
/// user-facing explanation), then accessibility (requiring manual System Settings
/// navigation). AXIsProcessTrusted() requires polling due to lack of callback.
@MainActor
final class PermissionManager: ObservableObject {
    @Published var microphoneGranted: Bool = false
    @Published var accessibilityGranted: Bool = false

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
    /// for accessibility trust on macOS.
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        accessibilityGranted = trusted
        if trusted {
            Log.permission.info("Accessibility permission granted")
        } else {
            Log.permission.warning("Accessibility permission not granted")
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
        Log.permission.info("Starting accessibility polling every \(interval)s")
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibilityPermission()
            }
        }
    }

    /// Stop polling (e.g., when permission is granted or user dismisses the flow).
    func stopAccessibilityPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        Log.permission.info("Accessibility polling stopped")
    }

    // MARK: - Initial Status Check

    /// Synchronously check all current permission statuses.
    /// Called during AppCoordinator initialization on a background task.
    func refreshAllStatuses() {
        // Microphone: check status synchronously (AVCaptureDevice.authorizationStatus is instant)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        microphoneGranted = (micStatus == .authorized)
        Log.permission.info("Initial microphone status: \(micStatus.rawValue)")

        // Accessibility: AXIsProcessTrusted() is also synchronous
        accessibilityGranted = AXIsProcessTrusted()
        Log.permission.info("Initial accessibility status: \(accessibilityGranted ? "trusted" : "not trusted")")
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
