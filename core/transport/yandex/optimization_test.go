package yandex

import (
	"encoding/binary"
	"testing"
	"time"
	"universal-bypass-tool/network"
	"universal-bypass-tool/transport"
)

func testPacket(payload int, flags byte) []byte {
	b := make([]byte, 40+payload)
	b[0] = 0x45
	b[9] = 6
	binary.BigEndian.PutUint16(b[2:], uint16(len(b)))
	b[32] = 0x50
	b[33] = flags
	return b
}
func TestACKClassification(t *testing.T) {
	for _, tc := range []struct {
		data []byte
		want bool
	}{{testPacket(0, 16), true}, {testPacket(100, 16), false}, {testPacket(0, 2), true}, {[]byte{0x45}, false}} {
		if network.UrgentTCP(tc.data) != tc.want {
			t.Fatal("wrong urgent classification")
		}
	}
}
func TestCollectorNoDelayAndFIFO(t *testing.T) {
	c := transport.DefaultConfig()
	c.YandexBatchDelay = time.Hour
	c.YandexBatchBytes = 100
	x := NewYandexDocsTransport("unused", c)
	x.queueCh = make(chan queuedPacket, 4)
	x.stopCh = make(chan struct{})
	ack := queuedPacket{testPacket(0, 16), time.Now()}
	done := make(chan []queuedPacket, 1)
	go func() { done <- x.collect(ack) }()
	select {
	case got := <-done:
		if len(got) != 1 {
			t.Fatal("ACK must not wait")
		}
	case <-time.After(time.Second):
		close(x.stopCh)
		t.Fatal("ACK delayed")
	}
	bulk := queuedPacket{testPacket(20, 16), time.Now()}
	x.queueCh <- bulk
	got := x.collect(bulk)
	if len(got) != 1 || x.pending == nil {
		t.Fatal("byte limit or FIFO carry lost")
	}
}
func TestPoolDeduplicatesAndRejectsSelf(t *testing.T) {
	p, e := NewSessionPool("unused", transport.DefaultConfig(), 2)
	if e != nil {
		t.Fatal(e)
	}
	calls := 0
	p.Receive(func(b []byte) { calls++ })
	b := make([]byte, 32+40)
	copy(b, poolMagic)
	b[8] = 99
	binary.BigEndian.PutUint64(b[24:], 1)
	copy(b[32:], testPacket(0, 16))
	p.receive(0, b)
	p.receive(1, b)
	if calls != 1 {
		t.Fatal("duplicate delivered")
	}
	copy(b[8:24], p.id[:])
	binary.BigEndian.PutUint64(b[24:], 2)
	p.receive(1, b)
	if calls != 1 {
		t.Fatal("self echo delivered")
	}
}
func TestReplayOutOfOrder(t *testing.T) {
	var w replayWindow
	for _, v := range []uint64{3, 1, 2, 10000} {
		if !w.accept(v) {
			t.Fatal("valid sequence rejected")
		}
	}
	if w.accept(3) || w.accept(10000) {
		t.Fatal("replay accepted")
	}
}
func TestTCPRTT(t *testing.T) {
	var o tcpObserver
	now := time.Now()
	syn := testPacket(0, 2)
	binary.BigEndian.PutUint32(syn[24:], 123)
	o.observe(syn, true, now)
	ack := testPacket(0, 18)
	binary.BigEndian.PutUint32(ack[28:], 124)
	o.observe(ack, false, now.Add(20*time.Millisecond))
	if o.samples != 1 {
		t.Fatal("missing RTT")
	}
}
func BenchmarkCollectACK(b *testing.B) {
	c := transport.DefaultConfig()
	t := NewYandexDocsTransport("unused", c)
	p := queuedPacket{testPacket(0, 16), time.Now()}
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		t.collect(p)
	}
}
