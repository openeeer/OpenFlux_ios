package yandex

import (
	"encoding/binary"
	"fmt"

	"github.com/pierrec/lz4/v4"
)

const (
	frameMagic      = "OF"
	frameVersion    = byte(2)
	frameHeaderSize = 10
	frameCompressed = byte(1 << 0)
	maxFrameBody    = 4 * 1024 * 1024
)

// encodeFrame preserves packet boundaries. Compression, when enabled, applies
// only to the whole body and is kept only when it removes at least 10%.
func encodeFrame(packets [][]byte, enableCompression bool) ([]byte, error) {
	if len(packets) == 0 || len(packets) > 0xffff {
		return nil, fmt.Errorf("invalid batch packet count: %d", len(packets))
	}

	bodyLen := 0
	for _, packet := range packets {
		if len(packet) == 0 || len(packet) > 0xffff {
			return nil, fmt.Errorf("invalid packet size: %d", len(packet))
		}
		bodyLen += 2 + len(packet)
	}
	if bodyLen > maxFrameBody {
		return nil, fmt.Errorf("batch body too large: %d", bodyLen)
	}

	body := make([]byte, bodyLen)
	offset := 0
	for _, packet := range packets {
		binary.BigEndian.PutUint16(body[offset:], uint16(len(packet)))
		offset += 2
		offset += copy(body[offset:], packet)
	}

	flags := byte(0)
	wireBody := body
	if enableCompression && len(body) >= 256 {
		compressed := make([]byte, lz4.CompressBlockBound(len(body)))
		if n, err := lz4.CompressBlock(body, compressed, nil); err == nil && n > 0 && n*10 < len(body)*9 {
			flags |= frameCompressed
			wireBody = compressed[:n]
		}
	}

	frame := make([]byte, frameHeaderSize+len(wireBody))
	copy(frame[:2], frameMagic)
	frame[2] = frameVersion
	frame[3] = flags
	binary.BigEndian.PutUint16(frame[4:], uint16(len(packets)))
	binary.BigEndian.PutUint32(frame[6:], uint32(len(body)))
	copy(frame[frameHeaderSize:], wireBody)
	return frame, nil
}

func decodeFrame(frame []byte) ([][]byte, error) {
	if len(frame) < frameHeaderSize || string(frame[:2]) != frameMagic || frame[2] != frameVersion {
		return nil, fmt.Errorf("unknown batch frame")
	}
	flags := frame[3]
	if flags&^frameCompressed != 0 {
		return nil, fmt.Errorf("unsupported batch flags: %02x", flags)
	}
	count := int(binary.BigEndian.Uint16(frame[4:]))
	bodyLen := int(binary.BigEndian.Uint32(frame[6:]))
	if count == 0 || bodyLen <= 0 || bodyLen > maxFrameBody {
		return nil, fmt.Errorf("invalid batch header")
	}

	body := frame[frameHeaderSize:]
	if flags&frameCompressed != 0 {
		decoded := make([]byte, bodyLen)
		n, err := lz4.UncompressBlock(body, decoded)
		if err != nil || n != bodyLen {
			return nil, fmt.Errorf("batch decompression failed")
		}
		body = decoded
	} else if len(body) != bodyLen {
		return nil, fmt.Errorf("invalid uncompressed batch length")
	}

	packets := make([][]byte, 0, count)
	for offset := 0; offset < len(body); {
		if len(body)-offset < 2 {
			return nil, fmt.Errorf("truncated packet length")
		}
		packetLen := int(binary.BigEndian.Uint16(body[offset:]))
		offset += 2
		if packetLen == 0 || packetLen > len(body)-offset {
			return nil, fmt.Errorf("invalid packet length")
		}
		packets = append(packets, body[offset:offset+packetLen])
		offset += packetLen
	}
	if len(packets) != count {
		return nil, fmt.Errorf("batch packet count mismatch")
	}
	return packets, nil
}
