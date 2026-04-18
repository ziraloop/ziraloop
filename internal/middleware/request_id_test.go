package middleware_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ziraloop/ziraloop/internal/middleware"
)

func TestRequestID_SetsResponseHeaderWhenNoIncomingHeader(t *testing.T) {
	handler := middleware.RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	got := rr.Header().Get("X-Request-ID")
	if got == "" {
		t.Fatal("expected X-Request-ID response header to be set")
	}
}

func TestRequestID_PreservesIncomingHeader(t *testing.T) {
	const incoming = "test-request-id-123"
	handler := middleware.RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.Header.Set("X-Request-ID", incoming)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	got := rr.Header().Get("X-Request-ID")
	if got != incoming {
		t.Fatalf("expected X-Request-ID %q, got %q", incoming, got)
	}
}

func TestRequestIDFromContext_ReturnsValue(t *testing.T) {
	var got string
	handler := middleware.RequestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = middleware.RequestIDFromContext(r.Context())
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if got == "" {
		t.Fatal("expected RequestIDFromContext to return a non-empty string")
	}
	header := rr.Header().Get("X-Request-ID")
	if got != header {
		t.Fatalf("context value %q != response header %q", got, header)
	}
}

func TestRequestIDFromContext_ReturnsEmptyWhenNoID(t *testing.T) {
	got := middleware.RequestIDFromContext(context.Background())
	if got != "" {
		t.Fatalf("expected empty string from background context, got %q", got)
	}
}
