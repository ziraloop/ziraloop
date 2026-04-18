package middleware

import (
	"context"
	"net/http"

	"github.com/google/uuid"
)

const requestIDHeader = "X-Request-ID"

type requestIDKey struct{}

// RequestID returns middleware that generates a UUIDv4 request ID for each
// request (or reuses the incoming X-Request-ID header if present), stores it
// in the request context, and sets it on the response header.
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(requestIDHeader)
		if id == "" {
			id = uuid.New().String()
		}
		ctx := context.WithValue(r.Context(), requestIDKey{}, id)
		w.Header().Set(requestIDHeader, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequestIDFromContext returns the request ID stored in the context, or an
// empty string if no ID is set.
func RequestIDFromContext(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey{}).(string)
	return id
}
