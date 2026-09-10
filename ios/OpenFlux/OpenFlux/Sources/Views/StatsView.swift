import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var vm: ConnectionViewModel
    @EnvironmentObject private var settings: SettingsViewModel

    var body: some View {
        ZStack {
            AnimatedBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TELEMETRY")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .tracking(3.2)
                                .foregroundColor(.accentCore)
                            Text("Session Stats")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        StatusPill(status: vm.status)
                    }
                    .padding(.top, 8)

                    // Traffic overview
                    VStack(spacing: 18) {
                        TrafficBar(
                            down: vm.stats.bytesIn,
                            up: vm.stats.bytesOut
                        )

                        HStack(spacing: 12) {
                            StatTile(
                                label: "DOWNLOAD",
                                value: vm.stats.formattedBytesIn,
                                systemImage: "arrow.down.circle.fill",
                                color: .success
                            )
                            StatTile(
                                label: "UPLOAD",
                                value: vm.stats.formattedBytesOut,
                                systemImage: "arrow.up.circle.fill",
                                color: .accentCore
                            )
                        }
                    }
                    .liquidGlassCard()

                    // Session details
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SESSION")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundColor(.textSecondary)
                            .padding(.bottom, 12)

                        DetailRow(label: "Uptime",    value: vm.stats.uptime)
                        Divider().overlay(Color.glassBorder)
                        DetailRow(
                            label: "Latency",
                            value: vm.stats.latencyMs > 0
                                ? String(format: "%.0f ms", vm.stats.latencyMs)
                                : "—"
                        )
                        Divider().overlay(Color.glassBorder)
                        DetailRow(label: "Transport", value: vm.selectedConfig.transport.displayName)
                        Divider().overlay(Color.glassBorder)
                        DetailRow(label: "SOCKS5",    value: "127.0.0.1:\(vm.selectedConfig.socksPort)")
                        Divider().overlay(Color.glassBorder)
                        DetailRow(label: "Server",    value: vm.selectedConfig.name)
                    }
                    .liquidGlassCard()

                    // Connected apps placeholder
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ROUTING")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundColor(.textSecondary)

                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.accentCore)
                            Text("Configure your apps to use the SOCKS5 proxy at 127.0.0.1:\(vm.selectedConfig.socksPort)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.textSecondary)
                            Spacer()
                        }
                    }
                    .liquidGlassCard()

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct DetailRow: View {
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
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 11)
    }
}

private struct TrafficBar: View {
    let down: Int64
    let up: Int64

    private var total: Double {
        max(Double(down + up), 1)
    }
    private var downFraction: Double { Double(down) / total }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TRAFFIC SPLIT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(Int(downFraction * 100))% down")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.success)
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.success, .success.opacity(0.6)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * downFraction - 1, 0))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.accentCore, .accentCore.opacity(0.6)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            .background(Color.glassRaised)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .animation(.easeInOut(duration: 0.5), value: down)
        }
    }
}

#Preview {
    StatsView()
        .environmentObject(ConnectionViewModel())
        .environmentObject(SettingsViewModel())
        .preferredColorScheme(.dark)
}
