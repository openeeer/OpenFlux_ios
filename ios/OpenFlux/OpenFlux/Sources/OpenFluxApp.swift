import SwiftUI

@main
struct OpenFluxApp: App {
    @StateObject private var connectionVM = ConnectionViewModel()
    @StateObject private var settingsVM = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionVM)
                .environmentObject(settingsVM)
                .preferredColorScheme(.dark)
        }
    }
}
