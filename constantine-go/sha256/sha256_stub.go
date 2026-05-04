//go:build !cgo

// sha256/sha256 - Pure Go stub for linting without CGO
// This file provides type definitions so golangci-lint can typecheck
// when CGO_ENABLED=0 or when C toolchain is not available.
package sha256

// Sha256Context is a stub type for linting.
// The actual implementation uses CGo to call Constantine's C library.
type Sha256Context struct {
	// Internal state - opaque for pure Go stub
	data [256]byte
}

// New creates a new SHA256 context (stub for linting).
func New() Sha256Context {
	return Sha256Context{}
}

// Init initializes the SHA256 context (stub for linting).
func (ctx *Sha256Context) Init() {
	// Stub - no-op in pure Go mode
}

// Update processes more data (stub for linting).
func (ctx *Sha256Context) Update(data []byte) {
	// Stub - no-op in pure Go mode
}

// Finish finalizes the hash and writes the result (stub for linting).
func (ctx *Sha256Context) Finish(data [32]byte) {
	// Stub - no-op in pure Go mode
}

// Clear clears the context state (stub for linting).
func (ctx *Sha256Context) Clear() {
	// Stub - no-op in pure Go mode
}

// Hash computes SHA256 of the message (stub for linting).
func Hash(message []byte, clearMemory bool) (digest [32]byte) {
	// Stub - returns zero digest in pure Go mode
	// Actual implementation uses Constantine's optimized C code
	return [32]byte{}
}