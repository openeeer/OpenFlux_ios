//
//  OpenFluxEngine.h
//
//  C surface of the Go tunnel engine (liboflux.a).
//  Mirrored by OpenFlux-Bridging-Header.h for Swift import.
//

#ifndef OPENFLUX_ENGINE_H
#define OPENFLUX_ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Start the SOCKS5 client tunnel against a Yandex Docs document.
/// `url` is a NUL-terminated UTF-8 C string. Blocks for the tunnel lifetime,
/// so call it from a background thread.
void RunMainClient(char *url);

/// Start the SOCKS5 client tunnel on an explicit local port. Blocks for the
/// tunnel lifetime and returns non-zero when it could not start.
int OpenFluxStartTunnel(char *url, int port);

/// Start the exit-node raw-socket engine. Needs root; unusable on iOS.
void RunMainExitNode(void);

/// Ask a running tunnel to shut down. Safe to call when nothing is running.
void StopTunnel(void);

/// 1 when the linked archive is the generated no-op stub (Go engine absent),
/// 0 when the real engine is linked. Lets the UI tell "tunnelling" apart from
/// "pretending to tunnel" instead of guessing.
int OpenFluxEngineIsStub(void);
char *OpenFluxCopyLogs(void);
void OpenFluxFreeLogs(char *logs);

#ifdef __cplusplus
}
#endif

#endif /* OPENFLUX_ENGINE_H */
