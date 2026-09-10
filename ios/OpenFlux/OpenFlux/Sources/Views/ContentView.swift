import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Connection", systemImage: "shield") }
            StatsView()
                .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.accentColor)
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
}
