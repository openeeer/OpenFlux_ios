# OpenFlux for iOS

SwiftUI client for the OpenFlux tunnel. Runs the Go engine in-process as a
static library and exposes a local SOCKS5 proxy on the device.

```
iOS app ──> SOCKS5 :1080 ──> Transport (Yandex Docs) ──> Exit node ──> Internet
             (in-app Go engine)
```

Everything here lives under `ios/`. Building the app never writes outside this
directory — the engine is a separate Go module that consumes the parent
checkout through a `replace` directive.

---

## Layout

```
ios/
└── OpenFlux/
    ├── OpenFlux.xcodeproj/
    ├── Supporting/
    │   ├── Info.plist
    │   └── OpenFlux.entitlements
    ├── GoEngine/
    │   ├── build_engine.sh         Xcode build phase → liboflux.a
    │   ├── OpenFluxEngine.h
    │   └── engine/                 Go module (c-archive sources)
    └── OpenFlux/
        ├── OpenFlux-Bridging-Header.h
        ├── Resources/
        └── Sources/
            ├── Models/             ConnectionState
            ├── Services/           NetworkManager
            ├── ViewModels/
            └── Views/              DesignSystem, Home, Stats, Settings
```

CI config lives at the repository root as `bitrise.yml`. The `unsigned-ipa`
workflow creates a device archive without signing and packages it as an IPA
for eSign.

---

## Requirements

- macOS with Xcode 16 or newer (the project uses `objectVersion = 77`)
- Go 1.26+ on `PATH` for a native engine build
- A physical iPhone, iOS 17+

The simulator is supported for UI work only — see *Engine flavours* below.

---

## Building

Open `ios/OpenFlux/OpenFlux.xcodeproj`, pick your device, run.

A build phase invokes `GoEngine/build_engine.sh`, which cross-compiles
`GoEngine/engine` to `GoEngine/liboflux.a` with `-buildmode=c-archive` and
links it into the app.

### Engine flavours

`build_engine.sh` always produces a linkable archive, but it may be one of two
things:

| Flavour    | When                                                        | Runtime behaviour                                  |
|------------|-------------------------------------------------------------|----------------------------------------------------|
| **native** | Device build, Go on `PATH`, archive exports `_RunMainClient` | Real tunnel                                        |
| **stub**   | Simulator, no Go toolchain, or the Go build failed           | App runs, shows a banner, refuses to fake a connection |

Go cannot target the iOS simulator ABI, so simulator builds are *always* stubs.
This is deliberate: a stub build links and launches so you can iterate on UI,
and `OpenFluxEngineIsStub()` lets the app say so out loud instead of pretending
to tunnel.

Force a stub on a device build with `FORCE_STUB=1`.

To confirm which one you got:

```sh
nm -gU ios/OpenFlux/GoEngine/liboflux.a | grep _OpenFluxBytesIn
# a match means native
```

### Offline builds

`GoEngine/engine/go.sum` is committed, so `go build` works without network
access. If the module cache is cold and the sumdb is unreachable:

```sh
cd ios/OpenFlux/GoEngine/engine
GOFLAGS=-mod=mod GOPRIVATE='*' go build ./...
```

Set `OPENFLUX_SKIP_TIDY=1` to skip the `go mod download` step in the build
script entirely.

---

## The C bridge

`OpenFlux-Bridging-Header.h` declares the engine's C surface. Both the native
archive and the generated stub define every one of these symbols, so the app
links either way.

| Symbol                          | Purpose                                    |
|---------------------------------|--------------------------------------------|
| `RunMainClient(char *url)`       | Start the tunnel; **blocks** until stopped |
| `OpenFluxStartTunnel(url, port)` | Starts on the selected SOCKS5 port; 0 on success |
| `StopTunnel()`                   | Shut down; releases the blocking call      |
| `OpenFluxIsConnected()`          | 1 while the SOCKS5 listener is accepting   |
| `OpenFluxBytesIn/Out()`          | Live traffic counters                      |
| `OpenFluxEngineIsStub()`         | 1 for the stub archive, 0 for native       |
| `RunMainExitNode()`              | Exit-node mode; needs root, unusable on iOS |

`NetworkManager` calls `OpenFluxStartTunnel` with the configured port and
waits for `OpenFluxIsConnected()` before showing Connected. It also uses a
generation counter so a late-returning operation cannot clobber a newer
session.

Adding an export means touching three places, or the stub and native builds
drift apart:

1. `//export` in `GoEngine/engine/main.go`
2. the stub in `GoEngine/build_engine.sh`
3. `OpenFlux/OpenFlux-Bridging-Header.h`

---

## Configuration

Set the document URL in **Settings**. It is validated before use: HTTPS only,
no embedded credentials, no bare IP addresses. An invalid URL surfaces an error
rather than hanging on connect.

The default SOCKS5 port is `1080`.

---

## Entitlements

`OpenFlux.entitlements` is deliberately empty. The in-process SOCKS5 listener
needs no entitlement — iOS lets any app bind a loopback port.

Keeping it empty is what makes the IPA resignable with a free Apple ID. Free
certificates cannot grant capabilities, so every extra key becomes a resigning
failure in eSign or Sideloadly. Do not add App Groups, Keychain sharing, or
NetworkExtension keys unless you sign with a paid account.

Note that the SOCKS5 proxy is only reachable by apps that honour a manual
proxy setting. A system-wide tunnel would require a `NEPacketTunnelProvider`
network extension — a paid account, a different architecture, and not what
this project does.

---

## Installing with eSign

1. Run the **`unsigned-ipa`** workflow in Bitrise.
2. Download `OpenFlux-unsigned.ipa` from the Bitrise artifacts.
3. Transfer it to the iPhone — AirDrop, Files, or a direct download.
4. In eSign: **Import** the IPA, pick your certificate and provisioning
   profile, **Sign**, then install.
5. First launch: **Settings → General → VPN & Device Management** → trust the
   developer certificate.

An app signed with a free Apple ID expires after 7 days and must be resigned.

---

## CI

`bitrise.yml` at the repository root defines two workflows. Bitrise's
`unsigned-ipa` workflow runs `xcodebuild archive` with signing disabled, then
packages the `.app` from the archive into `OpenFlux-unsigned.ipa`.

### `unsigned-ipa`

No Bitrise signing setup is needed. It produces `OpenFlux-unsigned.ipa` for
eSign and prints whether the engine came out native or stub.

### `signed-development`

Requires a certificate and provisioning profile uploaded to Bitrise. It is not
needed for the eSign workflow.

Change the bundle identifier from `com.openflux.app` to one you own.

---

## Troubleshooting

**"Engine not linked (stub build)"** — expected on the simulator. On a device,
check the build log for a `note: building stub engine (...)` line; the
parenthetical gives the reason.

**Undefined symbols at link time** — the archive and the bridging header
disagree. Add the missing symbol to the stub in `build_engine.sh`.

**Connect does nothing** — verify the exit node is reachable and the document
URL is correct. The stats panel reads live engine counters, so flat zeros with
a "connected" state means traffic is not reaching the transport.
