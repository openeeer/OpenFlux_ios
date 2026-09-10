package main

import (
	"strings"
	"sync"
	"testing"
	"unicode/utf8"
)

func TestLogBuffer(t *testing.T) {
	var b logBuffer
	b.Write([]byte(strings.Repeat("x", logLimit+10)))
	b.Write([]byte("latest error\n"))
	if len(b.data) > logLimit || !strings.HasSuffix(b.snapshot(), "latest error\n") {
		t.Fatal("buffer must be bounded and retain latest error")
	}
	b.Write([]byte{0, 0xff})
	if s := b.snapshot(); !utf8.ValidString(s) || strings.ContainsRune(s, 0) {
		t.Fatal("snapshot must be safe for C string and Swift UTF-8")
	}
}

func TestConcurrentLogs(t *testing.T) {
	var b logBuffer
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 100; j++ {
				b.Write([]byte("entry\n"))
				_ = b.snapshot()
			}
		}()
	}
	wg.Wait()
}
