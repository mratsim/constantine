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

func (ctx EthKzgContext) BlobToKzgCommitment(blob EthBlob) (commitment EthKzgCommitment, err error) {
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
		if status == C.cttEthKzg_VerificationFailure {
			return false, nil
		}

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
		if status == C.cttEthKzg_VerificationFailure {
			return false, nil
		}

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
		if status == C.cttEthKzg_VerificationFailure {
			return false, nil
		}

		err := errors.New(
			C.GoString(C.ctt_eth_kzg_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

// Ethereum EIP-4844 KZG API - Parallel
// -----------------------------------------------------

func (ctx EthKzgContext) BlobToKzgCommitmentParallel(blob EthBlob) (commitment EthKzgCommitment, err error) {
	if ctx.threadpool.ctx == nil {
		return commitment, errors.New("BlobToKzgCommitmentParallel: The threadpool is not configured.")
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
		if status == C.cttEthKzg_VerificationFailure {
			return false, nil
		}

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
		if status == C.cttEthKzg_VerificationFailure {
			return false, nil
		}

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


// Several byte array aliases used for BLS sigs and EVM prec.
type (
	Bytes32         [32]byte // serialized secret key
	Bytes48         [48]byte // compressed, serialized public key
	Bytes96         [96]byte // compressed, serialized signature
)

func (pub EthBlsPubKey) IsZero() bool {
	status := C.ctt_eth_bls_pubkey_is_zero((*C.ctt_eth_bls_pubkey)(&pub))
	return bool(status)
}

func DeserializeSecKey(src Bytes32) (sec EthBlsSecKey, err error) {
	status := C.ctt_eth_bls_deserialize_seckey((*C.ctt_eth_bls_seckey)(&sec),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecScalar_Success {
		err = errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return sec, err
	}
	return sec, nil
}

func DerivePubKey(sec EthBlsSecKey) (pub EthBlsPubKey) {
	C.ctt_eth_bls_derive_pubkey((*C.ctt_eth_bls_pubkey)(&pub), (*C.ctt_eth_bls_seckey)(&sec))
	return pub
}

func (pub *EthBlsPubKey) Verify(message []byte, sig EthBlsSignature) (bool, error) {
	status := C.ctt_eth_bls_verify((*C.ctt_eth_bls_pubkey)(pub),
		(*C.byte)(getAddr(message)),
		(C.size_t)(len(message)),
		(*C.ctt_eth_bls_signature)(&sig),
	)
	if status != C.cttEthBls_Success {
		if status == C.cttEthBls_VerificationFailure {
			return false, nil
		}

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

func (sec *EthBlsSecKey) Validate() (err error) {
	status := C.ctt_eth_bls_validate_seckey((*C.ctt_eth_bls_seckey)(sec))
	if status != C.cttCodecScalar_Success {
		err = errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return err
	}
	return nil
}

func (pub *EthBlsPubKey) Validate() (err error) {
	status := C.ctt_eth_bls_validate_pubkey((*C.ctt_eth_bls_pubkey)(pub))
	if status != C.cttCodecEcc_Success {
		err = errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return err
	}
	return nil
}

func (sig *EthBlsSignature) Validate() (err error) {
	status := C.ctt_eth_bls_validate_signature((*C.ctt_eth_bls_signature)(sig))
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return err
	}
	return nil
}

func (sec *EthBlsSecKey) Serialize() (dst Bytes32, err error) {
	status := C.ctt_eth_bls_serialize_seckey((*C.byte)(unsafe.Pointer(&dst)),
		(*C.ctt_eth_bls_seckey)(sec),
	)
	if status != C.cttCodecScalar_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return dst, err
	}
	return dst, nil
}

func (pub *EthBlsPubKey) SerializeCompressed() (dst Bytes48, err error) {
	status := C.ctt_eth_bls_serialize_pubkey_compressed((*C.byte)(unsafe.Pointer(&dst)),
		(*C.ctt_eth_bls_pubkey)(pub),
	)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return dst, err
	}
	return dst, nil
}

func (sig *EthBlsSignature) SerializeCompressed() (dst Bytes96, err error) {
	status := C.ctt_eth_bls_serialize_signature_compressed((*C.byte)(unsafe.Pointer(&dst)),
		(*C.ctt_eth_bls_signature)(sig),
	)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return dst, err
	}
	return dst, nil
}

func DeserializePubKeyCompressedUnchecked(src Bytes48) (pub EthBlsPubKey, err error) {
	status := C.ctt_eth_bls_deserialize_pubkey_compressed_unchecked((*C.ctt_eth_bls_pubkey)(&pub),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return pub, err
	}
	return pub, nil
}

func DeserializeSignatureCompressedUnchecked(src Bytes96) (sig EthBlsSignature, err error) {
	status := C.ctt_eth_bls_deserialize_signature_compressed_unchecked((*C.ctt_eth_bls_signature)(&sig),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return sig, err
	}
	return sig, nil
}

func DeserializePubKeyCompressed(src Bytes48) (pub EthBlsPubKey, err error) {
	status := C.ctt_eth_bls_deserialize_pubkey_compressed((*C.ctt_eth_bls_pubkey)(&pub),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return pub, err
	}
	return pub, nil
}

func DeserializeSignatureCompressed(src Bytes96) (sig EthBlsSignature, err error) {
	status := C.ctt_eth_bls_deserialize_signature_compressed((*C.ctt_eth_bls_signature)(&sig),
		(*C.byte)(&src[0]),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return sig, err
	}
	return sig, nil
}

func Sign(sec EthBlsSecKey, message []byte) (sig EthBlsSignature) {
	C.ctt_eth_bls_sign((*C.ctt_eth_bls_signature)(&sig), (*C.ctt_eth_bls_seckey)(&sec),
		(*C.byte)(getAddr(message)),
		(C.size_t)(len(message)),
	)
	return sig
}

func FastAggregateVerify(pubkeys []EthBlsPubKey, message []byte, aggregate_sig EthBlsSignature) (bool, error) {
	if len(pubkeys) == 0 {
		err := errors.New(
			"No public keys given.",
		)
		return false, err
	}
	status := C.ctt_eth_bls_fast_aggregate_verify((*C.ctt_eth_bls_pubkey)(getAddr(pubkeys)),
		(C.size_t)(len(pubkeys)),
		(*C.byte)(getAddr(message)),
		(C.size_t)(len(message)),
		(*C.ctt_eth_bls_signature)(&aggregate_sig),
	)
	if status != C.cttEthBls_Success {
		if status == C.cttEthBls_VerificationFailure {
			return false, nil
		}

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

func (accum ethBlsBatchSigAccumulator) init(secureRandomBytes Bytes32, accumSepTag []byte) {
	C.ctt_eth_bls_init_batch_sig_accumulator((*C.ctt_eth_bls_batch_sig_accumulator)(accum.ctx),
		(*C.byte)(&secureRandomBytes[0]),
		(*C.byte)(getAddr(accumSepTag)),
		(C.size_t)(len(accumSepTag)),
	)
}

func (accum ethBlsBatchSigAccumulator) update(pub EthBlsPubKey, message []byte, sig EthBlsSignature) bool {
	status := C.ctt_eth_bls_update_batch_sig_accumulator((*C.ctt_eth_bls_batch_sig_accumulator)(accum.ctx),
		(*C.ctt_eth_bls_pubkey)(&pub),
		(*C.byte)(getAddr(message)),
		(C.size_t)(len(message)),
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


func BatchVerifySoA(pubkeys []EthBlsPubKey, messages [][]byte, signatures []EthBlsSignature, secureRandomBytes Bytes32) (bool, error) {
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

func BatchVerifyAoS(triplets []BatchVerifyTriplet, secureRandomBytes Bytes32) (bool, error) {
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

type (
	Bytes64     [64]byte
	Bytes128    [128]byte
	Bytes256    [256]byte
)


func EvmSha256(inputs []byte) (result Bytes32, err error) {
	status := C.ctt_eth_evm_sha256((*C.byte)(&result[0]),
		32,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmModexp(inputs []byte) (result []byte, err error) {
	var size C.uint64_t
	// Call Nim function to determine correct size to allocate for `result`
	status := C.ctt_eth_evm_modexp_result_size(&size,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	result = make([]byte, int(size), int(size))
	status = C.ctt_eth_evm_modexp((*C.byte)(getAddr(result)),
		(C.size_t)(len(result)),
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBn254G1Add(inputs []byte) (result Bytes64, err error) {
	status := C.ctt_eth_evm_bn254_g1add((*C.byte)(&result[0]),
		64,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBn254G1Mul(inputs []byte) (result Bytes64, err error) {
	status := C.ctt_eth_evm_bn254_g1mul((*C.byte)(&result[0]),
		64,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err = errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBn254G1EcPairingCheck(inputs []byte) (result Bytes32, err error) {
	status := C.ctt_eth_evm_bn254_ecpairingcheck((*C.byte)(&result[0]),
		32,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381G1Add(inputs []byte) (result Bytes128, err error) {
	status := C.ctt_eth_evm_bls12381_g1add((*C.byte)(&result[0]),
		128,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381G1Mul(inputs []byte) (result Bytes128, err error) {
	status := C.ctt_eth_evm_bls12381_g1mul((*C.byte)(&result[0]),
		128,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381G1Msm(inputs []byte) (result Bytes128, err error) {
	status := C.ctt_eth_evm_bls12381_g1msm((*C.byte)(&result[0]),
		128,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381G2Add(inputs []byte) (result Bytes256, err error) {
	status := C.ctt_eth_evm_bls12381_g2add((*C.byte)(&result[0]),
		256,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381G2Mul(inputs []byte) (result Bytes256, err error) {
	status := C.ctt_eth_evm_bls12381_g2mul((*C.byte)(&result[0]),
		256,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381G2Msm(inputs []byte) (result Bytes256, err error) {
	status := C.ctt_eth_evm_bls12381_g2msm((*C.byte)(&result[0]),
		256,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381PairingCheck(inputs []byte) (result Bytes32, err error) {
	status := C.ctt_eth_evm_bls12381_pairingcheck((*C.byte)(&result[0]),
		32,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381MapFpToG1(inputs []byte) (result Bytes128, err error) {
	status := C.ctt_eth_evm_bls12381_map_fp_to_g1((*C.byte)(&result[0]),
		128,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}

func EvmBls12381MapFp2ToG2(inputs []byte) (result Bytes256, err error) {
	status := C.ctt_eth_evm_bls12381_map_fp2_to_g2((*C.byte)(&result[0]),
		256,
		(*C.byte)(getAddr(inputs)),
		(C.size_t)(len(inputs)),
	)
	if status != C.cttEVM_Success {
		err := errors.New(
			C.GoString(C.ctt_evm_status_to_string(status)),
		)
		return result, err
	}
	return result, nil
}
