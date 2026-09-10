package network

import "encoding/binary"

// TCPInfo validates IPv4/TCP lengths before inspecting flags or options.
type TCPInfo struct {
	Flow     [12]byte
	Seq, Ack uint32
	Flags    byte
	Payload  int
	Window   uint32
	Scale    uint8
	HasScale bool
}

func ParseTCP(p []byte) (TCPInfo, bool) {
	var t TCPInfo
	if len(p) < 40 || p[0]>>4 != 4 || p[9] != 6 {
		return t, false
	}
	ip := int(p[0]&15) * 4
	n := int(binary.BigEndian.Uint16(p[2:4]))
	if ip < 20 || n > len(p) || n < ip+20 || binary.BigEndian.Uint16(p[6:8])&0x3fff != 0 {
		return t, false
	}
	h := int(p[ip+12]>>4) * 4
	if h < 20 || ip+h > n {
		return t, false
	}
	copy(t.Flow[:8], p[12:20])
	copy(t.Flow[8:], p[ip:ip+4])
	t.Seq = binary.BigEndian.Uint32(p[ip+4:])
	t.Ack = binary.BigEndian.Uint32(p[ip+8:])
	t.Flags = p[ip+13]
	t.Payload = n - ip - h
	t.Window = uint32(binary.BigEndian.Uint16(p[ip+14:]))
	if t.Flags&2 != 0 {
		for i := ip + 20; i < ip+h; {
			kind := p[i]
			if kind == 0 {
				break
			}
			if kind == 1 {
				i++
				continue
			}
			if i+1 >= ip+h {
				break
			}
			l := int(p[i+1])
			if l < 2 || i+l > ip+h {
				break
			}
			if kind == 3 && l == 3 && p[i+2] <= 14 {
				t.Scale = p[i+2]
				t.HasScale = true
			}
			i += l
		}
	}
	return t, true
}

func (t TCPInfo) Reverse() [12]byte {
	var k [12]byte
	copy(k[:4], t.Flow[4:8])
	copy(k[4:8], t.Flow[:4])
	copy(k[8:10], t.Flow[10:12])
	copy(k[10:], t.Flow[8:10])
	return k
}
func UrgentTCP(p []byte) bool {
	t, ok := ParseTCP(p)
	return ok && (t.Flags&7 != 0 || (t.Flags&16 != 0 && t.Payload == 0))
}
