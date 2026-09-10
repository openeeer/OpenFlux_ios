import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionVM: ConnectionViewModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "shield.lefthalf.filled") }

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.accentCore)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
        .preferredColorScheme(.dark)
}
