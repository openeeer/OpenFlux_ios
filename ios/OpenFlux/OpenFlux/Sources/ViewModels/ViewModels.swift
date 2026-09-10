import Foundation
import Combine

final class ConnectionViewModel: ObservableObject {
    @Published var status: ConnectionStatus = .disconnected
    @Published var stats = ConnectionStats()
    @Published var selectedConfig: ServerConfig = ServerConfig.defaultConfig
    @Published var isStubEngine: Bool = false

    private let manager = NetworkManager()
    private var cancellables = Set<AnyCancellable>()

    init() {
        manager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: &$status)
        manager.$stats
            .receive(on: DispatchQueue.main)
            .assign(to: &$stats)
        manager.$isStubEngine
            .receive(on: DispatchQueue.main)
            .assign(to: &$isStubEngine)
    }

    func toggleConnection() {
        switch status {
        case .connected, .connecting:
            manager.disconnect()
        case .disconnected, .error:
            manager.connect(config: selectedConfig)
        }
    }

    var canConnect: Bool {
        NetworkManager.validatedURL(selectedConfig.docURL) != nil
    }
}

final class SettingsViewModel: ObservableObject {
    @Published var configs: [ServerConfig] = {
        guard let data = UserDefaults.standard.data(forKey: "serverConfigs"),
              let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data)
        else { return [ServerConfig.defaultConfig] }
        return decoded
    }()

    @Published var selectedID: UUID? = {
        guard let str = UserDefaults.standard.string(forKey: "selectedConfigID"),
              let uuid = UUID(uuidString: str)
        else { return nil }
        return uuid
    }()

    func save() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "serverConfigs")
        }
        if let id = selectedID {
            UserDefaults.standard.set(id.uuidString, forKey: "selectedConfigID")
        }
    }

    func addConfig(_ c: ServerConfig) {
        configs.append(c)
        save()
    }

    func updateConfig(_ c: ServerConfig) {
        if let idx = configs.firstIndex(where: { $0.id == c.id }) {
            configs[idx] = c
            save()
        }
    }

    func removeConfig(at offsets: IndexSet) {
        configs.remove(atOffsets: offsets)
        save()
    }

    func selectedConfig(updating vm: ConnectionViewModel) -> ServerConfig {
        let cfg = configs.first(where: { $0.id == selectedID }) ?? configs.first ?? ServerConfig.defaultConfig
        vm.selectedConfig = cfg
        return cfg
    }
}
