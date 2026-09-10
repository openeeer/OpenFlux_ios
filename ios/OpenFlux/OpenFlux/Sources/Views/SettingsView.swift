import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: ConnectionViewModel
    @EnvironmentObject private var settings: SettingsViewModel
    @State private var editingConfig: ServerConfig?
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(settings.configs) { config in
                        Button {
                            settings.selectedID = config.id
                            settings.save()
                            vm.selectedConfig = config
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: config.id == activeID ? "checkmark.circle.fill" : "server.rack")
                                    .foregroundStyle(config.id == activeID ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(config.name).foregroundStyle(.primary)
                                    Text(config.docURL.isEmpty ? "No document URL" : config.docURL)
                                        .font(.caption).foregroundStyle(config.docURL.isEmpty ? .orange : .secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { delete(config) } label: { Label("Delete", systemImage: "trash") }
                            Button { editingConfig = config } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                        }
                    }
                    .onDelete { settings.removeConfig(at: $0) }
                } header: { Text("Servers") } footer: { Text("Select the server used by the local SOCKS5 proxy.") }
                Section("Transport") {
                    Picker("Backend", selection: transportBinding) {
                        ForEach(ServerConfig.TransportType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    LabeledContent("Build", value: Bundle.main.buildNumber)
                    LabeledContent("License", value: "GPL-3.0")
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.large).listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add server")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) { ConfigEditorSheet(config: nil) { config in
            settings.addConfig(config); settings.selectedID = config.id; settings.save(); vm.selectedConfig = config
        }}
        .sheet(item: $editingConfig) { config in ConfigEditorSheet(config: config) { updated in
            settings.updateConfig(updated); if settings.selectedID == updated.id { vm.selectedConfig = updated }
        }}
    }

    private var activeID: UUID? { settings.selectedID ?? settings.configs.first?.id }
    private var transportBinding: Binding<ServerConfig.TransportType> {
        Binding(get: { vm.selectedConfig.transport }, set: { value in vm.selectedConfig.transport = value; settings.updateConfig(vm.selectedConfig) })
    }
    private func delete(_ config: ServerConfig) {
        guard let index = settings.configs.firstIndex(where: { $0.id == config.id }) else { return }
        settings.removeConfig(at: IndexSet(integer: index))
    }
}

struct ConfigEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let config: ServerConfig?
    let onSave: (ServerConfig) -> Void
    @State private var name = ""
    @State private var docURL = ""
    @State private var port = "1080"
    @State private var transport: ServerConfig.TransportType = .yandex
    @State private var showValidation = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && NetworkManager.validatedURL(docURL) != nil && (1...65535).contains(Int(port) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name", text: $name)
                    TextField("Document URL", text: $docURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("SOCKS5 port", text: $port).keyboardType(.numberPad)
                }
                Section("Transport") {
                    Picker("Backend", selection: $transport) { ForEach(ServerConfig.TransportType.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                }
                if showValidation && !isValid { Section { Label("Enter an HTTPS document URL and a valid port.", systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
            }
            .navigationTitle(config == nil ? "New Server" : "Edit Server").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard isValid else { showValidation = true; return }
                        var result = config ?? ServerConfig(name: name, docURL: docURL, socksPort: Int(port) ?? 1080, transport: transport)
                        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines); result.docURL = docURL.trimmingCharacters(in: .whitespacesAndNewlines); result.socksPort = Int(port) ?? 1080; result.transport = transport
                        onSave(result); dismiss()
                    }.disabled(!isValid)
                }
            }
        }
        .onAppear { guard let config else { return }; name = config.name; docURL = config.docURL; port = String(config.socksPort); transport = config.transport }
    }
}

extension Bundle {
    var appVersion: String { (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0" }
    var buildNumber: String { (infoDictionary?["CFBundleVersion"] as? String) ?? "1" }
}

#Preview { SettingsView().environmentObject(ConnectionViewModel()).environmentObject(SettingsViewModel()) }
