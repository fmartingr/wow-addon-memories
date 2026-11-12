// Package config reads the server settings from environment variables.
package config

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
)

const (
	RegistrationInvite = "invite"
	RegistrationOpen   = "open"
)

const (
	miB = int64(1) << 20
	giB = int64(1) << 30
)

// Config holds every setting of the server. Load fills each field, so a zero value is not a usable Config.
type Config struct {
	PublicAddr     string
	AdminAddr      string
	DataDir        string
	WebDir         string
	SiteURL        string
	SiteName       string
	GitHubURL      string
	CurseForgeURL  string
	ExampleURL     string
	Registration   string
	TrustedProxies []netip.Prefix

	SentryDSN         string
	SentryEnvironment string

	MaxUploadBytes       int64
	MaxShotBytes         int64
	MaxPixels            int64
	MaxDecodedBytes      int64
	MaxText              int64
	MaxRecords           int64
	MaxChunks            int64
	MaxPoints            int64
	MaxCharactersPerKey  int64
	MaxDataBytesPerKey   int64
	MaxShotBytesPerKey   int64
	MaxConcurrentUploads int64
	RateSignedPerMinute  int64
	RateRegisterPerHour  int64
	RatePublicPerMinute  int64
}

type intSetting struct {
	env  string
	dst  *int64
	std  int64
	what string
}

// Load reads the settings with getenv. An unset or empty variable takes its default.
// Every bad value is reported in one error.
func Load(getenv func(string) string) (Config, error) {
	c := Config{}
	var problems []error
	bad := func(env, why string) {
		problems = append(problems, fmt.Errorf("%s %s", env, why))
	}
	str := func(env, def string) string {
		if v := strings.TrimSpace(getenv(env)); v != "" {
			return v
		}
		return def
	}

	c.PublicAddr = str("MEMORIES_PUBLIC_ADDR", ":8080")
	c.AdminAddr = str("MEMORIES_ADMIN_ADDR", "127.0.0.1:8081")
	if err := listenAddr(c.PublicAddr); err != nil {
		bad("MEMORIES_PUBLIC_ADDR", err.Error())
	}
	if err := listenAddr(c.AdminAddr); err != nil {
		bad("MEMORIES_ADMIN_ADDR", err.Error())
	}
	c.DataDir = str("MEMORIES_DATA_DIR", "./data")
	c.WebDir = str("MEMORIES_WEB_DIR", "../web")
	c.SiteName = str("MEMORIES_SITE_NAME", "WoW Journey")

	site, err := webURL(str("MEMORIES_SITE_URL", "http://localhost:8080"), false)
	if err != nil {
		bad("MEMORIES_SITE_URL", err.Error())
	}
	c.SiteURL = site

	gh, err := webURL(str("MEMORIES_GITHUB_URL", "https://github.com/fmartingr/wow-addon-memories"), true)
	if err != nil {
		bad("MEMORIES_GITHUB_URL", err.Error())
	}
	c.GitHubURL = gh

	cf, err := webURL(str("MEMORIES_CURSEFORGE_URL", "https://www.curseforge.com/wow/addons/memories"), true)
	if err != nil {
		bad("MEMORIES_CURSEFORGE_URL", err.Error())
	}
	c.CurseForgeURL = cf

	example, err := webURL(str("MEMORIES_EXAMPLE_URL", "https://wowjourney.xyz/forever/eu/brumamar/neral"), true)
	if err != nil {
		bad("MEMORIES_EXAMPLE_URL", err.Error())
	}
	c.ExampleURL = example

	switch c.Registration = str("MEMORIES_REGISTRATION", RegistrationInvite); c.Registration {
	case RegistrationInvite, RegistrationOpen:
	default:
		bad("MEMORIES_REGISTRATION", fmt.Sprintf("is %q, but it must be %q or %q.", c.Registration, RegistrationInvite, RegistrationOpen))
	}

	if raw := strings.TrimSpace(getenv("MEMORIES_TRUSTED_PROXIES")); raw != "" {
		for _, part := range strings.Split(raw, ",") {
			prefix, err := netip.ParsePrefix(strings.TrimSpace(part))
			if err != nil {
				bad("MEMORIES_TRUSTED_PROXIES", fmt.Sprintf("has %q, which is not a CIDR such as 10.0.0.0/8.", strings.TrimSpace(part)))
				continue
			}
			c.TrustedProxies = append(c.TrustedProxies, prefix.Masked())
		}
	}

	c.SentryDSN = str("MEMORIES_SENTRY_DSN", "")
	c.SentryEnvironment = str("MEMORIES_SENTRY_ENVIRONMENT", "production")

	for _, s := range []intSetting{
		{"MEMORIES_MAX_UPLOAD_BYTES", &c.MaxUploadBytes, 16 * miB, "bytes"},
		{"MEMORIES_MAX_SHOT_BYTES", &c.MaxShotBytes, 15 * miB, "bytes"},
		{"MEMORIES_MAX_PIXELS", &c.MaxPixels, 50_000_000, "pixels"},
		{"MEMORIES_MAX_DECODED_BYTES", &c.MaxDecodedBytes, 64 * miB, "bytes"},
		{"MEMORIES_MAX_TEXT", &c.MaxText, 512, "bytes"},
		{"MEMORIES_MAX_RECORDS", &c.MaxRecords, 500_000, "records"},
		{"MEMORIES_MAX_CHUNKS", &c.MaxChunks, 50_000, "chunks"},
		{"MEMORIES_MAX_POINTS", &c.MaxPoints, 20_000, "points"},
		{"MEMORIES_MAX_CHARACTERS_PER_KEY", &c.MaxCharactersPerKey, 50, "characters"},
		{"MEMORIES_MAX_DATA_BYTES_PER_KEY", &c.MaxDataBytesPerKey, 512 * miB, "bytes"},
		{"MEMORIES_MAX_SHOT_BYTES_PER_KEY", &c.MaxShotBytesPerKey, 5 * giB, "bytes"},
		{"MEMORIES_MAX_CONCURRENT_UPLOADS", &c.MaxConcurrentUploads, 2, "uploads"},
		{"MEMORIES_RATE_SIGNED_PER_MINUTE", &c.RateSignedPerMinute, 30, "requests"},
		{"MEMORIES_RATE_REGISTER_PER_HOUR", &c.RateRegisterPerHour, 10, "registrations"},
		{"MEMORIES_RATE_PUBLIC_PER_MINUTE", &c.RatePublicPerMinute, 600, "requests"},
	} {
		*s.dst = s.std
		raw := strings.TrimSpace(getenv(s.env))
		if raw == "" {
			continue
		}
		n, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || n < 1 {
			bad(s.env, fmt.Sprintf("is %q, but it must be a whole number of %s, 1 or more.", raw, s.what))
			continue
		}
		*s.dst = n
	}

	if len(problems) > 0 {
		return Config{}, errors.Join(problems...)
	}
	return c, nil
}

// webURL accepts an http or https address with a host. The site URL may carry no path, because the router serves
// character pages from the root; the GitHub URL keeps its path. A trailing slash is dropped.
func webURL(raw string, allowPath bool) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Hostname() == "" {
		return "", fmt.Errorf("is %q, which is not a web address. Write it like https://example.com", raw)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", fmt.Errorf("is %q, but it must start with http:// or https://.", raw)
	}
	if u.User != nil || strings.ContainsAny(raw, "?#") {
		return "", fmt.Errorf("is %q, but it must have no user name, query or fragment.", raw)
	}
	path := strings.TrimRight(u.EscapedPath(), "/")
	if path != "" && !allowPath {
		return "", fmt.Errorf("is %q, but it must have no path. Use the address of the site root.", raw)
	}
	return u.Scheme + "://" + u.Host + path, nil
}

// listenAddr accepts a host:port address with a numeric port, such as :8080 or 127.0.0.1:8081.
func listenAddr(addr string) error {
	_, port, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("is %q, which is not a host:port address such as :8080 or 127.0.0.1:8081.", addr)
	}
	if _, err := strconv.ParseUint(port, 10, 16); err != nil {
		return fmt.Errorf("is %q, but its port must be a number from 0 to 65535.", addr)
	}
	return nil
}
