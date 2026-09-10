package yandex

import (
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"syscall"
	"time"
)

// docHostSuffixes are the hosts fetchDocInfo is allowed to reach. The API layer
// validates the doc_url an operator submits, but validation at the edge is not
// enough on its own: a permitted host can answer with a 302 pointing anywhere,
// and Go's default client follows redirects.
var docHostSuffixes = []string{"yandex.ru", "yandex.net", "yandex.com"}

// newSafeHTTPClient returns a client that cannot be steered at the host's own
// network.
//
// Two separate guards, because they cover different attacks:
//
//   - CheckRedirect stops an allowlisted host from bouncing the request to an
//     internal address.
//   - The dialer's Control hook rejects non-public destinations at connect
//     time. Checking the URL alone is insufficient: DNS can resolve a permitted
//     name to 127.0.0.1 or 169.254.169.254 after the URL has been accepted
//     (DNS rebinding), and a redirect could point at a name we never inspected.
func newSafeHTTPClient(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		KeepAlive: 30 * time.Second,
		Control: func(network, address string, _ syscall.RawConn) error {
			host, _, err := net.SplitHostPort(address)
			if err != nil {
				return fmt.Errorf("unparsable dial address %q", address)
			}
			ip := net.ParseIP(host)
			if ip == nil {
				return fmt.Errorf("dial address %q is not an IP", address)
			}
			if !isPublicIP(ip) {
				return fmt.Errorf("refusing to connect to non-public address %s", ip)
			}
			return nil
		},
	}

	return &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			DialContext:           dialer.DialContext,
			TLSHandshakeTimeout:   10 * time.Second,
			ResponseHeaderTimeout: 20 * time.Second,
			MaxIdleConns:          4,
			IdleConnTimeout:       30 * time.Second,
		},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return fmt.Errorf("too many redirects")
			}
			if !hostAllowedForFetch(req.URL) {
				return fmt.Errorf("redirect to %q is not allowed", req.URL.Hostname())
			}
			return nil
		},
	}
}

func hostAllowedForFetch(u *url.URL) bool {
	if !strings.EqualFold(u.Scheme, "https") {
		return false
	}
	if u.User != nil {
		return false
	}
	host := strings.ToLower(u.Hostname())
	if host == "" || net.ParseIP(host) != nil {
		return false
	}
	for _, s := range docHostSuffixes {
		if host == s || strings.HasSuffix(host, "."+s) {
			return true
		}
	}
	return false
}

// isPublicIP reports whether an address is routable on the public internet.
// Everything a cloud instance would consider its own identity or its private
// network is excluded.
func isPublicIP(ip net.IP) bool {
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() ||
		ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsInterfaceLocalMulticast() || ip.IsMulticast() {
		return false
	}
	// Carrier-grade NAT (100.64.0.0/10) is not "private" per net.IP but is
	// still not a public destination, and 169.254.169.254 is covered above.
	if ip4 := ip.To4(); ip4 != nil {
		if ip4[0] == 100 && ip4[1] >= 64 && ip4[1] <= 127 {
			return false
		}
		if ip4[0] == 0 {
			return false
		}
		// net.IP classifies the limited broadcast address as neither
		// unspecified nor multicast, so it needs an explicit test.
		if ip4[0] == 255 && ip4[1] == 255 && ip4[2] == 255 && ip4[3] == 255 {
			return false
		}
	}
	return true
}
