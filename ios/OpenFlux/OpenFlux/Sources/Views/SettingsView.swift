import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var vm: ConnectionViewModel
    @EnvironmentObject private var settings: SettingsViewModel

    @State private var editingConfig: ServerConfig?
    @State private var showAddSheet = false

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CONFIG")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .tracking(3.2)
                                .foregroundColor(.accentCore)
                            Text("Servers")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.accentCore)
                                .clipShape(Circle())
                                .shadow(color: Color.accentGlow, radius: 10, y: 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add server")
                    }
                    .padding(.top, 8)

                    // ── Server list ───────────────────────────
                    VStack(spacing: 12) {
                        ForEach(settings.configs) { cfg in
                            ServerRow(
                                config: cfg,
                                isSelected: cfg.id == activeID,
                                onSelect: {
                                    settings.selectedID = cfg.id
                                    settings.save()
                                    vm.selectedConfig = cfg
                                },
                                onEdit: { editingConfig = cfg },
                                onDelete: {
                                    if let idx = settings.configs.firstIndex(where: { $0.id == cfg.id }) {
                                        settings.removeConfig(at: IndexSet(integer: idx))
                                    }
                                }
                            )
                        }
                    }

                    // ── Transport picker ──────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TRANSPORT BACKEND")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundColor(.textSecondary)

                        HStack(spacing: 10) {
                            ForEach(ServerConfig.TransportType.allCases, id: \.self) { t in
                                Button {
                                    var cfg = vm.selectedConfig
                                    cfg.transport = t
                                    vm.selectedConfig = cfg
                                    settings.updateConfig(cfg)
                                } label: {
                                    Text(t.displayName)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(
                                            vm.selectedConfig.transport == t ? .white : .textSecondary
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(
                                            vm.selectedConfig.transport == t
                                                ? Color.accentCore
                                                : Color.glassRaised
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.glassBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .liquidGlassCard()

                    // ── About ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ABOUT")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundColor(.textSecondary)
                            .padding(.bottom, 12)

                        AboutRow(label: "Version", value: Bundle.main.appVersion)
                        Divider().overlay(Color.glassBorder)
                        AboutRow(label: "Build", value: Bundle.main.buildNumber)
                        Divider().overlay(Color.glassBorder)
                        AboutRow(label: "License", value: "GPL-3.0")
                    }
                    .liquidGlassCard()

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ConfigEditorSheet(config: nil) { newConfig in
                settings.addConfig(newConfig)
                settings.selectedID = newConfig.id
                settings.save()
                vm.selectedConfig = newConfig
            }
        }
        .sheet(item: $editingConfig) { cfg in
            ConfigEditorSheet(config: cfg) { updated in
                settings.updateConfig(updated)
                if settings.selectedID == updated.id {
                    vm.selectedConfig = updated
                }
            }
        }
    }

    private var activeID: UUID? {
        settings.selectedID ?? settings.configs.first?.id
    }
}

// MARK: - Server row

private struct ServerRow: View {
    let config: ServerConfig
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentCore : Color.glassRaised)
                    .frame(width: 40, height: 40)
                Image(systemName: isSelected ? "checkmark" : "server.rack")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isSelected ? .white : .textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(config.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text(config.docURL.isEmpty ? "No URL" : config.docURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(config.docURL.isEmpty ? .danger : .textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Menu {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(14)
        .background(
            ZStack {
                Color.glassSurface
                if isSelected {
                    LinearGradient(
                        colors: [Color.accentCore.opacity(0.16), Color.clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentCore.opacity(0.5) : Color.glassBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

private struct AboutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Config editor

struct ConfigEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let config: ServerConfig?
    let onSave: (ServerConfig) -> Void

    @State private var name: String = ""
    @State private var docURL: String = ""
    @State private var port: String = "1080"
    @State private var transport: ServerConfig.TransportType = .yandex
    @State private var showValidation = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        URL(string: docURL) != nil &&
        (Int(port) ?? 0) > 0 && (Int(port) ?? 0) < 65536
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        FieldGroup(title: "NAME", placeholder: "My Server", text: $name)
                        FieldGroup(
                            title: "DOCUMENT URL",
                            placeholder: "https://disk.yandex.ru/i/...",
                            text: $docURL,
                            keyboard: .URL
                        )
                        FieldGroup(
                            title: "SOCKS5 PORT",
                            placeholder: "1080",
                            text: $port,
                            keyboard: .numberPad
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("TRANSPORT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.6)
                                .foregroundColor(.textSecondary)

                            HStack(spacing: 10) {
                                ForEach(ServerConfig.TransportType.allCases, id: \.self) { t in
                                    Button {
                                        transport = t
                                    } label: {
                                        Text(t.displayName)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(transport == t ? .white : .textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 11)
                                            .background(transport == t ? Color.accentCore : Color.glassRaised)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .liquidGlassCard()

                        if showValidation && !isValid {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Check name, URL and port")
                                    .font(.system(size: 12, design: .rounded))
                                Spacer()
                            }
                            .foregroundColor(.danger)
                            .liquidGlassInner()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(config == nil ? "New Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard isValid else { showValidation = true; return }
                        var result = config ?? ServerConfig(
                            name: name, docURL: docURL,
                            socksPort: Int(port) ?? 1080, transport: transport
                        )
                        result.name = name.trimmingCharacters(in: .whitespaces)
                        result.docURL = docURL
                        result.socksPort = Int(port) ?? 1080
                        result.transport = transport
                        onSave(result)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.accentCore)
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let c = config {
                name = c.name
                docURL = c.docURL
                port = String(c.socksPort)
                transport = c.transport
            }
        }
    }
}

private struct FieldGroup: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundColor(.textSecondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.glassRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.glassBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Bundle helpers

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    var buildNumber: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}

#Preview {
    SettingsView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
        .preferredColorScheme(.dark)
}
