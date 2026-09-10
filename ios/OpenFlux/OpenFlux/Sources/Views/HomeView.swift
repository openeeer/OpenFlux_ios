import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vm: ConnectionViewModel
    @EnvironmentObject private var settings: SettingsViewModel
    @State private var copied = false

    private var endpoint: String { "127.0.0.1:\(vm.selectedConfig.socksPort)" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: vm.status == .connected ? "checkmark.shield.fill" : "shield")
                            .font(.system(size: 58, weight: .regular))
                            .foregroundStyle(vm.status == .connected ? .green : .accentColor)
                            .symbolEffect(.pulse, isActive: vm.status == .connecting)

                        VStack(spacing: 4) {
                            Text(vm.status.displayText)
                                .font(.title2.weight(.semibold))
                            Text(vm.status == .connected ? "SOCKS5 proxy is ready" : "Connect to start the local proxy")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                }

                Section {
                    PrimaryButton(
                        label: buttonLabel,
                        systemImage: buttonIcon,
                        color: vm.status == .connected ? .red : .accentColor,
                        action: vm.toggleConnection
                    )
                    .disabled(vm.status == .connecting || (!vm.canConnect && !vm.status.isActive))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("Local Proxy") {
                    HStack {
                        Label("SOCKS5 address", systemImage: "network")
                        Spacer()
                        Text(endpoint).font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.string = endpoint
                            copied = true
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy proxy address")
                    }

                    Label("This is a local proxy, not a system VPN", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Server") {
                    LabeledContent("Configuration", value: vm.selectedConfig.name)
                    LabeledContent("Transport", value: vm.selectedConfig.transport.displayName)
                    if vm.selectedConfig.docURL.isEmpty {
                        Label("Add a document URL in Settings", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if vm.isStubEngine {
                    Section {
                        Label("This build contains the stub engine and cannot connect.", systemImage: "wrench.and.screwdriver")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if case .error(let message) = vm.status {
                    Section("Connection Error") {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("OpenFlux")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .task { _ = settings.selectedConfig(updating: vm) }
            .onChange(of: copied) { _, value in
                if value { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false } }
            }
        }
    }

    private var buttonLabel: String {
        switch vm.status {
        case .connected: return "Stop Proxy"
        case .connecting: return "Starting…"
        case .disconnected: return "Start Proxy"
        case .error: return "Try Again"
        }
    }

    private var buttonIcon: String {
        vm.status == .connected ? "stop.fill" : "play.fill"
    }
}

#Preview {
    HomeView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
}
