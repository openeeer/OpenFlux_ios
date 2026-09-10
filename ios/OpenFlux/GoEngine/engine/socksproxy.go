package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"sync/atomic"
)

// dialer is the subset of tunnel.TCPTunnel the proxy needs.
type dialer interface {
	DialTCP(address string) (net.Conn, error)
}

// socksProxy is a minimal SOCKS5 CONNECT server bound to loopback.
//
// It is a local copy rather than a reuse of universal-bypass-tool/socks5 for
// two reasons: that server exposes no way to stop its accept loop, and it
// reports no traffic counters, both of which the iOS UI needs.
type socksProxy struct {
	port    int
	dialer  dialer
	ln      net.Listener
	closing atomic.Bool

	conns sync.WaitGroup

	// onTraffic receives (bytesFromTarget, bytesToTarget) after each relay.
	onTraffic func(in, out int64)
}

func newSOCKSProxy(port int, d dialer) *socksProxy {
	return &socksProxy{port: port, dialer: d}
}

// Listen binds the socket. Kept separate from Serve so start() can fail fast
// and surface the error to Swift instead of logging it on a goroutine.
func (p *socksProxy) Listen() error {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", p.port))
	if err != nil {
		return fmt.Errorf("socks5 listen: %w", err)
	}
	p.ln = ln
	return nil
}

func (p *socksProxy) Serve() {
	for {
		conn, err := p.ln.Accept()
		if err != nil {
			if p.closing.Load() {
				return
			}
			log.Printf("[socks5] accept: %v", err)
			continue
		}
		p.conns.Add(1)
		go func() {
			defer p.conns.Done()
			p.handle(conn)
		}()
	}
}

func (p *socksProxy) Close() {
	if p.closing.Swap(true) {
		return
	}
	if p.ln != nil {
		_ = p.ln.Close()
	}
	// Give in-flight relays a moment to unwind before the caller tears the
	// tunnel down underneath them.
	done := make(chan struct{})
	go func() { p.conns.Wait(); close(done) }()
	select {
	case <-done:
	case <-timeAfter(2):
	}
}

// handle performs the SOCKS5 handshake and relays one CONNECT.
func (p *socksProxy) handle(client net.Conn) {
	defer client.Close()

	_ = client.SetDeadline(nowPlus(30 * 1000 * 1000 * 1000)) // 30s for the handshake
	target, err := handshake(client)
	if err != nil {
		return
	}
	_ = client.SetDeadline(noDeadline())

	remote, err := p.dialer.DialTCP(target)
	if err != nil {
		// General SOCKS server failure.
		_, _ = client.Write([]byte{0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	defer remote.Close()

	if _, err := client.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}

	_ = client.SetDeadline(noDeadline())

	var up, down atomic.Int64
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		n, _ := io.Copy(remote, client)
		up.Store(n)
		if c, ok := remote.(interface{ CloseWrite() error }); ok {
			_ = c.CloseWrite()
		} else {
			_ = remote.Close()
		}
	}()

	go func() {
		defer wg.Done()
		n, _ := io.Copy(client, remote)
		down.Store(n)
		if c, ok := client.(interface{ CloseWrite() error }); ok {
			_ = c.CloseWrite()
		} else {
			_ = client.Close()
		}
	}()

	wg.Wait()

	if p.onTraffic != nil {
		p.onTraffic(down.Load(), up.Load())
	}
}

// handshake reads the SOCKS5 greeting and CONNECT request, replying to the
// greeting. The CONNECT reply is sent by the caller once dialling succeeds.
func handshake(c net.Conn) (string, error) {
	// Greeting: VER NMETHODS METHODS...
	hdr := make([]byte, 2)
	if _, err := io.ReadFull(c, hdr); err != nil {
		return "", err
	}
	if hdr[0] != 0x05 {
		return "", fmt.Errorf("socks5: bad version %d", hdr[0])
	}
	if n := int(hdr[1]); n > 0 {
		if _, err := io.ReadFull(c, make([]byte, n)); err != nil {
			return "", err
		}
	}
	// No authentication.
	if _, err := c.Write([]byte{0x05, 0x00}); err != nil {
		return "", err
	}

	// Request: VER CMD RSV ATYP DST.ADDR DST.PORT
	req := make([]byte, 4)
	if _, err := io.ReadFull(c, req); err != nil {
		return "", err
	}
	if req[0] != 0x05 {
		return "", fmt.Errorf("socks5: bad request version %d", req[0])
	}
	if req[1] != 0x01 { // CONNECT only
		_, _ = c.Write([]byte{0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return "", fmt.Errorf("socks5: unsupported command %d", req[1])
	}

	var host string
	switch req[3] {
	case 0x01: // IPv4
		b := make([]byte, 4)
		if _, err := io.ReadFull(c, b); err != nil {
			return "", err
		}
		host = net.IP(b).String()
	case 0x03: // domain
		l := make([]byte, 1)
		if _, err := io.ReadFull(c, l); err != nil {
			return "", err
		}
		b := make([]byte, int(l[0]))
		if _, err := io.ReadFull(c, b); err != nil {
			return "", err
		}
		host = string(b)
	case 0x04: // IPv6 — the tunnel is IPv4-only
		_, _ = c.Write([]byte{0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return "", fmt.Errorf("socks5: IPv6 unsupported")
	default:
		return "", fmt.Errorf("socks5: bad address type %d", req[3])
	}

	pb := make([]byte, 2)
	if _, err := io.ReadFull(c, pb); err != nil {
		return "", err
	}
	port := binary.BigEndian.Uint16(pb)

	return fmt.Sprintf("%s:%d", host, port), nil
}
