import SwiftUI

/// Settings window placeholder — will be fully implemented in Task 3.
/// This stub allows the app to compile with the Settings scene wired in VoiceTypeApp.
struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        TabView {
            Text("Settings")
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 500, height: 400)
    }
}
