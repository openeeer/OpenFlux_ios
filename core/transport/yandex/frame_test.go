package yandex

import (
	"bytes"
	"testing"
)

func TestFrameRoundTrip(t *testing.T) {
	want := [][]byte{[]byte("first"), []byte("second packet"), bytes.Repeat([]byte{7}, 300)}
	frame, err := encodeFrame(want, false)
	if err != nil {
		t.Fatal(err)
	}
	got, err := decodeFrame(frame)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(want) {
		t.Fatalf("got %d packets, want %d", len(got), len(want))
	}
	for i := range want {
		if !bytes.Equal(got[i], want[i]) {
			t.Fatalf("packet %d differs", i)
		}
	}
}

func TestCompressedFrameRoundTrip(t *testing.T) {
	want := [][]byte{bytes.Repeat([]byte("compressible "), 500)}
	frame, err := encodeFrame(want, true)
	if err != nil {
		t.Fatal(err)
	}
	if frame[3]&frameCompressed == 0 {
		t.Fatal("expected compression")
	}
	got, err := decodeFrame(frame)
	if err != nil || !bytes.Equal(got[0], want[0]) {
		t.Fatalf("round trip failed: %v", err)
	}
}

func TestDecodeFrameRejectsCorruption(t *testing.T) {
	if _, err := decodeFrame([]byte("OF\x02\x00")); err == nil {
		t.Fatal("expected malformed frame to fail")
	}
}

func TestExtractPayload(t *testing.T) {
	payload, batch := extractPayload([]byte(`42["message",{"type":"cursor","cursor":"18;OF2;YWJj"}]`))
	if !batch || string(payload) != "YWJj" {
		t.Fatalf("got batch=%v payload=%q", batch, payload)
	}
	payload, batch = extractPayload([]byte(`42["message",{"type":"cursor","cursor":"18;YWJj"}]`))
	if batch || string(payload) != "YWJj" {
		t.Fatalf("got batch=%v payload=%q", batch, payload)
	}
}
