import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var vm: ConnectionViewModel
    @EnvironmentObject private var settings: SettingsViewModel

    @State private var ringRotation: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {

                    // ── Header ────────────────────────────────
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OPENFLUX")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .tracking(3.2)
                                .foregroundColor(.accentCore)
                            Text("Secure Tunnel")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        StatusPill(status: vm.status)
                    }
                    .padding(.top, 8)

                    // ── Big connect orb ───────────────────────
                    ConnectOrb(
                        status: vm.status,
                        rotation: $ringRotation,
                        pulse: $pulse
                    )
                    .frame(height: 290)

                    // ── Server info ───────────────────────────
                    ServerInfoCard(config: vm.selectedConfig)

                    if vm.isStubEngine {
                        HStack(spacing: 10) {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(.warning)
                            Text("Engine stub build — no Go tunnel linked. See ios/README.md.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.textSecondary)
                            Spacer()
                        }
                        .liquidGlassInner()
                    }

                    // ── Action button ─────────────────────────
                    PrimaryButton(
                        label: buttonLabel,
                        systemImage: buttonIcon,
                        color: buttonColor
                    ) {
                        vm.toggleConnection()
                    }
                    .disabled(!vm.canConnect && !vm.status.isActive)
                    .opacity(!vm.canConnect && !vm.status.isActive ? 0.5 : 1)

                    // ── Quick stats strip ─────────────────────
                    if vm.status.isActive {
                        HStack(spacing: 12) {
                            StatTile(
                                label: "DOWN",
                                value: vm.stats.formattedBytesIn,
                                systemImage: "arrow.down.circle.fill",
                                color: .success
                            )
                            StatTile(
                                label: "UP",
                                value: vm.stats.formattedBytesOut,
                                systemImage: "arrow.up.circle.fill",
                                color: .accentCore
                            )
                            StatTile(
                                label: "PING",
                                value: String(format: "%.0f ms", vm.stats.latencyMs),
                                systemImage: "waveform.path.ecg",
                                color: .warning
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if case .error(let msg) = vm.status {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.danger)
                            Text(msg)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.textSecondary)
                            Spacer()
                        }
                        .liquidGlassInner()
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: vm.status)
            }
        }
        .onAppear {
            _ = settings.selectedConfig(updating: vm)
        }
    }

    private var buttonLabel: String {
        switch vm.status {
        case .connected:    return "Disconnect"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Connect"
        case .error:        return "Retry"
        }
    }

    private var buttonIcon: String {
        switch vm.status {
        case .connected:    return "stop.fill"
        case .connecting:   return "hourglass"
        case .disconnected: return "bolt.fill"
        case .error:        return "arrow.clockwise"
        }
    }

    private var buttonColor: Color {
        switch vm.status {
        case .connected:    return .danger
        case .connecting:   return .warning
        case .disconnected: return .accentCore
        case .error:        return .accentCore
        }
    }
}

// MARK: - Connect orb

private struct ConnectOrb: View {
    let status: ConnectionStatus
    @Binding var rotation: Double
    @Binding var pulse: Bool

    var orbColor: Color {
        switch status {
        case .connected:    return .success
        case .connecting:   return .warning
        case .disconnected: return .accentCore
        case .error:        return .danger
        }
    }

    var body: some View {
        ZStack {
            // Outer rotating dashed ring
            Circle()
                .stroke(
                    orbColor.opacity(0.28),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 10])
                )
                .frame(width: 240, height: 240)
                .rotationEffect(.degrees(rotation))

            // Middle progress ring
            Circle()
                .trim(from: 0, to: status == .connected ? 1.0 : 0.72)
                .stroke(
                    AngularGradient(
                        colors: [orbColor, orbColor.opacity(0.15), orbColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 208, height: 208)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: status)

            // Glow
            Circle()
                .fill(orbColor.opacity(pulse ? 0.24 : 0.12))
                .frame(width: 190, height: 190)
                .blur(radius: 34)
                .animation(
                    .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                    value: pulse
                )

            // Glass disc
            Circle()
                .fill(
                    ZStack {
                        Color.glassSurface
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                )
                .frame(width: 176, height: 176)
                .overlay(
                    Circle().stroke(Color.glassBorderBright, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 22, x: 0, y: 12)

            // Center content
            VStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 46, weight: .light))
                    .foregroundColor(orbColor)
                    .shadow(color: orbColor.opacity(0.7), radius: 12)

                Text(centerLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.textSecondary)
            }
        }
        .onAppear {
            pulse = true
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    private var iconName: String {
        switch status {
        case .connected:    return "lock.shield.fill"
        case .connecting:   return "arrow.triangle.2.circlepath"
        case .disconnected: return "shield.slash"
        case .error:        return "exclamationmark.shield.fill"
        }
    }

    private var centerLabel: String {
        switch status {
        case .connected:    return "PROTECTED"
        case .connecting:   return "LINKING"
        case .disconnected: return "UNPROTECTED"
        case .error:        return "FAILED"
        }
    }
}

// MARK: - Server info card

private struct ServerInfoCard: View {
    let config: ServerConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentCore)
                Text("SERVER")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(config.transport.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.accentCore)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentMuted)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(config.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)

                Text(config.docURL.isEmpty ? "No document URL configured" : config.docURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(config.docURL.isEmpty ? .danger : .textMuted)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Divider().overlay(Color.glassBorder)

            HStack(spacing: 16) {
                Label("\(config.socksPort)", systemImage: "network")
                Label("SOCKS5", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(.textSecondary)
        }
        .liquidGlassCard()
    }
}

#Preview {
    HomeView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
        .preferredColorScheme(.dark)
}
