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
#include <string.h> // for memcpy

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

func (ctx EthKzgContext) BlobToKZGCommitmentParallel(tp Threadpool, blob EthBlob) (commitment EthKzgCommitment, err error) {
	status := C.ctt_eth_kzg_blob_to_kzg_commitment_parallel(
		ctx.cCtx, tp.ctx,
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

func (ctx EthKzgContext) ComputeKzgProofParallel(tp Threadpool, blob EthBlob, z EthKzgChallenge) (proof EthKzgProof, y EthKzgEvalAtChallenge, err error) {
	status := C.ctt_eth_kzg_compute_kzg_proof_parallel(
		ctx.cCtx, tp.ctx,
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

func (ctx EthKzgContext) ComputeBlobKzgProofParallel(tp Threadpool, blob EthBlob, commitment EthKzgCommitment) (proof EthKzgProof, err error) {
	status := C.ctt_eth_kzg_compute_blob_kzg_proof_parallel(
		ctx.cCtx, tp.ctx,
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

func (ctx EthKzgContext) VerifyBlobKzgProofParallel(tp Threadpool, blob EthBlob, commitment EthKzgCommitment, proof EthKzgProof) (bool, error) {
	status := C.ctt_eth_kzg_verify_blob_kzg_proof_parallel(
		ctx.cCtx, tp.ctx,
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

func (ctx EthKzgContext) VerifyBlobKzgProofBatchParallel(tp Threadpool, blobs []EthBlob, commitments []EthKzgCommitment, proofs []EthKzgProof, secureRandomBytes [32]byte) (bool, error) {

	if len(blobs) != len(commitments) || len(blobs) != len(proofs) {
		return false, errors.New("VerifyBlobKzgProofBatch: Lengths of inputs do not match.")
	}

	status := C.ctt_eth_kzg_verify_blob_kzg_proof_batch_parallel(
		ctx.cCtx, tp.ctx,
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

// Constantine's SHA256 API

type Sha256Context struct {
	cCtx C.ctt_sha256_context
}

func Sha256ContextNew() (ctx Sha256Context, err error) {
	var cCtx C.ctt_sha256_context
	ctx = Sha256Context{cCtx: cCtx}
	return ctx, nil
}

func (ctx *Sha256Context) Sha256ContextInit() (bool, error) {
	C.ctt_sha256_init(&ctx.cCtx)
	return true, nil
}

func (ctx *Sha256Context) Sha256ContextUpdate(data []byte) (bool, error) {
	C.ctt_sha256_update(&ctx.cCtx,
		(*C.byte)(unsafe.Pointer(&data[0])),
		(C.ptrdiff_t)(len(data)),
	)
	return true, nil
}

func (ctx *Sha256Context) Sha256ContextFinish(data [32]byte) (bool, error) {
	C.ctt_sha256_finish(&ctx.cCtx,
		(*C.byte)(unsafe.Pointer(&data[0])),
	)
	return true, nil
}

func (ctx *Sha256Context) Sha256ContextClear() (bool, error) {
	C.ctt_sha256_clear(&ctx.cCtx)
	return true, nil
}

func Sha256Hash(digest *[32]byte, message []byte, clearMemory bool) (bool, error) {
	C.ctt_sha256_hash((*C.byte)(unsafe.Pointer(digest)),
		(*C.byte)(unsafe.Pointer(&message[0])),
		(C.ptrdiff_t)(len(message)),
		(C.ctt_bool)(clearMemory),
	)
	return true, nil
}

// Ethereum BLS signatures
// -----------------------------------------------------

type EthBlsSecKey struct {
	cSec C.ctt_eth_bls_seckey
}

type EthBlsPubKey struct {
	cPub C.ctt_eth_bls_pubkey
}

type EthBlsSignature struct {
	cSig C.ctt_eth_bls_signature
}

func (pub EthBlsPubKey) PubKeyIsZero() (bool, error) {
	status := C.ctt_eth_bls_pubkey_is_zero(&pub.cPub)
	return bool(status), nil
}

func (sec *EthBlsSecKey) DeserializeSecKey(src [32]byte) (bool, error) {
	status := C.ctt_eth_bls_deserialize_seckey(&sec.cSec,
		(*C.byte)(unsafe.Pointer(&src[0])))
	if status != C.cttCodecScalar_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) DerivePubKey(sec EthBlsSecKey) (bool, error) {
	C.ctt_eth_bls_derive_pubkey(&pub.cPub, &sec.cSec)
	return true, nil
}

func (pub *EthBlsPubKey) Verify(message []byte, sig EthBlsSignature) (bool, error) {
	status := C.ctt_eth_bls_verify(&pub.cPub,
		(*C.byte)(unsafe.Pointer(&message[0])),
		(C.ptrdiff_t)(len(message)),
		&sig.cSig,
	)
	if status != C.cttEthBls_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_bls_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig EthBlsSignature) SignatureIsZero() (bool, error) {
	status := C.ctt_eth_bls_signature_is_zero(&sig.cSig)
	return bool(status), nil
}

func (pub1 EthBlsPubKey) PubKeysAreEqual(pub2 EthBlsPubKey) (bool, error) {
	status := C.ctt_eth_bls_pubkeys_are_equal(&pub1.cPub, &pub2.cPub)
	return bool(status), nil
}

func (sig1 EthBlsSignature) SignaturesAreEqual(sig2 EthBlsSignature) (bool, error) {
	status := C.ctt_eth_bls_signatures_are_equal(&sig1.cSig, &sig2.cSig)
	return bool(status), nil
}

func (sec *EthBlsSecKey) Validate() (bool, error) {
	status := C.ctt_eth_bls_validate_seckey(&sec.cSec)
	if status != C.cttCodecScalar_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_scalar_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (pub *EthBlsPubKey) Validate() (bool, error) {
	status := C.ctt_eth_bls_validate_pubkey(&pub.cPub)
	if status != C.cttCodecEcc_Success {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) Validate() (bool, error) {
	status := C.ctt_eth_bls_validate_signature(&sig.cSig)
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
		&sec.cSec,
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
		&pub.cPub,
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
		&sig.cSig,
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
	status := C.ctt_eth_bls_deserialize_pubkey_compressed_unchecked(&pub.cPub,
		(*C.byte)(unsafe.Pointer(&src[0])),
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
	status := C.ctt_eth_bls_deserialize_signature_compressed_unchecked(&sig.cSig,
		(*C.byte)(unsafe.Pointer(&src[0])),
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
	status := C.ctt_eth_bls_deserialize_pubkey_compressed(&pub.cPub,
		(*C.byte)(unsafe.Pointer(&src[0])),
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
	status := C.ctt_eth_bls_deserialize_signature_compressed(&sig.cSig,
		(*C.byte)(unsafe.Pointer(&src[0])),
	)
	if status != C.cttCodecEcc_Success && status != C.cttCodecEcc_PointAtInfinity {
		err := errors.New(
			C.GoString(C.ctt_codec_ecc_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func (sig *EthBlsSignature) Sign(sec EthBlsSecKey, message []byte) (bool, error) {
	C.ctt_eth_bls_sign(&sig.cSig, &sec.cSec,
		(*C.byte)(unsafe.Pointer(&message[0])),
		(C.ptrdiff_t)(len(message)),
	)
	return true, nil
}

func FastAggregateVerify(pubkeys []EthBlsPubKey, message []byte, aggregate_sig EthBlsSignature) (bool, error) {
	// TODO: If we had `EthBlsPubKey` just be
	// type EthBlsPubKey C.ctt_eth_bls_pubkey
	// we could just pass it directly, no? But I guess that leaks out
	// the C types into users' modules?
	if len(pubkeys) == 0 {
		err := errors.New(
			"No public keys given.",
		)
		return false, err
	}
	var cpkeys []C.ctt_eth_bls_pubkey
	cpkeys = make([]C.ctt_eth_bls_pubkey, len(pubkeys), len(pubkeys))
	for i, pk := range pubkeys {
		cpkeys[i] = pk.cPub
	}
	status := C.ctt_eth_bls_fast_aggregate_verify((*C.ctt_eth_bls_pubkey)(unsafe.Pointer(&cpkeys[0])),
		(C.ptrdiff_t)(len(pubkeys)),
		(*C.byte)(unsafe.Pointer(&message[0])),
		(C.ptrdiff_t)(len(message)),
		&aggregate_sig.cSig,
	)
	if status != C.cttEthBls_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_bls_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

// Go wrapper of the `ctt_span` type of the C API
type CttSpan struct {
	data *C.byte
	len  C.size_t
}

// NOTE: this does not work, because it would end up with us having a
// Go pointer we pass to C, which points to Go pointers.
func toSpan(data *[]byte) (span C.ctt_span) { //CttSpan) {
	span = C.ctt_span{data: (*C.byte)(unsafe.Pointer(&(*data)[0])), len: C.size_t(len(*data))} // in place span
	return span
}

func newSpans(data [][]byte) (spans []CttSpan) {
	// TODO: this is ugly, but due to Go's rules about not allowing to
	// pass a Go pointer, which itself contains a Go pointer, we cannot
	// pass the data of each `message` to C... So gotta malloc and copy
	spans = make([]CttSpan, len(data), len(data))
	for i, msg := range data {
		mem := C.malloc(C.ulong(len(msg)))
		C.memcpy(mem, unsafe.Pointer(&msg[0]), C.ulong(len(msg)))
		spans[i] = CttSpan{data: (*C.byte)(mem), len: C.size_t(len(msg))}
	}
	return spans
}

func freeSpans(spans []CttSpan){
	// frees the malloc'd memory of the given spans
	for _, msg := range spans {
		C.free(unsafe.Pointer(msg.data))
	}
}

func AggregateVerify(pubkeys []EthBlsPubKey, messages [][]byte, aggregate_sig EthBlsSignature) (bool, error) {
	// TODO: If we had `EthBlsPubKey` just be
	// type EthBlsPubKey C.ctt_eth_bls_pubkey
	// we could just pass it directly, no? But I guess that leaks out
	// the C types into users' modules?
	if len(pubkeys) == 0 {
		err := errors.New(
			"No public keys given.",
		)
		return false, err
	}

	var cpkeys []C.ctt_eth_bls_pubkey
	cpkeys = make([]C.ctt_eth_bls_pubkey, len(pubkeys), len(pubkeys))
	for i, pk := range pubkeys {
		cpkeys[i] = pk.cPub
	}

	// copy messages to CttSpan type array
	spans := newSpans(messages)
	defer freeSpans(spans) // make sure to free after!
	status := C.ctt_eth_bls_aggregate_verify((*C.ctt_eth_bls_pubkey)(unsafe.Pointer(&cpkeys[0])),
		(*C.ctt_span)(unsafe.Pointer(&spans[0])),
		(C.ptrdiff_t)(len(pubkeys)),
		&aggregate_sig.cSig,
	)
	if status != C.cttEthBls_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_bls_status_to_string(status)),
		)
		return false, err
	}
	return true, nil
}

func BatchVerify(pubkeys []EthBlsPubKey, messages [][]byte, signatures []EthBlsSignature, secureRandomBytes [32]byte) (bool, error) {
	// TODO: If we had `EthBlsPubKey` just be
	// type EthBlsPubKey C.ctt_eth_bls_pubkey
	// we could just pass it directly, no? But I guess that leaks out
	// the C types into users' modules?
	if len(pubkeys) != len(messages) {
		err := errors.New("Number of public keys must match number of messages.")
		return false, err
	} else if len(pubkeys) != len(signatures) {
		err := errors.New("Number of public keys must match number of signatures.")
		return false, err
	}

	var cpkeys []C.ctt_eth_bls_pubkey
	var csigs []C.ctt_eth_bls_signature
	cpkeys = make([]C.ctt_eth_bls_pubkey, len(pubkeys), len(pubkeys))
	csigs = make([]C.ctt_eth_bls_signature, len(pubkeys), len(pubkeys))
	for i, pk := range pubkeys {
		cpkeys[i] = pk.cPub
		csigs[i] = signatures[i].cSig
	}

	// copy messages to CttSpan type array
	spans := newSpans(messages)
	defer freeSpans(spans) // make sure to free after!

	status := C.ctt_eth_bls_batch_verify((*C.ctt_eth_bls_pubkey)(unsafe.Pointer(&cpkeys[0])),
		(*C.ctt_span)(unsafe.Pointer(&spans[0])),
		(*C.ctt_eth_bls_signature)(unsafe.Pointer(&csigs[0])),
		(C.ptrdiff_t)(len(pubkeys)),
		(*C.byte)(unsafe.Pointer(&secureRandomBytes[0])),
	)
	if status != C.cttEthBls_Success {
		err := errors.New(
			C.GoString(C.ctt_eth_bls_status_to_string(status)),
		)
		return false, err
	}

	return true, nil
}

// TODO: BatchVerifyParallel
