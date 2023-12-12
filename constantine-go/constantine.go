/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

package constantine

/*
#cgo CFLAGS: -I"${SRCDIR}/../include"
#cgo !windows LDFLAGS: "${SRCDIR}/../lib/libconstantine.a"
// The ending in .lib is rejected, so we can't use the direct linking syntax:
//   https://github.com/golang/go/blob/46ea4ab/src/cmd/go/internal/work/security.go#L216
// #cgo windows LDFLAGS: "${SRCDIR}/../lib/constantine.lib"
#cgo windows LDFLAGS: -L"${SRCDIR}/../lib" -Wl,-Bstatic -lconstantine -Wl,-Bdynamic

#include <stdlib.h>
#include <constantine.h>
*/
import "C"
import (
	"errors"
	"unsafe"
)

// Threadpool API
// -----------------------------------------------------

type Threadpool struct {
	ctx *C.ctt_threadpool
}

func ThreadpoolNew(numThreads int) Threadpool {
	return Threadpool{
		ctx: C.ctt_threadpool_new(C.size_t(numThreads)),
	}
}

func (tp Threadpool) Shutdown() {
	C.ctt_threadpool_shutdown(tp.ctx)
}

// Ethereum EIP-4844 KZG API
// -----------------------------------------------------

type (
	EthKzgCommitment      [48]byte
	EthKzgProof           [48]byte
	EthBlob               [4096 * 32]byte
	EthKzgChallenge       [32]byte
	EthKzgEvalAtChallenge [32]byte
)

type EthKzgContext struct {
	cCtx *C.ctt_eth_kzg_context
}

func EthKzgContextNew(trustedSetupFile string) (ctx EthKzgContext, err error) {
	cFile := C.CString(trustedSetupFile)
	defer C.free(unsafe.Pointer(cFile))
	status := C.ctt_eth_trusted_setup_load(
		&ctx.cCtx,
		cFile,
		C.cttEthTSFormat_ckzg4844,
	)
	if status != C.cttEthTS_Success {
		err = errors.New(
			C.GoString(C.ctt_eth_trusted_setup_status_to_string(status)),
		)
	}
	return ctx, err
}

func (ctx EthKzgContext) Delete() {
	C.ctt_eth_trusted_setup_delete(ctx.cCtx)
}

func (ctx EthKzgContext) BlobToKZGCommitment(blob EthBlob) (commitment EthKzgCommitment, err error) {
	status := C.ctt_eth_kzg_blob_to_kzg_commitment(
		ctx.cCtx,
		(*C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitment)),
		(*C.ctt_eth_kzg_blob)(unsafe.Pointer(&blob)),
	)
	if status != C.cttEthKzg_Success {
		err = errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
	}
	return commitment, err
}

func (ctx EthKzgContext) ComputeKzgProof(blob EthBlob, z EthKzgChallenge) (proof EthKzgProof, y EthKzgEvalAtChallenge, err error) {
	status := C.ctt_eth_kzg_compute_kzg_proof(
		ctx.cCtx,
		(*C.ctt_eth_kzg_proof)(unsafe.Pointer(&proof)),
		(*C.ctt_eth_kzg_eval_at_challenge)(unsafe.Pointer(&y)),
		(*C.ctt_eth_kzg_blob)(unsafe.Pointer(&blob)),
		(*C.ctt_eth_kzg_challenge)(unsafe.Pointer(&z)),
	)
	if status != C.cttEthKzg_Success {
		err = errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
	}
	return proof, y, err
}

func (ctx EthKzgContext) VerifyKzgProof(commitment EthKzgCommitment, z EthKzgChallenge, y EthKzgEvalAtChallenge, proof EthKzgProof) (bool, error) {
	status := C.ctt_eth_kzg_verify_kzg_proof(
		ctx.cCtx,
		(*C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitment)),
		(*C.ctt_eth_kzg_challenge)(unsafe.Pointer(&z)),
		(*C.ctt_eth_kzg_eval_at_challenge)(unsafe.Pointer(&y)),
		(*C.ctt_eth_kzg_proof)(unsafe.Pointer(&proof)),
	)
	if status != C.cttEthKzg_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (ctx EthKzgContext) ComputeBlobKzgProof(blob EthBlob, commitment EthKzgCommitment) (proof EthKzgProof, err error) {
	status := C.ctt_eth_kzg_compute_blob_kzg_proof(
		ctx.cCtx,
		(*C.ctt_eth_kzg_proof)(unsafe.Pointer(&proof)),
		(*C.ctt_eth_kzg_blob)(unsafe.Pointer(&blob)),
		(*C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitment)),
	)
	if status != C.cttEthKzg_Success {
		err = errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
	}
	return proof, err
}

func (ctx EthKzgContext) VerifyBlobKzgProof(blob EthBlob, commitment EthKzgCommitment, proof EthKzgProof) (bool, error) {
	status := C.ctt_eth_kzg_verify_blob_kzg_proof(
		ctx.cCtx,
		(*C.ctt_eth_kzg_blob)(unsafe.Pointer(&blob)),
		(*C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitment)),
		(*C.ctt_eth_kzg_proof)(unsafe.Pointer(&proof)),
	)
	if status != C.cttEthKzg_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (ctx EthKzgContext) VerifyBlobKzgProofBatch(blobs []EthBlob, commitments []EthKzgCommitment, proofs []EthKzgProof, secureRandomeBytes [32]byte) (bool, error) {

	if len(blobs) != len(commitments) || len(blobs) != len(proofs) {
		return false, errors.New("VerifyBlobKzgProofBatch: Lengths of inputs do not match.")
	}

	status := C.ctt_eth_kzg_verify_blob_kzg_proof_batch(
		ctx.cCtx,
		*(**C.ctt_eth_kzg_blob)(unsafe.Pointer(&blobs)),
		*(**C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitments)),
		*(**C.ctt_eth_kzg_proof)(unsafe.Pointer(&proofs)),
		(C.size_t)(len(blobs)),
		(*C.uint8_t)(unsafe.Pointer(&secureRandomeBytes)),
	)
	if status != C.cttEthKzg_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}
