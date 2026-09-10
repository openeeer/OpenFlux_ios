package yandex

import (
	"bytes"
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"sync"
	"sync/atomic"
	"universal-bypass-tool/network"
	"universal-bypass-tool/transport"
)

var poolMagic = []byte{'O', 'F', 'P', '1', 0, 0, 0, 1}

const poolHeader = 32

func packetData(p []byte) []byte {
	if len(p) >= poolHeader && bytes.Equal(p[:8], poolMagic) {
		return p[poolHeader:]
	}
	return p
}

// A bounded replay window permits reordered frames across independent sessions.
type replayWindow struct {
	top   uint64
	slots [8192]uint64
}

func (w *replayWindow) accept(seq uint64) bool {
	if seq == 0 || (w.top >= 8192 && seq <= w.top-8192) {
		return false
	}
	i := seq % 8192
	if w.slots[i] == seq {
		return false
	}
	w.slots[i] = seq
	if seq > w.top {
		w.top = seq
	}
	return true
}

type SessionPool struct {
	members    []*YandexDocsTransport
	id         [16]byte
	seq        atomic.Uint64
	mu         sync.Mutex
	seen       map[[16]byte]*replayWindow
	callback   func([]byte)
	duplicates atomic.Uint64
}

func NewSessionPool(url string, c transport.TransportConfig, n int) (*SessionPool, error) {
	if n < 1 || n > 8 {
		return nil, fmt.Errorf("yandex-sessions must be 1..8")
	}
	if n > 1 && c.YandexLegacy {
		return nil, fmt.Errorf("session pool requires OF2 mode on both peers")
	}
	p := &SessionPool{seen: make(map[[16]byte]*replayWindow)}
	if _, e := rand.Read(p.id[:]); e != nil {
		return nil, e
	}
	for i := 0; i < n; i++ {
		t := NewYandexDocsTransport(url, c)
		index := i
		t.receiveHook = func(b []byte) bool { return p.receive(index, b) }
		p.members = append(p.members, t)
	}
	return p, nil
}
func (p *SessionPool) receive(index int, b []byte) bool {
	data := packetData(b)
	p.mu.Lock()
	if len(data) != len(b) {
		var id [16]byte
		copy(id[:], b[8:24])
		if id == p.id {
			p.mu.Unlock()
			return false
		}
		w := p.seen[id]
		if w == nil {
			if len(p.seen) >= 32 {
				p.mu.Unlock()
				return false
			}
			w = &replayWindow{}
			p.seen[id] = w
		}
		if !w.accept(binary.BigEndian.Uint64(b[24:32])) {
			p.duplicates.Add(1)
			p.mu.Unlock()
			return false
		}
	} else if index != 0 {
		p.mu.Unlock()
		return false
	}
	cb := p.callback
	p.mu.Unlock()
	if cb != nil {
		cb(data)
	}
	return true
}
func (p *SessionPool) Start() error {
	for i, t := range p.members {
		if e := t.Start(); e != nil {
			for _, old := range p.members[:i] {
				old.Stop()
			}
			return e
		}
	}
	return nil
}
func (p *SessionPool) Stop() error {
	for _, t := range p.members {
		t.Stop()
	}
	return nil
}
func (p *SessionPool) Receive(cb func([]byte)) { p.mu.Lock(); p.callback = cb; p.mu.Unlock() }
func (p *SessionPool) IsConnected() bool {
	for _, t := range p.members {
		if !t.IsConnected() {
			return false
		}
	}
	return true
}
func (p *SessionPool) Send(b []byte) error {
	if len(p.members) == 1 {
		return p.members[0].Send(b)
	}
	info, ok := network.ParseTCP(b)
	if !ok {
		return fmt.Errorf("pool requires validated IPv4 TCP packet")
	}
	h := uint32(2166136261)
	for _, v := range info.Flow {
		h = (h ^ uint32(v)) * 16777619
	}
	frame := make([]byte, poolHeader+len(b))
	copy(frame, poolMagic)
	copy(frame[8:24], p.id[:])
	binary.BigEndian.PutUint64(frame[24:32], p.seq.Add(1))
	copy(frame[32:], b)
	return p.members[int(h%uint32(len(p.members)))].Send(frame)
}
func (p *SessionPool) Stats() transport.TransportStats {
	var r transport.TransportStats
	r.Connected = p.IsConnected()
	for _, t := range p.members {
		s := t.Stats()
		r.BytesSent += s.BytesSent
		r.BytesReceived += s.BytesReceived
		r.PacketsSent += s.PacketsSent
		r.PacketsRecv += s.PacketsRecv
		r.Reconnects += s.Reconnects
		if s.Uptime > r.Uptime {
			r.Uptime = s.Uptime
		}
	}
	return r
}
