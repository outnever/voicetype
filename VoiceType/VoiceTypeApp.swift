import SwiftUI

/// Minimal placeholder entry point for Task 1 skeleton build.
/// Will be replaced with full implementation in Task 2.
@main
struct VoiceTypeApp: App {
    var body: some Scene {
        MenuBarExtra("VoiceType", systemImage: "mic.fill") {
            Text("VoiceType")
        }
        .menuBarExtraStyle(.menu)
    }
}
