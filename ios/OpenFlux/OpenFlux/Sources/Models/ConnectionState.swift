import Foundation

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        case .error(let m): return "Error: \(m)"
        }
    }

    var isActive: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var docURL: String
    var socksPort: Int
    var transport: TransportType

    enum TransportType: String, Codable, CaseIterable {
        case yandex = "yandex"
        case oneme  = "oneme"

        var displayName: String {
            switch self {
            case .yandex: return "Yandex Docs"
            case .oneme:  return "Max Messenger"
            }
        }
    }

    /// Stable identity so a fresh install always resolves the same default config.
    static let defaultConfig = ServerConfig(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "My Server",
        docURL: "",
        socksPort: 1080,
        transport: .yandex
    )
}

struct ConnectionStats {
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
    var latencyMs: Double = 0
    var connectedSince: Date? = nil

    var uptime: String {
        guard let since = connectedSince else { return "—" }
        let s = Int(Date().timeIntervalSince(since))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \(s%3600/60)m"
    }

    var formattedBytesIn: String  { formatBytes(bytesIn) }
    var formattedBytesOut: String { formatBytes(bytesOut) }

    private func formatBytes(_ n: Int64) -> String {
        let kb = Double(n) / 1024
        let mb = kb / 1024
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.1f KB", kb) }
        return "\(n) B"
    }
}
