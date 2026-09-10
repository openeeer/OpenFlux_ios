import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Connection", systemImage: "shield") }
            StatsView().tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
            EngineLogsView().tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .tint(.accentColor)
    }
}

private struct EngineLogsView: View {
    @State private var logs = ""
    @State private var copied = false

    private func refresh() {
        guard let pointer = OpenFluxCopyLogs() else { return }
        defer { OpenFluxFreeLogs(pointer) }
        logs = String(cString: pointer)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        refresh()
                        UIPasteboard.general.string = logs
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Logs", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(logs.isEmpty)
                }
                Section("Engine Output") {
                    Text(logs.isEmpty ? "No logs yet. Start the proxy from Connection." : logs)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                Section {
                    Text("Logs may contain URLs or server details. Review them before sharing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .task {
                while !Task.isCancelled {
                    refresh()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
}
