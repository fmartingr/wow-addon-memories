// Package apierr writes the JSON answers of the API: the success bodies and the error shape of the Protocol.
package apierr

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"
)

// JSON writes v with the given status.
func JSON(w http.ResponseWriter, status int, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		http.Error(w, "The server could not build the answer.", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	w.Write(append(body, '\n'))
}

// Write answers with {"error": code, "message": message}. The message is plain English that tells what happened and what to do.
func Write(w http.ResponseWriter, status int, code, message string) {
	JSON(w, status, map[string]string{"error": code, "message": message})
}

// Internal answers 500 without any detail of the failure, which the caller logs instead.
func Internal(w http.ResponseWriter) {
	Write(w, http.StatusInternalServerError, "internal",
		"The server could not finish the request. Try again later, and tell the website admin if it keeps happening.")
}

// Fail logs err as msg with the failed step, without any request data, and answers 500.
func Fail(w http.ResponseWriter, log *slog.Logger, msg, step string, err error) {
	log.Error(msg, "step", step, "err", err.Error())
	Internal(w)
}

// KeyRevoked answers 403 key_revoked.
func KeyRevoked(w http.ResponseWriter) {
	Write(w, http.StatusForbidden, "key_revoked", "The website admin blocked this key. Ask the admin of the website for help.")
}

// RetryAfter returns the Retry-After value, in whole seconds and at least 1.
func RetryAfter(d time.Duration) string {
	secs := int64((d + time.Second - 1) / time.Second)
	if secs < 1 {
		secs = 1
	}
	return strconv.FormatInt(secs, 10)
}

// RateLimited answers 429 with a Retry-After header.
func RateLimited(w http.ResponseWriter, wait time.Duration) {
	secs := RetryAfter(wait)
	w.Header().Set("Retry-After", secs)
	Write(w, http.StatusTooManyRequests, "rate_limited", "Too many requests. Wait "+secs+" seconds, then try again.")
}
