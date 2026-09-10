package yandex

import (
	"log"
	"sync"
	"sync/atomic"
	"time"
	"universal-bypass-tool/network"
)

// Fixed logarithmic buckets bound memory and avoid per-packet allocations.
type latencyHistogram struct{ buckets [24]atomic.Uint64 }

func (h *latencyHistogram) observe(d time.Duration) {
	u := uint64(d / time.Microsecond)
	i := 0
	for u > 1 && i < 23 {
		u = (u + 1) / 2
		i++
	}
	h.buckets[i].Add(1)
}
func (h *latencyHistogram) percentile(p uint64) time.Duration {
	var counts [24]uint64
	var n uint64
	for i := range counts {
		counts[i] = h.buckets[i].Load()
		n += counts[i]
	}
	if n == 0 {
		return 0
	}
	target := (n*p + 99) / 100
	var sum uint64
	for i, c := range counts {
		sum += c
		if sum >= target {
			return time.Duration(uint64(1)<<i) * time.Microsecond
		}
	}
	return 0
}

type flowObservation struct {
	end, start uint32
	at, last   time.Time
	scale      uint8
	scaleKnown bool
	window     uint32
}
type tcpObserver struct {
	mu                           sync.Mutex
	flows                        map[[12]byte]*flowObservation
	rtt                          latencyHistogram
	samples, retrans, zeroWindow uint64
	minWindow, maxWindow         uint32
}

// RTT is sampled from locally sent data/SYN to a cumulative ACK; it includes
// the tunnel and remote ACK delay. Retransmitted samples are discarded.
func (o *tcpObserver) observe(p []byte, out bool, now time.Time) {
	t, ok := network.ParseTCP(p)
	if !ok {
		return
	}
	o.mu.Lock()
	defer o.mu.Unlock()
	if o.flows == nil {
		o.flows = make(map[[12]byte]*flowObservation)
	}
	if len(o.flows) >= 4096 {
		for k, f := range o.flows {
			if now.Sub(f.last) > time.Minute {
				delete(o.flows, k)
			}
		}
	}
	f := o.flows[t.Flow]
	if f == nil {
		if len(o.flows) >= 4096 {
			return
		}
		f = &flowObservation{}
		o.flows[t.Flow] = f
	}
	f.last = now
	if t.Flags&2 != 0 {
		f.scale = t.Scale
		f.scaleKnown = t.HasScale
	}
	if t.Flags&16 != 0 {
		w := t.Window
		if t.Flags&2 == 0 {
			peer := o.flows[t.Reverse()]
			if !f.scaleKnown || peer == nil || !peer.scaleKnown {
				w = t.Window
			} else {
				w <<= f.scale
			}
		}
		f.window = w
		if w == 0 {
			o.zeroWindow++
		}
		if o.minWindow == 0 || w < o.minWindow {
			o.minWindow = w
		}
		if w > o.maxWindow {
			o.maxWindow = w
		}
	}
	if !out && t.Flags&16 != 0 {
		if sent := o.flows[t.Reverse()]; sent != nil && !sent.at.IsZero() && int32(t.Ack-sent.end) >= 0 {
			o.rtt.observe(now.Sub(sent.at))
			o.samples++
			sent.at = time.Time{}
		}
	}
	if out && (t.Payload > 0 || t.Flags&2 != 0) {
		end := t.Seq + uint32(t.Payload)
		if t.Flags&2 != 0 {
			end++
		}
		if !f.at.IsZero() && int32(t.Seq-f.end) < 0 {
			o.retrans++
			f.at = time.Time{}
			return
		}
		if f.at.IsZero() {
			f.start = t.Seq
			f.end = end
			f.at = now
		}
	}
	if t.Flags&4 != 0 {
		delete(o.flows, t.Flow)
		delete(o.flows, t.Reverse())
	}
}
func (o *tcpObserver) report() {
	o.mu.Lock()
	defer o.mu.Unlock()
	log.Printf("[TCP-OBS] flows=%d rtt_samples=%d rtt_p50_upper=%s rtt_p95_upper=%s sampled_retrans=%d window_min=%d window_max=%d zero_window=%d (window scaling requires both SYNs; RTT includes queue/remote ACK delay)", len(o.flows), o.samples, o.rtt.percentile(50), o.rtt.percentile(95), o.retrans, o.minWindow, o.maxWindow, o.zeroWindow)
}
