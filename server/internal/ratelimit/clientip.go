package ratelimit

import (
	"net"
	"net/http"
	"net/netip"
	"strings"
)

// ClientIP returns the address of the client. It is the peer address, except when the peer is a trusted proxy: then
// it is the right-most X-Forwarded-For address that is not a trusted proxy. A header the proxy did not write cannot
// move the answer, because the walk starts at the right end, where only trusted proxies have appended.
// It returns the peer address when the header has no such address or has an entry that is not an address.
func ClientIP(r *http.Request, trusted []netip.Prefix) netip.Addr {
	peer := peerAddr(r.RemoteAddr)
	if !peer.IsValid() || !isTrusted(peer, trusted) {
		return peer
	}
	var hops []string
	for _, v := range r.Header.Values("X-Forwarded-For") {
		hops = append(hops, strings.Split(v, ",")...)
	}
	for i := len(hops) - 1; i >= 0; i-- {
		addr := hopAddr(strings.TrimSpace(hops[i]))
		if !addr.IsValid() {
			return peer
		}
		if !isTrusted(addr, trusted) {
			return addr
		}
	}
	return peer
}

// hopAddr reads one X-Forwarded-For entry. Some proxies write the entry with a port ("1.2.3.4:5678", "[::1]:5678"),
// and such an entry must still name the client, or every client behind the proxy would share the proxy's limit.
func hopAddr(hop string) netip.Addr {
	if addr, err := netip.ParseAddr(hop); err == nil {
		return addr.Unmap().WithZone("")
	}
	if ap, err := netip.ParseAddrPort(hop); err == nil {
		return ap.Addr().Unmap().WithZone("")
	}
	return netip.Addr{}
}

func peerAddr(remote string) netip.Addr {
	host, _, err := net.SplitHostPort(remote)
	if err != nil {
		host = remote
	}
	addr, err := netip.ParseAddr(host)
	if err != nil {
		return netip.Addr{}
	}
	return addr.Unmap().WithZone("")
}

func isTrusted(a netip.Addr, trusted []netip.Prefix) bool {
	for _, p := range trusted {
		if p.Contains(a) {
			return true
		}
	}
	return false
}

// IPKey is the rate-limit key of an address. An IPv6 client usually holds a whole /64, so the key is that prefix.
func IPKey(a netip.Addr) string {
	if !a.IsValid() {
		return "unknown"
	}
	if a.Is6() {
		return netip.PrefixFrom(a, 64).Masked().String()
	}
	return a.String()
}
