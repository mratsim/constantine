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
		ctx: C.ctt_threadpool_new(C.int(numThreads)),
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
	threadpool Threadpool
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
	ctx.threadpool.ctx = nil
	return ctx, err
}

func (ctx *EthKzgContext) SetThreadpool(tp Threadpool) {
	ctx.threadpool = tp
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
		(*C.ctt_eth_kzg_opening_challenge)(unsafe.Pointer(&z)),
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
		(*C.ctt_eth_kzg_opening_challenge)(unsafe.Pointer(&z)),
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

func (ctx EthKzgContext) VerifyBlobKzgProofBatch(blobs []EthBlob, commitments []EthKzgCommitment, proofs []EthKzgProof, secureRandomBytes [32]byte) (bool, error) {

	if len(blobs) != len(commitments) || len(blobs) != len(proofs) {
		return false, errors.New("VerifyBlobKzgProofBatch: Lengths of inputs do not match.")
	}

	status := C.ctt_eth_kzg_verify_blob_kzg_proof_batch(
		ctx.cCtx,
		*(**C.ctt_eth_kzg_blob)(unsafe.Pointer(&blobs)),
		*(**C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitments)),
		*(**C.ctt_eth_kzg_proof)(unsafe.Pointer(&proofs)),
		(C.size_t)(len(blobs)),
		(*C.uint8_t)(unsafe.Pointer(&secureRandomBytes)),
	)
	if status != C.cttEthKzg_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

// Ethereum EIP-4844 KZG API - Parallel
// -----------------------------------------------------

func (ctx EthKzgContext) BlobToKZGCommitmentParallel(blob EthBlob) (commitment EthKzgCommitment, err error) {
	if ctx.threadpool.ctx == nil {
		return commitment, errors.New("BlobToKZGCommitmentParallel: The threadpool is not configured.")
	}
	status := C.ctt_eth_kzg_blob_to_kzg_commitment_parallel(
		ctx.threadpool.ctx, ctx.cCtx,
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

func (ctx EthKzgContext) ComputeKzgProofParallel(blob EthBlob, z EthKzgChallenge) (proof EthKzgProof, y EthKzgEvalAtChallenge, err error) {
	if ctx.threadpool.ctx == nil {
		return proof, y, errors.New("ComputeKzgProofParallel: The Constantine's threadpool is not configured.")
	}
	status := C.ctt_eth_kzg_compute_kzg_proof_parallel(
		ctx.threadpool.ctx, ctx.cCtx,
		(*C.ctt_eth_kzg_proof)(unsafe.Pointer(&proof)),
		(*C.ctt_eth_kzg_eval_at_challenge)(unsafe.Pointer(&y)),
		(*C.ctt_eth_kzg_blob)(unsafe.Pointer(&blob)),
		(*C.ctt_eth_kzg_opening_challenge)(unsafe.Pointer(&z)),
	)
	if status != C.cttEthKzg_Success {
		err = errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
	}
	return proof, y, err
}

func (ctx EthKzgContext) ComputeBlobKzgProofParallel(blob EthBlob, commitment EthKzgCommitment) (proof EthKzgProof, err error) {
	if ctx.threadpool.ctx == nil {
		return proof, errors.New("ComputeBlobKzgProofParallel: The threadpool is not configured.")
	}
	status := C.ctt_eth_kzg_compute_blob_kzg_proof_parallel(
		ctx.threadpool.ctx, ctx.cCtx,
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

func (ctx EthKzgContext) VerifyBlobKzgProofParallel(blob EthBlob, commitment EthKzgCommitment, proof EthKzgProof) (bool, error) {
	if ctx.threadpool.ctx == nil {
		return false, errors.New("VerifyBlobKzgProofParallel: The threadpool is not configured.")
	}
	status := C.ctt_eth_kzg_verify_blob_kzg_proof_parallel(
		ctx.threadpool.ctx, ctx.cCtx,
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

func (ctx EthKzgContext) VerifyBlobKzgProofBatchParallel(blobs []EthBlob, commitments []EthKzgCommitment, proofs []EthKzgProof, secureRandomBytes [32]byte) (bool, error) {
	if len(blobs) != len(commitments) || len(blobs) != len(proofs) {
		return false, errors.New("VerifyBlobKzgProofBatch: Lengths of inputs do not match.")
	}
	if ctx.threadpool.ctx == nil {
		return false, errors.New("VerifyBlobKzgProofBatch: The threadpool is not configured.")
	}
	status := C.ctt_eth_kzg_verify_blob_kzg_proof_batch_parallel(
		ctx.threadpool.ctx, ctx.cCtx,
		*(**C.ctt_eth_kzg_blob)(unsafe.Pointer(&blobs)),
		*(**C.ctt_eth_kzg_commitment)(unsafe.Pointer(&commitments)),
		*(**C.ctt_eth_kzg_proof)(unsafe.Pointer(&proofs)),
		(C.size_t)(len(blobs)),
		(*C.uint8_t)(unsafe.Pointer(&secureRandomBytes)),
	)
	if status != C.cttEthKzg_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

// Ethereum BLS signatures
// -----------------------------------------------------

func getAddr[T any](arg []T) (unsafe.Pointer) {
	// Makes sure to not access a non existant 0 element if the slice is empty
	if len(arg) > 0 {
		return unsafe.Pointer(&arg[0])
	} else {
		return nil
	}
}


type (
	EthBlsSecKey    C.ctt_eth_bls_seckey
	EthBlsPubKey    C.ctt_eth_bls_pubkey
	EthBlsSignature C.ctt_eth_bls_signature
)

func (pub EthBlsPubKey) IsZero() bool {
	status := C.ctt_eth_bls_pubkey_is_zero((*C.ctt_eth_bls_pubkey)(&pub))
	return bool(status)
}

func (sec *EthBlsSecKey) Deserialize(src [32]byte) (bool, error) {
	status := C.ctt_eth_bls_deserialize_seckey((*C.ctt_eth_bls_seckey)(sec),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecScalar_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) DerivePubKey(sec EthBlsSecKey) {
	C.ctt_eth_bls_derive_pubkey((*C.ctt_eth_bls_pubkey)(pub), (*C.ctt_eth_bls_seckey)(&sec))
}

func (pub *EthBlsPubKey) Verify(message []byte, sig EthBlsSignature) (bool, error) {
	status := C.ctt_eth_bls_verify((*C.ctt_eth_bls_pubkey)(pub),
		(*C.byte)(getAddr(message)),
		(C.ptrdiff_t)(len(message)),
		(*C.ctt_eth_bls_signature)(&sig),
	)
	if status != C.cttEthBls_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_bls_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig EthBlsSignature) IsZero() bool {
	status := C.ctt_eth_bls_signature_is_zero((*C.ctt_eth_bls_signature)(&sig))
	return bool(status)
}

func (pub1 EthBlsPubKey) AreEqual(pub2 EthBlsPubKey) bool {
	status := C.ctt_eth_bls_pubkeys_are_equal((*C.ctt_eth_bls_pubkey)(&pub1), (*C.ctt_eth_bls_pubkey)(&pub2))
	return bool(status)
}

func (sig1 EthBlsSignature) AreEqual(sig2 EthBlsSignature) bool {
	status := C.ctt_eth_bls_signatures_are_equal((*C.ctt_eth_bls_signature)(&sig1), (*C.ctt_eth_bls_signature)(&sig2))
	return bool(status)
}

func (sec *EthBlsSecKey) Validate() (bool, error) {
	status := C.ctt_eth_bls_validate_seckey((*C.ctt_eth_bls_seckey)(sec))
	if status != C.cttCodecScalar_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) Validate() (bool, error) {
	status := C.ctt_eth_bls_validate_pubkey((*C.ctt_eth_bls_pubkey)(pub))
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) Validate() (bool, error) {
	status := C.ctt_eth_bls_validate_signature((*C.ctt_eth_bls_signature)(sig))
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sec *EthBlsSecKey) Serialize(dst *[32]byte) (bool, error) {
	status := C.ctt_eth_bls_serialize_seckey((*C.byte)(unsafe.Pointer(dst)),
		(*C.ctt_eth_bls_seckey)(sec),
	)
	if status != C.cttCodecScalar_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) SerializeCompressed(dst *[48]byte) (bool, error) {
	status := C.ctt_eth_bls_serialize_pubkey_compressed((*C.byte)(unsafe.Pointer(dst)),
		(*C.ctt_eth_bls_pubkey)(pub),
	)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) SerializeCompressed(dst *[96]byte) (bool, error) {
	status := C.ctt_eth_bls_serialize_signature_compressed((*C.byte)(unsafe.Pointer(dst)),
		(*C.ctt_eth_bls_signature)(sig),
	)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) DeserializeCompressedUnchecked(src [48]byte) (bool, error) {
	status := C.ctt_eth_bls_deserialize_pubkey_compressed_unchecked((*C.ctt_eth_bls_pubkey)(pub),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) DeserializeCompressedUnchecked(src [96]byte) (bool, error) {
	status := C.ctt_eth_bls_deserialize_signature_compressed_unchecked((*C.ctt_eth_bls_signature)(sig),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) DeserializeCompressed(src [48]byte) (bool, error) {
	status := C.ctt_eth_bls_deserialize_pubkey_compressed((*C.ctt_eth_bls_pubkey)(pub),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) DeserializeCompressed(src [96]byte) (bool, error) {
	status := C.ctt_eth_bls_deserialize_signature_compressed((*C.ctt_eth_bls_signature)(sig),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) Sign(sec EthBlsSecKey, message []byte) {
	C.ctt_eth_bls_sign((*C.ctt_eth_bls_signature)(sig), (*C.ctt_eth_bls_seckey)(&sec),
		(*C.byte)(getAddr(message)),
		(C.ptrdiff_t)(len(message)),
	)
}

func FastAggregateVerify(pubkeys []EthBlsPubKey, message []byte, aggregate_sig EthBlsSignature) (bool, error) {
	if len(pubkeys) == 0 {
		err := errors.New(
			"No public keys given.",
		)
		return false, err
	}
	status := C.ctt_eth_bls_fast_aggregate_verify((*C.ctt_eth_bls_pubkey)(getAddr(pubkeys)),
		(C.ptrdiff_t)(len(pubkeys)),
		(*C.byte)(getAddr(message)),
		(C.ptrdiff_t)(len(message)),
		(*C.ctt_eth_bls_signature)(&aggregate_sig),
	)
	if status != C.cttEthBls_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_bls_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

// NOTE: C.ctt_eth_bls_batch_sig_accumulator is an incomplete struct. Therefore
// we use 2 functions on the Nim side to (de)allocate storage for the struct.
type ethBlsBatchSigAccumulator struct {
	ctx *C.ctt_eth_bls_batch_sig_accumulator
}
func ethBlsBatchSigAccumulatorAlloc() (accum ethBlsBatchSigAccumulator) {
	accum.ctx = C.ctt_eth_bls_alloc_batch_sig_accumulator()
	return accum
}

func ethBlsBatchSigAccumulatorFree(accum ethBlsBatchSigAccumulator) {
	C.ctt_eth_bls_free_batch_sig_accumulator(accum.ctx)
}

func (accum ethBlsBatchSigAccumulator) init(secureRandomBytes [32]byte, accumSepTag []byte) {
	C.ctt_eth_bls_init_batch_sig_accumulator((*C.ctt_eth_bls_batch_sig_accumulator)(accum.ctx),
		(*C.byte)(&secureRandomBytes[0]),
		(*C.byte)(getAddr(accumSepTag)),
		(C.ptrdiff_t)(len(accumSepTag)),
	)
}

func (accum ethBlsBatchSigAccumulator) update(pub EthBlsPubKey, message []byte, sig EthBlsSignature) bool {
	status := C.ctt_eth_bls_update_batch_sig_accumulator((*C.ctt_eth_bls_batch_sig_accumulator)(accum.ctx),
		(*C.ctt_eth_bls_pubkey)(&pub),
		(*C.byte)(getAddr(message)),
		(C.ptrdiff_t)(len(message)),
		(*C.ctt_eth_bls_signature)(&sig),
	)
	return bool(status)
}

func (accum ethBlsBatchSigAccumulator) finalVerify() bool {
	status := C.ctt_eth_bls_final_verify_batch_sig_accumulator(
		(*C.ctt_eth_bls_batch_sig_accumulator)(accum.ctx),
	)
	return bool(status)
}


func BatchVerifySoA(pubkeys []EthBlsPubKey, messages [][]byte, signatures []EthBlsSignature, secureRandomBytes [32]byte) (bool, error) {
	if len(pubkeys) == 0 {
		err := errors.New(
			C.GoString(
				C.ctt_eth_bls_status_to_string(C.cttEthBls_ZeroLengthAggregation),
			),
		)
		return false, err

	} else if len(pubkeys) != len(messages) {
		err := errors.New("Number of public keys must match number of messages.")
		return false, err
	} else if len(pubkeys) != len(signatures) {
		err := errors.New("Number of public keys must match number of signatures.")
		return false, err
	}

	// Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
	for _, pub := range pubkeys {
		if pub.IsZero() {
			err := errors.New(
				C.GoString(
					C.ctt_eth_bls_status_to_string(C.cttEthBls_PointAtInfinity),
				),
			)
			return false, err
		}
	}
	for _, sig := range signatures {
		if sig.IsZero() {
			err := errors.New(
				C.GoString(
					C.ctt_eth_bls_status_to_string(C.cttEthBls_PointAtInfinity),
				),
			)
			return false, err
		}
	}

	// NOTE: We *must* use the New / Free functions!
	accum := ethBlsBatchSigAccumulatorAlloc()
	defer ethBlsBatchSigAccumulatorFree(accum)
	accum.init(secureRandomBytes, []byte("serial"))

	for i, pub := range pubkeys {
		if !accum.update(pub, messages[i], signatures[i]) {
			err := errors.New(
				C.GoString(
					C.ctt_eth_bls_status_to_string(C.cttEthBls_VerificationFailure),
				),
			)
			return false, err
		}
	}

	return accum.finalVerify(), nil
}

type BatchVerifyTriplet struct {
	pub EthBlsPubKey
	message []byte
	sig EthBlsSignature
}

func BatchVerifyAoS(triplets []BatchVerifyTriplet, secureRandomBytes [32]byte) (bool, error) {
	if len(triplets) == 0 {
		err := errors.New(
			C.GoString(
				C.ctt_eth_bls_status_to_string(C.cttEthBls_ZeroLengthAggregation),
			),
		)
		return false, err
	}
	// Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
	for _, trp := range triplets {
		if trp.pub.IsZero() || trp.sig.IsZero() {
			err := errors.New(
				C.GoString(
					C.ctt_eth_bls_status_to_string(C.cttEthBls_PointAtInfinity),
				),
			)
			return false, err
		}
	}
	// NOTE: We *must* use the New / Free functions!
	accum := ethBlsBatchSigAccumulatorAlloc()
	defer ethBlsBatchSigAccumulatorFree(accum)
	accum.init(secureRandomBytes, []byte("serial"))

	for _, trp := range triplets {
		if !accum.update(trp.pub, trp.message, trp.sig) {
			err := errors.New(
				C.GoString(
					C.ctt_eth_bls_status_to_string(C.cttEthBls_VerificationFailure),
				),
			)
			return false, err
		}
	}

	return accum.finalVerify(), nil
}

// --------------------------------
// ------- EVM precompiles --------
// --------------------------------

func EvmSha256(result *[32]byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_sha256((*C.byte)(&result[0]),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmModexp(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_modexp((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBn254G1Add(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bn254_g1add((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBn254G1Mul(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bn254_g1mul((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBn254G1EcPairingCheck(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bn254_ecpairingcheck((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381G1Add(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_g1add((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381G1Mul(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_g1mul((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381G1Msm(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_g1msm((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381G2Add(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_g2add((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381G2Mul(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_g2mul((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381G2Msm(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_g2msm((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381PairingCheck(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_pairingcheck((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381MapFpToG1(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_map_fp_to_g1((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func EvmBls12381MapFp2ToG2(result []byte, inputs []byte) (bool, error) {
	status := C.ctt_eth_evm_bls12381_map_fp2_to_g2((*C.byte)(getAddr(result)),
		(C.ptrdiff_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.ptrdiff_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}
