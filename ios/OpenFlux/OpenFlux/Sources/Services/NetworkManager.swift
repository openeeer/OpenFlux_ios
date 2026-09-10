import Foundation
import Combine

/// Manages the lifecycle of the OpenFlux SOCKS5 tunnel.
///
/// The Go engine is linked as a static archive (`GoEngine/liboflux.a`, produced
/// by `GoEngine/build_engine.sh` during the Xcode build). Two flavours exist:
///
///   * **native** — the real tunnel; `RunMainClient` blocks until `StopTunnel`.
///   * **stub**   — generated when Go cannot target the build (simulator, no
///                  toolchain, or the Go package exports no bridge symbols yet).
///                  `OpenFluxEngineIsStub()` returns 1, and this manager then
///                  reports a clearly-fake session instead of a silent no-op.
///
/// `RunMainClient` blocks, so it owns a dedicated thread; `StopTunnel` is what
/// releases it.
final class NetworkManager: ObservableObject {

    // MARK: - Published state

    @Published private(set) var status: ConnectionStatus = .disconnected
    @Published private(set) var stats = ConnectionStats()
    @Published private(set) var isStubEngine: Bool = OpenFluxEngineIsStub() == 1

    // MARK: - Private

    private var tunnelThread: Thread?
    /// Bumped on every connect/disconnect so a late-returning thread cannot
    /// overwrite the state of a newer session.
    private var generation: UInt64 = 0
    private var statsTimer: Timer?
    private let stateLock = NSLock()

    // MARK: - Public API

    func connect(config: ServerConfig) {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard status == .disconnected || isError(status) else { return }

        guard let url = Self.validatedURL(config.docURL) else {
            status = .error("Invalid document URL")
            return
        }
        guard (1...65535).contains(config.socksPort) else {
            status = .error("Invalid SOCKS port")
            return
        }

        status = .connecting
        generation &+= 1
        let gen = generation
        let port = config.socksPort

        let thread = Thread { [weak self] in
            Self.runTunnel(url: url.absoluteString, port: port, generation: gen, owner: self)
        }
        thread.name = "openflux.tunnel"
        thread.stackSize = 1 << 20
        tunnelThread = thread
        thread.start()
    }

    func disconnect() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard status != .disconnected else { return }

        generation &+= 1
        stopStatsTimer()
        tunnelThread = nil

        // Releases the blocking RunMainClient call on the tunnel thread.
        StopTunnel()

        status = .disconnected
        stats = ConnectionStats()
    }

    // MARK: - Tunnel thread

    private static func runTunnel(url: String, port: Int, generation: UInt64, owner: NetworkManager?) {
        guard let owner else { return }

        if owner.isStubEngine {
            // No real engine linked: surface it rather than pretending.
            owner.publish(generation: generation) {
                $0.status = .error("Engine not linked (stub build)")
            }
            return
        }

        owner.publish(generation: generation) {
            $0.status = .connected
            $0.stats = ConnectionStats(connectedSince: Date())
            $0.startStatsTimer()
        }

        // OpenFluxStartTunnel blocks for the tunnel lifetime, but unlike the
        // legacy RunMainClient entry point it receives the selected SOCKS port.
        let result = url.withCString {
            OpenFluxStartTunnel(UnsafeMutablePointer(mutating: $0), Int32(port))
        }

        // Returned: either StopTunnel() fired, or the engine failed.
        owner.publish(generation: generation) {
            $0.stopStatsTimer()
            if result != 0 {
                $0.status = .error("Tunnel failed to start (see Logs)")
                $0.stats = ConnectionStats()
            } else if $0.status.isActive {
                $0.status = .disconnected
                $0.stats = ConnectionStats()
            }
        }
    }

    /// Applies a mutation on the main queue, but only if `generation` is still
    /// the current one — a stale tunnel thread must not clobber a new session.
    private func publish(generation gen: UInt64, _ mutate: @escaping (NetworkManager) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let current = self.generation == gen
            self.stateLock.unlock()
            guard current else { return }
            mutate(self)
        }
    }

    private func isError(_ s: ConnectionStatus) -> Bool {
        if case .error = s { return true }
        return false
    }

    // MARK: - Stats

    private func startStatsTimer() {
        stopStatsTimer()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.status.isActive else { return }

            self.stats.bytesIn  = Int64(OpenFluxBytesIn())
            self.stats.bytesOut = Int64(OpenFluxBytesOut())

            // The engine dropping its listener is the authoritative signal that
            // the session died; the blocking RunMainClient call may not have
            // unwound yet.
            if OpenFluxIsConnected() == 0 {
                self.stopStatsTimer()
                self.status = .error("Tunnel closed by engine")
            }
        }
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    // MARK: - Validation

    /// Mirrors the exit node's allowlist spirit: https only, no credentials,
    /// no bare IPs. Rejecting early gives a real error instead of a hang.
    static func validatedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil, url.password == nil,
              !isBareIP(host)
        else { return nil }
        return url
    }

    private static func isBareIP(_ host: String) -> Bool {
        if host.contains(":") { return true }         // IPv6 literal
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { UInt8($0) != nil }  // IPv4 dotted quad
    }

    deinit { stopStatsTimer() }
}
