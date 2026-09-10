package yandex

import (
	"net"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

// The URL-layer check catches a redirect aimed at an internal address. It has
// to be strict about the scheme and about userinfo, because both can be used to
// disguise the real destination.
func TestHostAllowedForFetch(t *testing.T) {
	allowed := []string{
		"https://disk.yandex.ru/i/abc",
		"https://yandex.ru/x",
		"https://docs.yandex.net/y",
		"https://yandex.com/z",
		"https://a.b.c.yandex.ru/z",
	}
	for _, raw := range allowed {
		u, err := url.Parse(raw)
		if err != nil {
			t.Fatalf("parse %q: %v", raw, err)
		}
		if !hostAllowedForFetch(u) {
			t.Errorf("rejected %q, want allowed", raw)
		}
	}

	rejected := []string{
		// Internal targets a redirect could point at.
		"https://169.254.169.254/latest/meta-data/",
		"https://127.0.0.1/",
		"https://10.0.0.1/",
		"https://[::1]/",
		"https://[fd00::1]/",
		"https://localhost/x",
		// Plaintext: a redirect to http would expose the request body.
		"http://disk.yandex.ru/i/abc",
		// Credentials in the authority disguise the real host.
		"https://disk.yandex.ru@evil.tld/i/abc",
		// Lookalikes that must not match on a bare suffix test.
		"https://notyandex.ru/x",
		"https://yandex.ru.evil.tld/x",
		"https://evil-yandex.ru/x",
	}
	for _, raw := range rejected {
		u, err := url.Parse(raw)
		if err != nil {
			continue
		}
		if hostAllowedForFetch(u) {
			t.Errorf("allowed %q, want rejected", raw)
		}
	}
}

// The dialer guard is what actually stops DNS rebinding and any redirect that
// slipped past the URL check, so every non-public range must be refused.
func TestIsPublicIPRejectsInternalRanges(t *testing.T) {
	internal := []string{
		"127.0.0.1",
		"::1",
		"10.0.0.1",
		"172.16.0.1",
		"192.168.1.1",
		"169.254.169.254", // cloud metadata
		"169.254.1.1",
		"0.0.0.0",
		"224.0.0.1", // multicast
		"255.255.255.255",
		"fd00::1",    // unique local
		"fe80::1",    // link local
		"100.64.0.1", // carrier-grade NAT
		"100.127.255.254",
	}
	for _, s := range internal {
		ip := net.ParseIP(s)
		if ip == nil {
			t.Fatalf("bad test input %q", s)
		}
		if isPublicIP(ip) {
			t.Errorf("isPublicIP(%s) = true, want false", s)
		}
	}

	public := []string{"8.8.8.8", "1.1.1.1", "77.88.55.88", "2606:4700::1111", "100.63.0.1", "100.128.0.1"}
	for _, s := range public {
		ip := net.ParseIP(s)
		if ip == nil {
			t.Fatalf("bad test input %q", s)
		}
		if !isPublicIP(ip) {
			t.Errorf("isPublicIP(%s) = false, want true", s)
		}
	}
}

// The client must not inherit Go's default redirect policy, which follows up to
// ten hops to anywhere.
func TestSafeClientRefusesRedirectOffAllowlist(t *testing.T) {
	c := newSafeHTTPClient(0)
	if c.CheckRedirect == nil {
		t.Fatal("safe client has no CheckRedirect; it would follow redirects anywhere")
	}

	via := []*http.Request{{}}
	req, _ := http.NewRequest(http.MethodGet, "https://169.254.169.254/latest/meta-data/", nil)
	err := c.CheckRedirect(req, via)
	if err == nil {
		t.Fatal("redirect to the metadata endpoint was allowed")
	}
	if !strings.Contains(err.Error(), "not allowed") {
		t.Fatalf("unexpected error: %v", err)
	}

	// A redirect that stays inside the allowlist is normal and must work.
	ok, _ := http.NewRequest(http.MethodGet, "https://disk.yandex.ru/i/moved", nil)
	if err := c.CheckRedirect(ok, via); err != nil {
		t.Fatalf("in-allowlist redirect rejected: %v", err)
	}
}

func TestSafeClientCapsRedirectChain(t *testing.T) {
	c := newSafeHTTPClient(0)
	via := make([]*http.Request, 5)
	req, _ := http.NewRequest(http.MethodGet, "https://disk.yandex.ru/i/loop", nil)
	if err := c.CheckRedirect(req, via); err == nil {
		t.Fatal("redirect loop was not capped")
	}
}
