package main

import (
	"strings"
	"sync"
)

const logLimit = 64 * 1024

// Retain recent diagnostics across failed connection attempts, not app launches.
type logBuffer struct {
	mu   sync.Mutex
	data []byte
}

func (b *logBuffer) Write(p []byte) (int, error) {
	n := len(p)
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(p) >= logLimit {
		b.data = append(b.data[:0], p[len(p)-logLimit:]...)
	} else {
		if excess := len(b.data) + len(p) - logLimit; excess > 0 {
			copy(b.data, b.data[excess:])
			b.data = b.data[:len(b.data)-excess]
		}
		b.data = append(b.data, p...)
	}
	return n, nil
}

func (b *logBuffer) snapshot() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return strings.ToValidUTF8(strings.ReplaceAll(string(b.data), "\x00", ""), "�")
}
