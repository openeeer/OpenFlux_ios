import SwiftUI

extension Color {
    static let appBlue = Color.accentColor
    static let appSecondary = Color.secondary
}

struct StatusPill: View {
    let status: ConnectionStatus

    private var color: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .error: return .red
        }
    }

    var body: some View {
        Label(status.displayText, systemImage: status == .connected ? "checkmark.circle.fill" : "circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
    }
}

struct PrimaryButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
