package auth

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

const vectorPath = "testdata/vector.json"

// vector is the shared test vector. The Dart client reads the same file, so a change to the signed string breaks both.
type vector struct {
	Note         string            `json:"note"`
	Seed         string            `json:"seed"`
	PublicKey    string            `json:"publicKey"`
	Method       string            `json:"method"`
	Path         string            `json:"path"`
	Time         int64             `json:"time"`
	Nonce        string            `json:"nonce"`
	Body         string            `json:"body"`
	BodySHA256   string            `json:"bodySha256"`
	SignedString string            `json:"signedString"`
	Signature    string            `json:"signature"`
	Headers      map[string]string `json:"headers"`
}

func seedBytes() []byte {
	seed := make([]byte, ed25519.SeedSize)
	for i := range seed {
		seed[i] = byte(i)
	}
	return seed
}

func nonceBytes() []byte {
	nonce := make([]byte, 16)
	for i := range nonce {
		nonce[i] = 0xa0 + byte(i)
	}
	return nonce
}

// buildVector derives the whole vector from the fixed inputs. Run `VECTOR_UPDATE=1 go test ./internal/auth -run TestVector`
// to write it again.
func buildVector() vector {
	priv := ed25519.NewKeyFromSeed(seedBytes())
	pub := priv.Public().(ed25519.PublicKey)
	v := vector{
		Note:   "Ed25519 signature of signedString (6 lines joined by \\n, no final newline). seed is the 32-byte private seed, base64url without padding like every other binary value. Written by internal/auth/signature_test.go.",
		Seed:   b64.EncodeToString(seedBytes()),
		Method: "POST",
		Path:   "/api/v1/characters?v=1",
		Time:   1794000000,
		Nonce:  b64.EncodeToString(nonceBytes()),
		Body:   `{"character":{"guid":"Player-1234-0ABCDEF1"},"journey":[],"trail":[]}`,
	}
	v.PublicKey = b64.EncodeToString(pub)
	v.SignedString = SignedString(v.Method, v.Path, v.Time, v.Nonce, []byte(v.Body))
	v.BodySHA256 = strings.Split(v.SignedString, "\n")[5]
	v.Signature = b64.EncodeToString(ed25519.Sign(priv, []byte(v.SignedString)))
	v.Headers = map[string]string{
		HeaderKey:       v.PublicKey,
		HeaderTime:      strconv.FormatInt(v.Time, 10),
		HeaderNonce:     v.Nonce,
		HeaderSignature: v.Signature,
	}
	return v
}

func loadVector(t *testing.T) vector {
	t.Helper()
	raw, err := os.ReadFile(vectorPath)
	if err != nil {
		t.Fatal(err)
	}
	var v vector
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestVector(t *testing.T) {
	want := buildVector()
	if os.Getenv("VECTOR_UPDATE") == "1" {
		raw, err := json.MarshalIndent(want, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(vectorPath, append(raw, '\n'), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	got := loadVector(t)
	if got.SignedString != want.SignedString || got.Signature != want.Signature || got.PublicKey != want.PublicKey {
		t.Fatalf("%s is stale. Run VECTOR_UPDATE=1 go test ./internal/auth -run TestVector", vectorPath)
	}
	lines := strings.Split(got.SignedString, "\n")
	if len(lines) != 6 || lines[0] != "memories-v1" || lines[1] != got.Method || lines[2] != got.Path ||
		lines[3] != strconv.FormatInt(got.Time, 10) || lines[4] != got.Nonce || len(lines[5]) != 64 {
		t.Errorf("signedString has the wrong lines: %q", got.SignedString)
	}
	if strings.HasSuffix(got.SignedString, "\n") {
		t.Error("signedString ends with a newline")
	}

	req := httptest.NewRequest(got.Method, got.Path, strings.NewReader(got.Body))
	for k, val := range got.Headers {
		req.Header.Set(k, val)
	}
	pub, err := Verify(req, []byte(got.Body), time.Unix(got.Time, 0))
	if err != nil {
		t.Fatalf("Verify of the vector: %v", err)
	}
	if b64.EncodeToString(pub) != got.PublicKey {
		t.Error("Verify returned another public key")
	}
}

type reqOpts struct {
	method, target string
	body           []byte
	time           int64
	nonce          []byte
	priv           ed25519.PrivateKey
}

func signed(o reqOpts) *http.Request {
	if o.method == "" {
		o.method = "POST"
	}
	if o.target == "" {
		o.target = "/api/v1/register"
	}
	if o.priv == nil {
		o.priv = ed25519.NewKeyFromSeed(seedBytes())
	}
	if o.nonce == nil {
		o.nonce = nonceBytes()
	}
	nonce := b64.EncodeToString(o.nonce)
	msg := SignedString(o.method, o.target, o.time, nonce, o.body)
	req := httptest.NewRequest(o.method, o.target, nil)
	req.Header.Set(HeaderKey, b64.EncodeToString(o.priv.Public().(ed25519.PublicKey)))
	req.Header.Set(HeaderTime, strconv.FormatInt(o.time, 10))
	req.Header.Set(HeaderNonce, nonce)
	req.Header.Set(HeaderSignature, b64.EncodeToString(ed25519.Sign(o.priv, []byte(msg))))
	return req
}

func TestVerifyTimeWindow(t *testing.T) {
	now := time.Unix(1794000000, 0)
	for _, tc := range []struct {
		name   string
		offset int64
		want   error
	}{
		{"same second", 0, nil},
		{"300 s in the past", -300, nil},
		{"300 s in the future", 300, nil},
		{"301 s in the past", -301, ErrClock},
		{"301 s in the future", 301, ErrClock},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Verify(signed(reqOpts{time: now.Unix() + tc.offset}), nil, now)
			if err != tc.want {
				t.Errorf("Verify = %v, want %v", err, tc.want)
			}
		})
	}
	if !strings.Contains(ErrClock.Message, "clock of your computer") {
		t.Errorf("the clock message does not point at the computer clock: %q", ErrClock.Message)
	}
}

func TestVerifyRejects(t *testing.T) {
	now := time.Unix(1794000000, 0)
	good := func() *http.Request { return signed(reqOpts{time: now.Unix(), body: []byte("{}")}) }
	rawKey := func(n int) string { return b64.EncodeToString(make([]byte, n)) }

	for _, tc := range []struct {
		name   string
		edit   func(*http.Request)
		body   string
		reason error
	}{
		{"wrong body", nil, "{ }", errBad},
		{"another method", func(r *http.Request) { r.Method = "PUT" }, "{}", errBad},
		{"another path", func(r *http.Request) { r.RequestURI = "/api/v1/me" }, "{}", errBad},
		{"another query", func(r *http.Request) { r.RequestURI = "/api/v1/register?a=1" }, "{}", errBad},
		{"another time", func(r *http.Request) { r.Header.Set(HeaderTime, "1794000001") }, "{}", errBad},
		{"another nonce", func(r *http.Request) { r.Header.Set(HeaderNonce, rawKey(16)) }, "{}", errBad},
		{"another key", func(r *http.Request) { r.Header.Set(HeaderKey, rawKey(32)) }, "{}", errBad},
		{"missing key", func(r *http.Request) { r.Header.Del(HeaderKey) }, "{}", errHeaders},
		{"missing time", func(r *http.Request) { r.Header.Del(HeaderTime) }, "{}", errHeaders},
		{"missing nonce", func(r *http.Request) { r.Header.Del(HeaderNonce) }, "{}", errHeaders},
		{"missing signature", func(r *http.Request) { r.Header.Del(HeaderSignature) }, "{}", errHeaders},
		{"key of 31 bytes", func(r *http.Request) { r.Header.Set(HeaderKey, rawKey(31)) }, "{}", errHeaders},
		{"key of 33 bytes", func(r *http.Request) { r.Header.Set(HeaderKey, rawKey(33)) }, "{}", errHeaders},
		{"nonce of 15 bytes", func(r *http.Request) { r.Header.Set(HeaderNonce, rawKey(15)) }, "{}", errHeaders},
		{"nonce of 17 bytes", func(r *http.Request) { r.Header.Set(HeaderNonce, rawKey(17)) }, "{}", errHeaders},
		{"signature of 63 bytes", func(r *http.Request) { r.Header.Set(HeaderSignature, rawKey(63)) }, "{}", errHeaders},
		{"padded base64", func(r *http.Request) { r.Header.Set(HeaderKey, base64.URLEncoding.EncodeToString(make([]byte, 32))) }, "{}", errHeaders},
		{"standard base64 alphabet", func(r *http.Request) { r.Header.Set(HeaderNonce, "+/+/+/+/+/+/+/+/+/+/+w") }, "{}", errHeaders},
		{"time with a plus", func(r *http.Request) { r.Header.Set(HeaderTime, "+1794000000") }, "{}", errHeaders},
		{"time with a fraction", func(r *http.Request) { r.Header.Set(HeaderTime, "1794000000.5") }, "{}", errHeaders},
		{"time with leading zeros", func(r *http.Request) { r.Header.Set(HeaderTime, "01794000000") }, "{}", errHeaders},
		{"time that is text", func(r *http.Request) { r.Header.Set(HeaderTime, "now") }, "{}", errHeaders},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := good()
			if tc.edit != nil {
				tc.edit(req)
			}
			_, err := Verify(req, []byte(tc.body), now)
			if err != tc.reason {
				t.Errorf("Verify = %v, want %v", err, tc.reason)
			}
		})
	}
}

func TestVerifyUsesTheRequestTargetAsSent(t *testing.T) {
	now := time.Unix(1794000000, 0)
	target := "/api/v1/me?x=%2Fa&y=1"
	req := signed(reqOpts{method: "GET", target: target, time: now.Unix()})
	if _, err := Verify(req, nil, now); err != nil {
		t.Fatalf("a query with an escape: %v", err)
	}
	// A request built by a client has no RequestURI; the URL gives the same target.
	req.RequestURI = ""
	if _, err := Verify(req, nil, now); err != nil {
		t.Fatalf("a request with no RequestURI: %v", err)
	}
}

func TestSignedStringOfAnEmptyBody(t *testing.T) {
	got := SignedString("GET", "/api/v1/me", 5, "n", nil)
	want := "memories-v1\nGET\n/api/v1/me\n5\nn\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	if got != want {
		t.Errorf("SignedString = %q, want %q", got, want)
	}
}
