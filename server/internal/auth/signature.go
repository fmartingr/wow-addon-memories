// Package auth checks the Ed25519 signature of a request and gates the API routes that need a key.
package auth

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"net/http"
	"strconv"
	"time"
)

// Header names of a signed request.
const (
	HeaderKey       = "Memories-Key"
	HeaderTime      = "Memories-Time"
	HeaderNonce     = "Memories-Nonce"
	HeaderSignature = "Memories-Signature"
)

const (
	// MaxSkew is how far, in seconds, the signed time may be from the server time, in either direction.
	MaxSkew     = 300
	nonceLength = 16
	signedTag   = "memories-v1"
)

// Error is a failed signature check. Message is plain English for the API response.
type Error struct{ Message string }

func (e *Error) Error() string { return e.Message }

var (
	errHeaders = &Error{"The request has no valid signature. Update the app, then try again."}
	errBad     = &Error{"The signature does not match the request. Update the app, and check that the key file is not damaged."}
	// ErrClock is the error of a time outside the window. Its message points at the clock because that is the usual cause.
	ErrClock = &Error{"The time of the request is more than 5 minutes away from the time of the server. Check that the clock of your computer is correct."}
	// ErrReplay is the error of a nonce that the server already saw.
	ErrReplay = &Error{"The server already received this request. Send a new request."}
)

// Headers are the parsed signature headers of a request.
type Headers struct {
	Public    ed25519.PublicKey
	Time      int64
	Nonce     []byte
	Signature []byte
}

var b64 = base64.RawURLEncoding.Strict()

// Parse reads the four headers. It checks only their shape, not the signature, so a caller can reject a request before it reads the body.
func Parse(r *http.Request) (Headers, error) {
	var h Headers
	var err error
	if h.Public, err = b64.DecodeString(r.Header.Get(HeaderKey)); err != nil || len(h.Public) != ed25519.PublicKeySize {
		return Headers{}, errHeaders
	}
	timeText := r.Header.Get(HeaderTime)
	if h.Time, err = strconv.ParseInt(timeText, 10, 64); err != nil || strconv.FormatInt(h.Time, 10) != timeText {
		return Headers{}, errHeaders
	}
	if h.Nonce, err = b64.DecodeString(r.Header.Get(HeaderNonce)); err != nil || len(h.Nonce) != nonceLength {
		return Headers{}, errHeaders
	}
	if h.Signature, err = b64.DecodeString(r.Header.Get(HeaderSignature)); err != nil || len(h.Signature) != ed25519.SignatureSize {
		return Headers{}, errHeaders
	}
	return h, nil
}

// requestTarget is the path with the query string exactly as the client sent it.
func requestTarget(r *http.Request) string {
	if len(r.RequestURI) > 0 && r.RequestURI[0] == '/' {
		return r.RequestURI
	}
	return r.URL.RequestURI()
}

// SignedString builds the 6 lines the client signs. The lines are joined with "\n" and the string has no final newline.
func SignedString(method, target string, unixTime int64, nonce string, body []byte) string {
	sum := sha256.Sum256(body)
	return signedTag + "\n" + method + "\n" + target + "\n" + strconv.FormatInt(unixTime, 10) + "\n" + nonce + "\n" + hex.EncodeToString(sum[:])
}

// Verify checks the signature headers against the request and the exact body bytes, and returns the public key.
// It rejects a missing or malformed header, a wrong signature and a time more than MaxSkew seconds from now.
// It does not check the nonce, because that needs the database.
func Verify(r *http.Request, body []byte, now time.Time) (ed25519.PublicKey, error) {
	h, err := Parse(r)
	if err != nil {
		return nil, err
	}
	return verifyHeaders(r, h, body, now)
}

// checkTime returns ErrClock when the signed time is more than MaxSkew seconds from now.
func checkTime(signed int64, now time.Time) error {
	if unix := now.Unix(); signed < unix-MaxSkew || signed > unix+MaxSkew {
		return ErrClock
	}
	return nil
}

// verifyHeaders is Verify for headers that Parse already read.
func verifyHeaders(r *http.Request, h Headers, body []byte, now time.Time) (ed25519.PublicKey, error) {
	if err := checkTime(h.Time, now); err != nil {
		return nil, err
	}
	msg := SignedString(r.Method, requestTarget(r), h.Time, r.Header.Get(HeaderNonce), body)
	if !ed25519.Verify(h.Public, []byte(msg), h.Signature) {
		return nil, errBad
	}
	return h.Public, nil
}
