//
//  OpenFlux-Bridging-Header.h
//
//  C surface of the Go tunnel engine (liboflux.a, built by build_ios.sh).
//
//  Declarations only — no symbols are referenced unless the Swift call sites
//  are compiled with -DOPENFLUX_NATIVE, so the project links cleanly without
//  the static library present (simulator, previews, CI smoke builds).
//

#ifndef OPENFLUX_BRIDGING_HEADER_H
#define OPENFLUX_BRIDGING_HEADER_H

#ifdef __cplusplus
extern "C" {
#endif

/// Start the SOCKS5 client tunnel. `url` is a NUL-terminated UTF-8 C string.
/// Blocks for the lifetime of the tunnel; call from a background thread.
void RunMainClient(char *url);

/// Starts the tunnel on `port` and blocks for its lifetime. Returns non-zero
/// when the listener could not be opened.
int OpenFluxStartTunnel(char *url, int port);

/// Start the exit-node raw-socket engine. Requires root, unusable on iOS.
void RunMainExitNode(void);

/// Ask a running tunnel to shut down. Safe to call when nothing is running.
void StopTunnel(void);

/// 1 while the SOCKS5 listener is accepting, 0 otherwise.
int OpenFluxIsConnected(void);

/// Cumulative bytes relayed since the current tunnel started.
long long OpenFluxBytesIn(void);
long long OpenFluxBytesOut(void);

/// 1 when the linked archive is the generated no-op stub (Go engine absent),
/// 0 when the real engine is linked. Lets the UI tell "tunnelling" apart from
/// "pretending to tunnel" instead of guessing.
int OpenFluxEngineIsStub(void);
/// Owned UTF-8 snapshot, released using OpenFluxFreeLogs (not Swift ownership).
char *OpenFluxCopyLogs(void);
void OpenFluxFreeLogs(char *logs);

#ifdef __cplusplus
}
#endif

#endif /* OPENFLUX_BRIDGING_HEADER_H */
