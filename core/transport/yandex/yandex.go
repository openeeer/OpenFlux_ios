package yandex

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"regexp"
	"runtime"
	rmetrics "runtime/metrics"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
	"universal-bypass-tool/network"
	"universal-bypass-tool/transport"
	"universal-bypass-tool/utils"
)

var cursorStart = []byte(`42["message",{"type":"cursor","cursor":"18;`)
var cursorEnd = []byte(`"}]`)
var clientConfigRE = regexp.MustCompile(`<script[^>]*id="client-config"[^>]*>(.*?)</script>`)

type YandexDocsInfo struct {
	CookieStr, Token, DocID, Origin, Host, WsURL string
	Permissions, OpenCmd                         map[string]interface{}
}
type queuedPacket struct {
	data []byte
	at   time.Time
}
type DocSession struct {
	tx     *atomic.Uint64
	Info   YandexDocsInfo
	Conn   *websocket.Conn
	UserID string
	mu     sync.Mutex
}

func (s *DocSession) write(data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if err := s.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second)); err != nil {
		return err
	}
	err := s.Conn.WriteMessage(websocket.TextMessage, data)
	if err == nil && s.tx != nil {
		s.tx.Add(1)
	}
	return err
}

type metrics struct {
	accepted, disconnected, queueTimeouts, writeErrors, invalidRX, wireTX                                     atomic.Uint64
	completion, writes                                                                                        latencyHistogram
	encodedTX, encodedRX, wsTX, wsRX, drops, batchBytes, batchPackets, batches, delayNS, delayCount, maxQueue atomic.Uint64
}

func (m *metrics) queue(n int) {
	for {
		old := m.maxQueue.Load()
		if uint64(n) <= old || m.maxQueue.CompareAndSwap(old, uint64(n)) {
			return
		}
	}
}

type YandexDocsTransport struct {
	receiveHook func([]byte) bool
	*transport.BaseTransport
	url         string
	queueCh     chan queuedPacket
	stopCh      chan struct{}
	stopOnce    sync.Once
	sessionMu   sync.RWMutex
	session     *DocSession
	userCounter atomic.Int32
	baseUserID  string
	metrics     metrics
	pending     *queuedPacket
	tcpStats    tcpObserver
}

func NewYandexDocsTransport(url string, c transport.TransportConfig) *YandexDocsTransport {
	return &YandexDocsTransport{BaseTransport: transport.NewBaseTransport(c), url: url, baseUserID: randUserID()}
}
func (t *YandexDocsTransport) Start() error {
	if err := t.BaseTransport.Start(); err != nil {
		return err
	}
	c := t.GetConfig()
	if t.url == "" || c.MaxQueueSize < 1 || c.YandexBatchBytes < 1 || c.YandexBatchPackets < 1 {
		return fmt.Errorf("invalid Yandex transport configuration")
	}
	t.queueCh = make(chan queuedPacket, c.MaxQueueSize)
	t.stopCh = make(chan struct{})
	t.baseUserID = randUserID()
	go t.writerLoop()
	go t.keepAliveLoop()
	if c.YandexStats {
		go t.statsLoop()
	}
	t.connect(0)
	return nil
}
func (t *YandexDocsTransport) Stop() error {
	t.BaseTransport.Stop()
	t.stopOnce.Do(func() {
		if t.stopCh != nil {
			close(t.stopCh)
		}
		if s := t.current(); s != nil {
			_ = s.Conn.Close()
		}
	})
	return t.BaseTransport.Stop()
}
func (t *YandexDocsTransport) Send(data []byte) error {
	if !t.IsRunning() || !t.IsConnected() {
		t.metrics.drops.Add(1)
		t.metrics.disconnected.Add(1)
		return fmt.Errorf("transport not connected")
	}
	p := queuedPacket{append([]byte(nil), data...), time.Now()}
	select {
	case t.queueCh <- p:
		t.metrics.accepted.Add(uint64(len(packetData(data))))
		t.metrics.queue(len(t.queueCh))
		return nil
	default:
	}
	wait := t.GetConfig().YandexQueueTimeout
	if wait <= 0 {
		select {
		case t.queueCh <- p:
			t.metrics.accepted.Add(uint64(len(packetData(data))))
			t.metrics.queue(len(t.queueCh))
			return nil
		default:
			t.metrics.drops.Add(1)
			return fmt.Errorf("Yandex write queue full")
		}
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case t.queueCh <- p:
		t.metrics.accepted.Add(uint64(len(packetData(data))))
		t.metrics.queue(len(t.queueCh))
		return nil
	case <-timer.C:
		t.metrics.queueTimeouts.Add(1)
		t.metrics.drops.Add(1)
		return fmt.Errorf("Yandex write queue full after %s", wait)
	case <-t.stopCh:
		t.metrics.drops.Add(1)
		return fmt.Errorf("transport stopped")
	}
}
func (t *YandexDocsTransport) current() *DocSession {
	t.sessionMu.RLock()
	defer t.sessionMu.RUnlock()
	return t.session
}
func (t *YandexDocsTransport) isCurrent(s *DocSession) bool {
	t.sessionMu.RLock()
	defer t.sessionMu.RUnlock()
	return t.session == s
}

func (t *YandexDocsTransport) connect(attempt int) {
	if !t.IsRunning() {
		return
	}
	go func() {
		uid := t.baseUserID + fmt.Sprintf("%03d", t.userCounter.Add(1)%1000)
		info, err := t.fetchDocInfo(t.url, uid)
		if err != nil {
			utils.Debugf("[YDOCS] fetchDocInfo failed: %v", err)
			t.reconnect(attempt)
			return
		}
		buf := t.GetConfig().YandexBatchBytes + 1024
		if buf < 4096 {
			buf = 4096
		}
		d := websocket.Dialer{HandshakeTimeout: 10 * time.Second, ReadBufferSize: 16 * 1024, WriteBufferSize: buf}
		h := http.Header{"User-Agent": {"Mozilla/5.0"}, "Origin": {info.Origin}, "Cookie": {info.CookieStr}, "Host": {info.Host}}
		conn, _, err := d.Dial(info.WsURL, h)
		if err != nil {
			utils.Debugf("[YDOCS] WebSocket dial failed: %v", err)
			t.reconnect(attempt)
			return
		}
		if !t.IsRunning() {
			_ = conn.Close()
			return
		}
		s := &DocSession{Info: info, Conn: conn, UserID: uid, tx: &t.metrics.wsTX}
		t.sessionMu.Lock()
		old := t.session
		t.session = s
		t.SetConnected(true)
		t.sessionMu.Unlock()
		if old != nil {
			_ = old.Conn.Close()
		}
		if err = t.auth(s); err != nil {
			_ = conn.Close()
			t.SetConnected(false)
			t.reconnect(attempt)
			return
		}
		for t.IsRunning() {
			_, msg, e := conn.ReadMessage()
			if e != nil {
				if t.isCurrent(s) {
					t.SetConnected(false)
					t.reconnect(attempt)
				}
				return
			}
			t.metrics.wsRX.Add(1)
			t.handle(s, msg)
		}
	}()
}
func (t *YandexDocsTransport) auth(s *DocSession) error {
	if err := s.write([]byte(`40{"token":"` + s.Info.Token + `"}`)); err != nil {
		return err
	}
	d := map[string]interface{}{"type": "auth", "docid": s.Info.DocID, "token": "fghhfgsjdgfjs", "user": map[string]interface{}{"id": s.UserID}, "editorType": 0, "lastOtherSaveTime": -1, "permissions": s.Info.Permissions, "openCmd": s.Info.OpenCmd, "coEditingMode": "fast", "jwtOpen": s.Info.Token}
	b, e := json.Marshal([]interface{}{"message", d})
	if e != nil {
		return e
	}
	return s.write(append([]byte("42"), b...))
}

func (t *YandexDocsTransport) writerLoop() {
	for {
		if t.pending != nil {
			first := *t.pending
			t.pending = nil
			t.writeBatch(t.collect(first))
			continue
		}
		select {
		case <-t.stopCh:
			return
		case first := <-t.queueCh:
			t.writeBatch(t.collect(first))
		}
	}
}
func (t *YandexDocsTransport) collect(first queuedPacket) []queuedPacket {
	c := t.GetConfig()
	out := []queuedPacket{first}
	n := len(first.data)
	if c.YandexLegacy || network.UrgentTCP(packetData(first.data)) || n >= c.YandexBatchBytes {
		return out
	}
	// Drain available packets without delaying an isolated packet or ACK.
	for n < c.YandexBatchBytes && len(out) < c.YandexBatchPackets {
		select {
		case p := <-t.queueCh:
			if n+len(p.data) > c.YandexBatchBytes {
				t.pending = &p
				return out
			}
			out = append(out, p)
			n += len(p.data)
			if network.UrgentTCP(packetData(p.data)) {
				return out
			}
		default:
			if len(out) == 1 || c.YandexBatchDelay <= 0 {
				return out
			}
			goto wait
		}
	}
	return out
wait:
	timer := time.NewTimer(c.YandexBatchDelay)
	defer timer.Stop()
	for n < c.YandexBatchBytes && len(out) < c.YandexBatchPackets {
		select {
		case p := <-t.queueCh:
			if n+len(p.data) > c.YandexBatchBytes {
				t.pending = &p
				return out
			}
			out = append(out, p)
			n += len(p.data)
			if network.UrgentTCP(packetData(p.data)) {
				return out
			}
		case <-timer.C:
			return out
		case <-t.stopCh:
			return out
		}
	}
	return out
}
func (t *YandexDocsTransport) writeBatch(batch []queuedPacket) {
	if len(batch) == 0 {
		return
	}
	s := t.current()
	if s == nil || !t.IsConnected() {
		t.metrics.drops.Add(uint64(len(batch)))
		return
	}
	ps := make([][]byte, len(batch))
	raw := 0
	for i, p := range batch {
		ps[i] = p.data
		raw += len(packetData(p.data))
		t.metrics.delayNS.Add(uint64(time.Since(p.at)))
		t.metrics.delayCount.Add(1)
	}
	var payload, prefix []byte
	if t.GetConfig().YandexLegacy {
		payload = transport.EncodeLegacyPayload(ps[0])
		prefix = cursorStart
	} else {
		var e error
		payload, e = encodeFrame(ps, t.GetConfig().YandexCompressBatches)
		if e != nil {
			t.metrics.drops.Add(uint64(len(batch)))
			return
		}
		prefix = append(append([]byte{}, cursorStart...), []byte("OF2;")...)
	}
	n := base64.StdEncoding.EncodedLen(len(payload))
	msg := make([]byte, len(prefix)+n+len(cursorEnd))
	o := copy(msg, prefix)
	base64.StdEncoding.Encode(msg[o:o+n], payload)
	copy(msg[o+n:], cursorEnd)
	started := time.Now()
	if t.GetConfig().YandexStats {
		for _, p := range batch {
			t.tcpStats.observe(packetData(p.data), true, started)
		}
	}
	err := s.write(msg)
	t.metrics.writes.observe(time.Since(started))
	if err != nil {
		t.metrics.writeErrors.Add(1)
		_ = s.Conn.Close()
		t.SetConnected(false)
		t.metrics.drops.Add(uint64(len(batch)))
		return
	}
	for _, p := range batch {
		t.RecordSend(len(packetData(p.data)))
		t.metrics.completion.observe(time.Since(p.at))
	}
	t.metrics.encodedTX.Add(uint64(n))
	t.metrics.wireTX.Add(uint64(len(msg)))
	t.metrics.batchBytes.Add(uint64(raw))
	t.metrics.batchPackets.Add(uint64(len(batch)))
	t.metrics.batches.Add(1)
}
func (t *YandexDocsTransport) keepAliveLoop() {
	ticker := time.NewTicker(t.GetConfig().KeepAliveInterval)
	defer ticker.Stop()
	for {
		select {
		case <-t.stopCh:
			return
		case <-ticker.C:
			if s := t.current(); s != nil {
				if s.write([]byte(`42["message",{"type":"cursor","cursor":"18;---KA---"}]`)) != nil {
					t.SetConnected(false)
					_ = s.Conn.Close()
				}
			}
		}
	}
}

func (t *YandexDocsTransport) handle(s *DocSession, msg []byte) {
	if bytes.Contains(msg, []byte("---KA---")) || bytes.Equal(msg, []byte("3")) {
		return
	}
	if bytes.Equal(msg, []byte("2")) {
		_ = s.write([]byte("3"))
		return
	}
	data, batch := extractPayload(msg)
	if len(data) == 0 {
		return
	}
	decoded := make([]byte, base64.StdEncoding.DecodedLen(len(data)))
	n, e := base64.StdEncoding.Decode(decoded, data)
	if e != nil {
		t.metrics.invalidRX.Add(1)
		return
	}
	if batch {
		ps, e := decodeFrame(decoded[:n])
		if e != nil {
			t.metrics.invalidRX.Add(1)
			utils.Debugf("[YDOCS] batch decode failed: %v", e)
			return
		}
		t.metrics.encodedRX.Add(uint64(len(data)))
		for _, p := range ps {
			if t.receiveHook != nil && !t.receiveHook(p) {
				continue
			}
			if t.GetConfig().YandexStats {
				t.tcpStats.observe(packetData(p), false, time.Now())
			}
			t.RecordReceive(len(packetData(p)))
			t.CallReceive(p)
		}
		return
	}
	p, e := transport.DecodeLegacyPayload(decoded[:n])
	if e == nil && len(p) > 0 {
		if t.receiveHook != nil && !t.receiveHook(p) {
			return
		}
		t.metrics.encodedRX.Add(uint64(len(data)))
		if t.GetConfig().YandexStats {
			t.tcpStats.observe(packetData(p), false, time.Now())
		}
		t.RecordReceive(len(p))
		t.CallReceive(p)
	}
}
func extractPayload(msg []byte) ([]byte, bool) {
	if i := bytes.Index(msg, []byte(`"cursor":"`)); i >= 0 {
		v := msg[i+10:]
		j := bytes.IndexByte(v, ';')
		if j < 0 {
			return nil, false
		}
		v = v[j+1:]
		k := bytes.IndexByte(v, '"')
		if k < 0 {
			return nil, false
		}
		v = v[:k]
		return bytes.TrimPrefix(v, []byte("OF2;")), bytes.HasPrefix(v, []byte("OF2;"))
	}
	if i := bytes.Index(msg, []byte(`"excelAdditionalInfo":"`)); i >= 0 {
		v := msg[i+len(`"excelAdditionalInfo":"`):]
		if j := bytes.IndexByte(v, '"'); j >= 0 {
			return v[:j], false
		}
	}
	return nil, false
}
func (t *YandexDocsTransport) reconnect(n int) {
	if !t.IsRunning() || n >= t.GetConfig().MaxReconnectAttempts {
		return
	}
	t.RecordReconnect()
	d := t.GetConfig().ReconnectDelay
	if d <= 0 {
		d = time.Second
	}
	time.AfterFunc(d, func() { t.connect(n + 1) })
}

func (t *YandexDocsTransport) statsLoop() {
	d := t.GetConfig().YandexStatsInterval
	if d <= 0 {
		d = 5 * time.Second
	}
	tick := time.NewTicker(d)
	defer tick.Stop()
	var rawTX, rawRX, encTX, encRX, wsTX, wsRX, alloc uint64
	var gc uint32
	cpuSamples := []rmetrics.Sample{{Name: "/cpu/classes/gc/total:cpu-seconds"}}
	rmetrics.Read(cpuSamples)
	lastGCCPU := cpuSamples[0].Value.Float64()
	var initial runtime.MemStats
	runtime.ReadMemStats(&initial)
	alloc = initial.TotalAlloc
	gc = initial.NumGC
	for {
		select {
		case <-t.stopCh:
			return
		case <-tick.C:
			st := t.Stats()
			var m runtime.MemStats
			runtime.ReadMemStats(&m)
			rmetrics.Read(cpuSamples)
			gcCPU := cpuSamples[0].Value.Float64()
			log.Printf("[RUNTIME] gc_cpu_seconds_delta=%.6f mallocs_total=%d gc_pause_total_ns=%d", gcCPU-lastGCCPU, m.Mallocs, m.PauseTotalNs)
			lastGCCPU = gcCPU
			b := t.metrics.batches.Load()
			avgB, avgP, avgPayload := uint64(0), uint64(0), uint64(0)
			if b > 0 {
				avgB = t.metrics.batchBytes.Load() / b
				avgP = t.metrics.batchPackets.Load() / b
				if packets := t.metrics.batchPackets.Load(); packets > 0 {
					avgPayload = t.metrics.batchBytes.Load() / packets
				}
			}
			dc := t.metrics.delayCount.Load()
			avgD := time.Duration(0)
			if dc > 0 {
				avgD = time.Duration(t.metrics.delayNS.Load() / dc)
			}
			sec := d.Seconds()
			log.Printf("[YDOCS-STATS] raw_tx=%.0fB/s raw_rx=%.0fB/s encoded_tx=%.0fB/s encoded_rx=%.0fB/s ws_tx=%.1f/s ws_rx=%.1f/s queue=%d queue_max=%d drops=%d reconnects=%d avg_payload=%d avg_batch=%dB/%dpkts queue_avg=%s goroutines=%d alloc=%.0fB/s gc=%d heap=%dB", float64(st.BytesSent-rawTX)/sec, float64(st.BytesReceived-rawRX)/sec, float64(t.metrics.encodedTX.Load()-encTX)/sec, float64(t.metrics.encodedRX.Load()-encRX)/sec, float64(t.metrics.wsTX.Load()-wsTX)/sec, float64(t.metrics.wsRX.Load()-wsRX)/sec, len(t.queueCh), t.metrics.maxQueue.Load(), t.metrics.drops.Load(), st.Reconnects, avgPayload, avgB, avgP, avgD, runtime.NumGoroutine(), float64(m.TotalAlloc-alloc)/sec, m.NumGC-gc, m.HeapAlloc)
			log.Printf("[YDOCS-DETAIL] accepted=%d raw_sent=%d json_sent=%d disconnected_drops=%d queue_timeouts=%d write_errors=%d invalid_rx=%d enqueue_to_write_p50_upper=%s p95_upper=%s p99_upper=%s write_p95_upper=%s", t.metrics.accepted.Load(), st.BytesSent, t.metrics.wireTX.Load(), t.metrics.disconnected.Load(), t.metrics.queueTimeouts.Load(), t.metrics.writeErrors.Load(), t.metrics.invalidRX.Load(), t.metrics.completion.percentile(50), t.metrics.completion.percentile(95), t.metrics.completion.percentile(99), t.metrics.writes.percentile(95))
			t.tcpStats.report()
			rawTX, rawRX = st.BytesSent, st.BytesReceived
			encTX, encRX = t.metrics.encodedTX.Load(), t.metrics.encodedRX.Load()
			wsTX, wsRX = t.metrics.wsTX.Load(), t.metrics.wsRX.Load()
			alloc, gc = m.TotalAlloc, m.NumGC
		}
	}
}

func (t *YandexDocsTransport) fetchDocInfo(url, uid string) (YandexDocsInfo, error) {
	c := newSafeHTTPClient(30 * time.Second)
	req, e := http.NewRequest("GET", url, nil)
	if e != nil {
		return YandexDocsInfo{}, e
	}
	req.Header.Set("User-Agent", "Mozilla/5.0")
	r, e := c.Do(req)
	if e != nil {
		return YandexDocsInfo{}, e
	}
	defer r.Body.Close()
	html, e := io.ReadAll(r.Body)
	if e != nil {
		return YandexDocsInfo{}, e
	}
	match := clientConfigRE.FindSubmatch(html)
	if len(match) < 2 {
		return YandexDocsInfo{}, fmt.Errorf("client config not found")
	}
	var cfg map[string]interface{}
	if e = json.Unmarshal(match[1], &cfg); e != nil {
		return YandexDocsInfo{}, e
	}
	oa, ok := cfg["officeActionData"].(map[string]interface{})
	if !ok {
		return YandexDocsInfo{}, fmt.Errorf("officeActionData missing")
	}
	ec, ok := oa["editor_config"].(map[string]interface{})
	if !ok {
		return YandexDocsInfo{}, fmt.Errorf("editor_config missing")
	}
	doc, ok := ec["document"].(map[string]interface{})
	if !ok {
		return YandexDocsInfo{}, fmt.Errorf("document missing")
	}
	bal, ok := oa["balancer_url"].(string)
	if !ok {
		return YandexDocsInfo{}, fmt.Errorf("balancer URL missing")
	}
	token, ok := ec["token"].(string)
	if !ok {
		return YandexDocsInfo{}, fmt.Errorf("token missing")
	}
	id, ok := doc["key"].(string)
	if !ok {
		return YandexDocsInfo{}, fmt.Errorf("document key missing")
	}
	perms, _ := doc["permissions"].(map[string]interface{})
	if perms == nil {
		perms = map[string]interface{}{}
	}
	cookies := []string{}
	for _, x := range r.Cookies() {
		cookies = append(cookies, x.Name+"="+x.Value)
	}
	host := strings.TrimPrefix(bal, "https://")
	ft, _ := doc["fileType"].(string)
	du, _ := doc["url"].(string)
	title, _ := doc["title"].(string)
	return YandexDocsInfo{strings.Join(cookies, "; "), token, id, bal, host, fmt.Sprintf("wss://%s/2024.1.1-375/doc/%s/c/?EIO=4&transport=websocket", host, id), perms, map[string]interface{}{"c": "open", "id": id, "userid": uid, "format": ft, "url": du, "title": title, "lcid": 25}}, nil
}
func randUserID() string {
	return fmt.Sprintf("%010d", rand.New(rand.NewSource(time.Now().UnixNano())).Intn(1000000000))
}
