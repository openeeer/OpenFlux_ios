import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var vm: ConnectionViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Traffic") {
                    StatTile(label: "Downloaded", value: vm.stats.formattedBytesIn, systemImage: "arrow.down.circle.fill", color: .green)
                    StatTile(label: "Uploaded", value: vm.stats.formattedBytesOut, systemImage: "arrow.up.circle.fill", color: .blue)
                }

                Section("Session") {
                    LabeledContent("Status", value: vm.status.displayText)
                    LabeledContent("Uptime", value: vm.stats.uptime)
                    LabeledContent("Transport", value: vm.selectedConfig.transport.displayName)
                }

                Section("Local Proxy") {
                    LabeledContent("Protocol", value: "SOCKS5")
                    LabeledContent("Address", value: "127.0.0.1:\(vm.selectedConfig.socksPort)")
                }

                Section {
                    Text("Only apps that support a manual SOCKS5 proxy can use this connection. OpenFlux does not route all iPhone traffic.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(ConnectionViewModel())
}
