// sha256/sha256
package sha256

/*
#cgo CFLAGS: -I"${SRCDIR}/../../include"
#cgo !windows LDFLAGS: "${SRCDIR}/../../lib/libconstantine.a"
// The ending in .lib is rejected, so we can't use the direct linking syntax:
//   https://github.com/golang/go/blob/46ea4ab/src/cmd/go/internal/work/security.go#L216
// #cgo windows LDFLAGS: "${SRCDIR}/../../lib/constantine.lib"
#cgo windows LDFLAGS: -L"${SRCDIR}/../../lib" -Wl,-Bstatic -lconstantine -Wl,-Bdynamic

#include <stdlib.h>
#include <constantine.h>

*/
import "C"
import (
	"unsafe"
)

func getAddr[T any](arg []T) (unsafe.Pointer) {
	// Makes sure to not access a non existant 0 element if the slice is empty
	if len(arg) > 0 {
		return unsafe.Pointer(&arg[0])
	} else {
		return nil
	}
}

// Constantine's SHA256 API
type Sha256Context C.ctt_sha256_context

func New() (ctx Sha256Context) {
	return ctx
}

func (ctx *Sha256Context) Init() {
	C.ctt_sha256_init((*C.ctt_sha256_context)(ctx))
}

func (ctx *Sha256Context) Update(data []byte) {
	C.ctt_sha256_update((*C.ctt_sha256_context)(ctx),
		(*C.byte)(unsafe.Pointer(&data[0])),
		(C.size_t)(len(data)),
	)
}

func (ctx *Sha256Context) Finish(data [32]byte) {
	C.ctt_sha256_finish((*C.ctt_sha256_context)(ctx),
		(*C.byte)(unsafe.Pointer(&data[0])),
	)
}

func (ctx *Sha256Context) Clear() {
	C.ctt_sha256_clear((*C.ctt_sha256_context)(ctx))
}

func Hash(message []byte, clearMemory bool) (digest [32]byte) {
	C.ctt_sha256_hash((*C.byte)(unsafe.Pointer(&digest)),
		(*C.byte)(unsafe.Pointer(&message[0])),
		(C.size_t)(len(message)),
		(C.ctt_bool)(clearMemory),
	)
	return digest
}
