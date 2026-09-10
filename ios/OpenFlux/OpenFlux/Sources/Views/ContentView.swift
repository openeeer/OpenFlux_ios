import SwiftUI
import UIKit

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
            EngineLogsView()
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .tint(.accentCore)
    }
}

private struct EngineLogsView: View {
    @State private var logs = ""
    @State private var copied = false

    private func refresh() {
        guard let pointer = OpenFluxCopyLogs() else { return }
        defer { OpenFluxFreeLogs(pointer) }
        let snapshot = String(cString: pointer)
        if snapshot != logs { logs = snapshot }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Логи Go")
                .font(.title.bold())
            Button {
                refresh()
                UIPasteboard.general.setItems(
                    [["public.utf8-plain-text": logs]],
                    options: [.localOnly: true]
                )
                copied = true
            } label: {
                Label(copied ? "Скопировано" : "Скопировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(minHeight: 44)
            }
            .disabled(logs.isEmpty)
            .onChange(of: logs) { _, _ in copied = false }
            Text("Последние 64 КБ за этот запуск приложения. Логи могут содержать ссылки и адреса — проверьте их перед отправкой.")
                .font(.footnote)
                .foregroundColor(.textSecondary)
            ScrollView {
                Text(logs.isEmpty ? "Пока нет записей. Нажмите Connect на вкладке Home." : logs)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.glassSurface)
        }
        .padding(20)
        .foregroundColor(.textPrimary)
        .background(Color.glassBase.ignoresSafeArea())
        .task {
            while !Task.isCancelled {
                refresh()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
        .preferredColorScheme(.dark)
}
