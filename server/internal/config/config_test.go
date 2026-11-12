package config

import (
	"net/netip"
	"reflect"
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadDefaults(t *testing.T) {
	c, err := Load(env(nil))
	if err != nil {
		t.Fatal(err)
	}
	want := Config{
		PublicAddr:           ":8080",
		AdminAddr:            "127.0.0.1:8081",
		DataDir:              "./data",
		WebDir:               "../web",
		SiteURL:              "http://localhost:8080",
		SiteName:             "WoW Journey",
		GitHubURL:            "https://github.com/fmartingr/wow-addon-memories",
		CurseForgeURL:        "https://www.curseforge.com/wow/addons/memories",
		ExampleURL:           "https://wowjourney.xyz/forever/eu/brumamar/neral",
		Registration:         "invite",
		MaxUploadBytes:       16 << 20,
		MaxShotBytes:         15 << 20,
		MaxPixels:            50_000_000,
		MaxDecodedBytes:      64 << 20,
		MaxText:              512,
		MaxRecords:           500_000,
		MaxChunks:            50_000,
		MaxPoints:            20_000,
		MaxCharactersPerKey:  50,
		MaxDataBytesPerKey:   512 << 20,
		MaxShotBytesPerKey:   5 << 30,
		MaxConcurrentUploads: 2,
		RateSignedPerMinute:  30,
		RateRegisterPerHour:  10,
		RatePublicPerMinute:  600,
	}
	if c.TrustedProxies != nil {
		t.Errorf("TrustedProxies = %v, want none", c.TrustedProxies)
	}
	if !equal(c, want) {
		t.Errorf("defaults = %+v, want %+v", c, want)
	}
}

func equal(a, b Config) bool {
	a.TrustedProxies, b.TrustedProxies = nil, nil
	return reflect.DeepEqual(a, b)
}

func TestLoadEachVariable(t *testing.T) {
	c, err := Load(env(map[string]string{
		"MEMORIES_PUBLIC_ADDR":            "127.0.0.1:9000",
		"MEMORIES_ADMIN_ADDR":             "0.0.0.0:9001",
		"MEMORIES_DATA_DIR":               "/srv/data",
		"MEMORIES_WEB_DIR":                "/srv/web",
		"MEMORIES_SITE_URL":               "https://journey.example.com",
		"MEMORIES_SITE_NAME":              "My Journey",
		"MEMORIES_GITHUB_URL":             "https://github.com/me/fork",
		"MEMORIES_CURSEFORGE_URL":         "https://www.curseforge.com/wow/addons/fork",
		"MEMORIES_EXAMPLE_URL":            "https://journey.example.com/forever/eu/realm/me/",
		"MEMORIES_REGISTRATION":           "open",
		"MEMORIES_TRUSTED_PROXIES":        "10.0.0.0/8, 172.18.0.5/32",
		"MEMORIES_MAX_UPLOAD_BYTES":       "100",
		"MEMORIES_MAX_SHOT_BYTES":         "200",
		"MEMORIES_MAX_PIXELS":             "300",
		"MEMORIES_MAX_DECODED_BYTES":      "310",
		"MEMORIES_MAX_TEXT":               "320",
		"MEMORIES_MAX_RECORDS":            "330",
		"MEMORIES_MAX_CHUNKS":             "340",
		"MEMORIES_MAX_POINTS":             "350",
		"MEMORIES_MAX_CHARACTERS_PER_KEY": "4",
		"MEMORIES_MAX_DATA_BYTES_PER_KEY": "500",
		"MEMORIES_MAX_SHOT_BYTES_PER_KEY": "600",
		"MEMORIES_MAX_CONCURRENT_UPLOADS": "3",
		"MEMORIES_RATE_SIGNED_PER_MINUTE": "7",
		"MEMORIES_RATE_REGISTER_PER_HOUR": "8",
		"MEMORIES_RATE_PUBLIC_PER_MINUTE": "9",
	}))
	if err != nil {
		t.Fatal(err)
	}
	want := Config{
		PublicAddr: "127.0.0.1:9000", AdminAddr: "0.0.0.0:9001", DataDir: "/srv/data", WebDir: "/srv/web",
		SiteURL: "https://journey.example.com", SiteName: "My Journey", GitHubURL: "https://github.com/me/fork",
		CurseForgeURL: "https://www.curseforge.com/wow/addons/fork", ExampleURL: "https://journey.example.com/forever/eu/realm/me",
		Registration: "open", MaxUploadBytes: 100, MaxShotBytes: 200, MaxPixels: 300, MaxDecodedBytes: 310, MaxText: 320,
		MaxRecords: 330, MaxChunks: 340, MaxPoints: 350, MaxCharactersPerKey: 4,
		MaxDataBytesPerKey: 500, MaxShotBytesPerKey: 600, MaxConcurrentUploads: 3, RateSignedPerMinute: 7, RateRegisterPerHour: 8,
		RatePublicPerMinute: 9,
	}
	if !equal(c, want) {
		t.Errorf("config = %+v, want %+v", c, want)
	}
	wantProxies := []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8"), netip.MustParsePrefix("172.18.0.5/32")}
	if len(c.TrustedProxies) != 2 || c.TrustedProxies[0] != wantProxies[0] || c.TrustedProxies[1] != wantProxies[1] {
		t.Errorf("TrustedProxies = %v, want %v", c.TrustedProxies, wantProxies)
	}
}

func TestLoadURLs(t *testing.T) {
	tests := []struct {
		name, key, value, want, wantErr string
	}{
		{"site trailing slash", "MEMORIES_SITE_URL", "https://example.com/", "https://example.com", ""},
		{"site with port", "MEMORIES_SITE_URL", "http://127.0.0.1:9000", "http://127.0.0.1:9000", ""},
		{"site with path", "MEMORIES_SITE_URL", "https://example.com/journey", "", "no path"},
		{"site with query", "MEMORIES_SITE_URL", "https://example.com/?a=1", "", "no user name, query or fragment"},
		{"site with fragment", "MEMORIES_SITE_URL", "https://example.com/#a", "", "no user name, query or fragment"},
		{"site with user", "MEMORIES_SITE_URL", "https://me@example.com", "", "no user name, query or fragment"},
		{"site ftp", "MEMORIES_SITE_URL", "ftp://example.com", "", "http:// or https://"},
		{"site no scheme", "MEMORIES_SITE_URL", "example.com", "", "not a web address"},
		{"site no host", "MEMORIES_SITE_URL", "https://", "", "not a web address"},
		{"site junk", "MEMORIES_SITE_URL", "http://exa mple.com", "", "not a web address"},
		{"github trailing slash", "MEMORIES_GITHUB_URL", "https://github.com/a/b/", "https://github.com/a/b", ""},
		{"github bad scheme", "MEMORIES_GITHUB_URL", "javascript:alert(1)", "", "MEMORIES_GITHUB_URL"},
		{"github keeps escapes", "MEMORIES_GITHUB_URL", "https://github.com/a/b%2Fc", "https://github.com/a/b%2Fc", ""},
		{"github empty takes the default", "MEMORIES_GITHUB_URL", "", "https://github.com/fmartingr/wow-addon-memories", ""},
		{"curseforge bad scheme", "MEMORIES_CURSEFORGE_URL", "javascript:alert(1)", "", "MEMORIES_CURSEFORGE_URL"},
		{"curseforge trailing slash", "MEMORIES_CURSEFORGE_URL", "https://www.curseforge.com/wow/addons/x/", "https://www.curseforge.com/wow/addons/x", ""},
		{"example with query", "MEMORIES_EXAMPLE_URL", "https://example.com/a?b=1", "", "MEMORIES_EXAMPLE_URL"},
		{"example trailing slash", "MEMORIES_EXAMPLE_URL", "https://example.com/forever/eu/r/me/", "https://example.com/forever/eu/r/me", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			c, err := Load(env(map[string]string{tc.key: tc.value}))
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) || !strings.Contains(err.Error(), tc.key) {
					t.Fatalf("err = %v, want it to name %s and contain %q", err, tc.key, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			got := map[string]string{
				"MEMORIES_GITHUB_URL":     c.GitHubURL,
				"MEMORIES_CURSEFORGE_URL": c.CurseForgeURL,
				"MEMORIES_EXAMPLE_URL":    c.ExampleURL,
			}[tc.key]
			if got == "" {
				got = c.SiteURL
			}
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestLoadBadValues(t *testing.T) {
	tests := []struct{ key, value, wantErr string }{
		{"MEMORIES_PUBLIC_ADDR", "8080", "not a host:port address"},
		{"MEMORIES_PUBLIC_ADDR", "localhost", "not a host:port address"},
		{"MEMORIES_ADMIN_ADDR", "127.0.0.1:http", "port must be a number"},
		{"MEMORIES_ADMIN_ADDR", "127.0.0.1:70000", "port must be a number"},
		{"MEMORIES_REGISTRATION", "closed", `must be "invite" or "open"`},
		{"MEMORIES_REGISTRATION", "OPEN", "must be"},
		{"MEMORIES_TRUSTED_PROXIES", "10.0.0.1", "not a CIDR"},
		{"MEMORIES_TRUSTED_PROXIES", "10.0.0.0/8,nope", `"nope"`},
		{"MEMORIES_MAX_UPLOAD_BYTES", "abc", "whole number"},
		{"MEMORIES_MAX_UPLOAD_BYTES", "0", "1 or more"},
		{"MEMORIES_MAX_UPLOAD_BYTES", "-5", "1 or more"},
		{"MEMORIES_MAX_SHOT_BYTES", "1.5", "whole number"},
		{"MEMORIES_MAX_PIXELS", "x", "pixels"},
		{"MEMORIES_MAX_DECODED_BYTES", "0", "bytes"},
		{"MEMORIES_MAX_TEXT", "0", "bytes"},
		{"MEMORIES_MAX_RECORDS", "0", "records"},
		{"MEMORIES_MAX_CHUNKS", "0", "chunks"},
		{"MEMORIES_MAX_POINTS", "0", "points"},
		{"MEMORIES_MAX_CHARACTERS_PER_KEY", "0", "characters"},
		{"MEMORIES_MAX_DATA_BYTES_PER_KEY", "0", "bytes"},
		{"MEMORIES_MAX_SHOT_BYTES_PER_KEY", "0", "bytes"},
		{"MEMORIES_MAX_CONCURRENT_UPLOADS", "0", "uploads"},
		{"MEMORIES_RATE_SIGNED_PER_MINUTE", "0", "requests"},
		{"MEMORIES_RATE_REGISTER_PER_HOUR", "0", "registrations"},
		{"MEMORIES_RATE_PUBLIC_PER_MINUTE", "0", "requests"},
	}
	for _, tc := range tests {
		t.Run(tc.key+"="+tc.value, func(t *testing.T) {
			_, err := Load(env(map[string]string{tc.key: tc.value}))
			if err == nil || !strings.Contains(err.Error(), tc.key) || !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("err = %v, want it to name %s and contain %q", err, tc.key, tc.wantErr)
			}
		})
	}
}

func TestLoadReportsEveryProblem(t *testing.T) {
	_, err := Load(env(map[string]string{"MEMORIES_REGISTRATION": "x", "MEMORIES_SITE_URL": "nope"}))
	if err == nil || !strings.Contains(err.Error(), "MEMORIES_REGISTRATION") || !strings.Contains(err.Error(), "MEMORIES_SITE_URL") {
		t.Fatalf("err = %v, want both variables named", err)
	}
}

func TestLoadTrimsSpaces(t *testing.T) {
	c, err := Load(env(map[string]string{"MEMORIES_SITE_NAME": "  Spaced  ", "MEMORIES_REGISTRATION": " open "}))
	if err != nil {
		t.Fatal(err)
	}
	if c.SiteName != "Spaced" || c.Registration != "open" {
		t.Errorf("got %q and %q", c.SiteName, c.Registration)
	}
}
