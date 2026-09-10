#!/bin/bash
#
# Produces GoEngine/liboflux.a for the current Xcode build.
#
# Two outcomes:
#   native  — the Go c-archive built and exports RunMainClient
#   stub    — a generated no-op archive, so the app still links and runs
#
# The stub keeps the Xcode target buildable before the Go engine grows its
# //export surface, and keeps simulator builds working (Go cannot target the
# iOS simulator ABI).
#
# Environment (supplied by Xcode):
#   SRCROOT, PLATFORM_NAME, ARCHS, CONFIGURATION
# Optional:
#   FORCE_STUB=1          — skip the Go build entirely
#   OPENFLUX_SKIP_TIDY=1  — skip `go mod download`
#
# The engine lives in GoEngine/engine and is its own module, consuming the
# parent checkout through a `replace` directive — building the iOS app never
# writes anything outside ios/.

set -euo pipefail

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT_DIR="${SRCROOT}/GoEngine"
LIB="${OUT_DIR}/liboflux.a"
ENGINE_DIR="${OUT_DIR}/engine"
PLATFORM_NAME="${PLATFORM_NAME:-iphoneos}"

mkdir -p "${OUT_DIR}"

write_stub() {
  local reason="$1"
  echo "note: building stub engine (${reason})"

  local stub_src="${OUT_DIR}/.engine_stub.c"
  cat > "${stub_src}" <<'STUB_EOF'
/* Generated no-op engine. See GoEngine/build_engine.sh. */
#include <stddef.h>

void RunMainClient(char *url) { (void)url; }
int OpenFluxStartTunnel(char *url, int port) { (void)url; (void)port; return -1; }
void RunMainExitNode(void) {}
void StopTunnel(void) {}
int OpenFluxIsConnected(void) { return 0; }
long long OpenFluxBytesIn(void) { return 0; }
long long OpenFluxBytesOut(void) { return 0; }
int OpenFluxEngineIsStub(void) { return 1; }
STUB_EOF

  local cc sdk arch
  cc="$(xcrun --sdk "${PLATFORM_NAME}" --find clang)"
  sdk="$(xcrun --sdk "${PLATFORM_NAME}" --show-sdk-path)"
  arch="$(echo "${ARCHS:-arm64}" | awk '{print $1}')"

  local target_flag=""
  if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
    target_flag="-target ${arch}-apple-ios-simulator"
  fi

  local obj="${OUT_DIR}/.engine_stub.o"
  # shellcheck disable=SC2086
  "${cc}" -c -O2 -isysroot "${sdk}" -arch "${arch}" ${target_flag} \
    -mios-version-min=17.0 \
    -o "${obj}" "${stub_src}"

  rm -f "${LIB}"
  xcrun libtool -static -o "${LIB}" "${obj}" 2>/dev/null \
    || ar rcs "${LIB}" "${obj}"

  rm -f "${obj}" "${stub_src}"
  echo "note: stub engine written to ${LIB}"
}

# --- Simulator: Go cannot produce a matching archive -------------------------
if [ "${PLATFORM_NAME}" = "iphonesimulator" ]; then
  write_stub "iOS simulator target"
  exit 0
fi

if [ "${FORCE_STUB:-0}" = "1" ]; then
  write_stub "FORCE_STUB=1"
  exit 0
fi

# --- Prerequisites -----------------------------------------------------------
if ! command -v go >/dev/null 2>&1; then
  write_stub "go toolchain not on PATH"
  exit 0
fi

if [ ! -f "${ENGINE_DIR}/main.go" ]; then
  write_stub "no engine sources at ${ENGINE_DIR}"
  exit 0
fi

# --- Real Go c-archive -------------------------------------------------------
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
ARCH="$(echo "${ARCHS:-arm64}" | awk '{print $1}')"

TMP_LIB="${OUT_DIR}/.liboflux.tmp.a"
rm -f "${TMP_LIB}"

echo "note: building Go engine for ios/${ARCH}"

if [ "${OPENFLUX_SKIP_TIDY:-0}" != "1" ]; then
  ( cd "${ENGINE_DIR}" && go mod download ) || true
fi

if ! (
  cd "${ENGINE_DIR}" &&
  CGO_ENABLED=1 \
  GOOS=ios \
  GOARCH="${ARCH}" \
  SDK_PATH="${SDK_PATH}" \
  CC="${CLANG} -isysroot ${SDK_PATH} -arch ${ARCH} -miphoneos-version-min=17.0" \
  CGO_CFLAGS="-isysroot ${SDK_PATH} -arch ${ARCH} -miphoneos-version-min=17.0" \
  CGO_LDFLAGS="-isysroot ${SDK_PATH} -arch ${ARCH} -miphoneos-version-min=17.0" \
  go build -buildmode=c-archive -trimpath -ldflags="-s -w" -o "${TMP_LIB}" .
); then
  write_stub "go build failed"
  exit 0
fi

# --- Verify the archive actually exports the bridge symbols ------------------
# The linker fails with undefined symbols if the archive lacks them, so fall
# back to the stub rather than breaking the build.
if ! nm -gU "${TMP_LIB}" 2>/dev/null | grep -q '_RunMainClient'; then
  rm -f "${TMP_LIB}"
  write_stub "archive exports no RunMainClient"
  exit 0
fi

mv -f "${TMP_LIB}" "${LIB}"
echo "note: native Go engine written to ${LIB}"
