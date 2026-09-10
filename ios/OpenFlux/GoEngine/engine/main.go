// Package main is the iOS bridge over the OpenFlux tunnel engine.
//
// It is built with `-buildmode=c-archive` into liboflux.a and linked into the
// SwiftUI app. Go's c-archive runtime is initialized by a constructor emitted
// into the archive, so the exported functions below are callable from Swift
// without any explicit runtime start-up.
//
// Only the client path is exposed: the exit node needs a raw socket and root,
// neither of which exists in an iOS app sandbox.
//
// This is a separate Go module that consumes the parent checkout through a
// `replace` directive, so building the iOS app never modifies the main project.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"log"
	"sync"
	"sync/atomic"
	"time"

	"universal-bypass-tool/transport"
	"universal-bypass-tool/transport/yandex"
	"universal-bypass-tool/tunnel"
)

// ---------------------------------------------------------------------------
// Engine state
// ---------------------------------------------------------------------------

type engine struct {
	mu        sync.Mutex
	transport *yandex.SessionPool
	tunnel    *tunnel.TCPTunnel
	proxy     *socksProxy
	running   atomic.Bool
	connected atomic.Bool

	bytesIn  atomic.Int64
	bytesOut atomic.Int64

	done chan struct{}
}

var (
	engMu  sync.Mutex
	active *engine
)

// ---------------------------------------------------------------------------
// Exported C surface
// ---------------------------------------------------------------------------

// RunMainClient starts the SOCKS5 client tunnel for the given Yandex Docs URL.
// It blocks until StopTunnel is called, so Swift must invoke it off the main
// thread.
//
//export RunMainClient
func RunMainClient(url *C.char) {
	if url == nil {
		return
	}
	start(C.GoString(url), 1080)
}

// OpenFluxStartTunnel starts the SOCKS listener on the requested port and
// waits until startup succeeds or fails. Returns 0 on success.
//
//export OpenFluxStartTunnel
func OpenFluxStartTunnel(url *C.char, port C.int) C.int {
	if url == nil {
		return 1
	}

	errCh := make(chan error, 1)
	go func() {
		errCh <- start(C.GoString(url), int(port))
	}()

	deadline := time.NewTimer(10 * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case err := <-errCh:
			if err != nil {
				log.Printf("[engine] start failed: %v", err)
				return 2
			}
			return 0
		case <-ticker.C:
			engMu.Lock()
			ready := active != nil && active.running.Load()
			engMu.Unlock()
			if ready {
				return 0
			}
		case <-deadline.C:
			log.Printf("[engine] start timed out")
			return 3
		}
	}
}

// StopTunnel tears the session down and returns once the listener is closed.
// Safe to call when nothing is running.
//
//export StopTunnel
func StopTunnel() {
	engMu.Lock()
	e := active
	active = nil
	engMu.Unlock()

	if e == nil {
		return
	}

	if e.proxy != nil {
		e.proxy.Close()
	}
	if e.transport != nil {
		_ = e.transport.Stop()
	}
	e.connected.Store(false)
	e.running.Store(false)

	// Release the thread parked in start(); it owns the <-e.done wait.
	e.markDone()

	select {
	case <-e.done:
	case <-time.After(3 * time.Second):
		log.Printf("[engine] stop timed out")
	}
}

// OpenFluxIsConnected reports whether the transport currently holds a session.
//
//export OpenFluxIsConnected
func OpenFluxIsConnected() C.int {
	engMu.Lock()
	e := active
	engMu.Unlock()
	if e == nil {
		return 0
	}
	if e.connected.Load() {
		return 1
	}
	return 0
}

// OpenFluxBytesIn / OpenFluxBytesOut expose live traffic counters.
//
//export OpenFluxBytesIn
func OpenFluxBytesIn() C.longlong {
	engMu.Lock()
	e := active
	engMu.Unlock()
	if e == nil {
		return 0
	}
	return C.longlong(e.bytesIn.Load())
}

//export OpenFluxBytesOut
func OpenFluxBytesOut() C.longlong {
	engMu.Lock()
	e := active
	engMu.Unlock()
	if e == nil {
		return 0
	}
	return C.longlong(e.bytesOut.Load())
}

// OpenFluxEngineIsStub is 0 here: this archive is the real engine. The
// generated fallback archive defines the same symbol as 1 so the app can tell
// the two apart at runtime.
//
//export OpenFluxEngineIsStub
func OpenFluxEngineIsStub() C.int { return 0 }

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

func start(docURL string, port int) error {
	engMu.Lock()
	if active != nil {
		engMu.Unlock()
		// Already running: block so the caller's thread behaves like a tunnel.
		<-activeDone()
		return nil
	}
	engMu.Unlock()

	if port <= 0 || port > 65535 {
		port = 1080
	}

	cfg := transport.DefaultConfig()

	pool, err := yandex.NewSessionPool(docURL, cfg, 1)
	if err != nil {
		return err
	}
	if err := pool.Start(); err != nil {
		return err
	}

	tun := tunnel.NewTCPTunnel(pool, false)

	proxy := newSOCKSProxy(port, tun)
	if err := proxy.Listen(); err != nil {
		_ = pool.Stop()
		return err
	}

	e := &engine{
		transport: pool,
		tunnel:    tun,
		proxy:     proxy,
		done:      make(chan struct{}),
	}
	e.running.Store(true)
	e.connected.Store(true)

	proxy.onTraffic = func(in, out int64) {
		if in > 0 {
			e.bytesIn.Add(in)
		}
		if out > 0 {
			e.bytesOut.Add(out)
		}
	}

	engMu.Lock()
	active = e
	engMu.Unlock()

	log.Printf("[engine] tunnel up: socks5 on 127.0.0.1:%d", port)

	go proxy.Serve()

	// Watch the transport so a dropped session flips the UI state.
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-e.done:
				return
			case <-ticker.C:
				e.connected.Store(pool.IsConnected())
			}
		}
	}()

	<-e.done
	return nil
}

func activeDone() <-chan struct{} {
	engMu.Lock()
	defer engMu.Unlock()
	if active == nil {
		ch := make(chan struct{})
		close(ch)
		return ch
	}
	return active.done
}

// markDone is called by the proxy when the listener stops for any reason.
func (e *engine) markDone() {
	select {
	case <-e.done:
	default:
		close(e.done)
	}
}

// main is required by the main package but is never invoked for c-archive.
func main() {}
