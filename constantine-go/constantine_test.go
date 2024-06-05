/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

package constantine

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"fmt"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
	"encoding/json"

	"github.com/mratsim/constantine/constantine-go/sha256"
)


// Threadpool smoke test
// ----------------------------------------------------------

func TestThreadpool(t *testing.T) {
	tp := ThreadpoolNew(runtime.NumCPU())
	tp.Shutdown()
}

// Ethereum EIP-4844 KZG tests
// ----------------------------------------------------------
//
// Source: https://github.com/ethereum/c-kzg-4844

var (
	trustedSetupFile             = "../constantine/trusted_setups/trusted_setup_ethereum_kzg4844_reference.dat"
	testDir                      = "../tests/protocol_ethereum_eip4844_deneb_kzg"
	blobToKZGCommitmentTests     = filepath.Join(testDir, "blob_to_kzg_commitment/*/*/*")
	computeKZGProofTests         = filepath.Join(testDir, "compute_kzg_proof/*/*/*")
	computeBlobKZGProofTests     = filepath.Join(testDir, "compute_blob_kzg_proof/*/*/*")
	verifyKZGProofTests          = filepath.Join(testDir, "verify_kzg_proof/*/*/*")
	verifyBlobKZGProofTests      = filepath.Join(testDir, "verify_blob_kzg_proof/*/*/*")
	verifyBlobKZGProofBatchTests = filepath.Join(testDir, "verify_blob_kzg_proof_batch/*/*/*")
)

func fromHexImpl(dst []byte, input []byte) error {
	s := string(input)
	if strings.HasPrefix(s, "0x") {
		s = s[2:]
	}
	bytes, err := hex.DecodeString(s)
	if err != nil {
		return err
	}
	if len(bytes) != len(dst) {
		return errors.New(
			"Length of input doesn't match expected length.",
		)
	}
	copy(dst, bytes)
	return nil
}

func (dst *EthKzgCommitment) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}
func (dst *EthKzgProof) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}
func (dst *EthBlob) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}
func (dst *EthKzgChallenge) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}
func (dst *EthKzgEvalAtChallenge) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}

func TestBlobToKZGCommitment(t *testing.T) {
	type Test struct {
		Input struct {
			Blob string `yaml:"blob"`
		}
		Output *EthKzgCommitment `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(blobToKZGCommitmentTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			require.NoError(t, err)
			test := Test{}
			err = yaml.NewDecoder(testFile).Decode(&test)
			require.NoError(t, testFile.Close())
			require.NoError(t, err)

			var blob EthBlob
			err = blob.UnmarshalText([]byte(test.Input.Blob))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			commitment, err := ctx.BlobToKZGCommitment(blob)
			if err == nil {
				require.NotNil(t, test.Output)
				require.Equal(t, test.Output[:], commitment[:])
			} else {
				require.Nil(t, test.Output)
			}
		})
	}
}

func TestComputeKzgProof(t *testing.T) {
	type Test struct {
		Input struct {
			Blob string `yaml:"blob"`
			Z    string `yaml:"z"`
		}
		Output *[]string `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(computeKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			require.NoError(t, err)
			test := Test{}
			err = yaml.NewDecoder(testFile).Decode(&test)
			require.NoError(t, testFile.Close())
			require.NoError(t, err)

			var blob EthBlob
			err = blob.UnmarshalText([]byte(test.Input.Blob))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var z EthKzgChallenge
			err = z.UnmarshalText([]byte(test.Input.Z))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			proof, y, err := ctx.ComputeKzgProof(blob, z)
			if err == nil {
				require.NotNil(t, test.Output)
				var expectedProof EthKzgProof
				err = expectedProof.UnmarshalText([]byte((*test.Output)[0]))
				require.NoError(t, err)
				require.Equal(t, expectedProof[:], proof[:])
				var expectedY EthKzgEvalAtChallenge
				err = expectedY.UnmarshalText([]byte((*test.Output)[1]))
				require.NoError(t, err)
				require.Equal(t, expectedY[:], y[:])
			} else {
				require.Nil(t, test.Output)
			}
		})
	}
}

func TestVerifyKzgProof(t *testing.T) {
	type Test struct {
		Input struct {
			Commitment string `yaml:"commitment"`
			Z          string `yaml:"z"`
			Y          string `yaml:"y"`
			Proof      string `yaml:"proof"`
		}
		Output *bool `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(verifyKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			require.NoError(t, err)
			test := Test{}
			err = yaml.NewDecoder(testFile).Decode(&test)
			require.NoError(t, testFile.Close())
			require.NoError(t, err)

			var commitment EthKzgCommitment
			err = commitment.UnmarshalText([]byte(test.Input.Commitment))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var z EthKzgChallenge
			err = z.UnmarshalText([]byte(test.Input.Z))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var y EthKzgEvalAtChallenge
			err = y.UnmarshalText([]byte(test.Input.Y))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var proof EthKzgProof
			err = proof.UnmarshalText([]byte(test.Input.Proof))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			valid, err := ctx.VerifyKzgProof(commitment, z, y, proof)
			if err == nil {
				require.NotNil(t, test.Output)
				require.Equal(t, *test.Output, valid)
			} else {
				if test.Output != nil {
					require.Equal(t, *test.Output, valid)
				}
			}
		})
	}
}

func TestComputeBlobKzgProof(t *testing.T) {
	type Test struct {
		Input struct {
			Blob       string `yaml:"blob"`
			Commitment string `yaml:"commitment"`
		}
		Output *EthKzgProof `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(computeBlobKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			require.NoError(t, err)
			test := Test{}
			err = yaml.NewDecoder(testFile).Decode(&test)
			require.NoError(t, testFile.Close())
			require.NoError(t, err)

			var blob EthBlob
			err = blob.UnmarshalText([]byte(test.Input.Blob))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var commitment EthKzgCommitment
			err = commitment.UnmarshalText([]byte(test.Input.Commitment))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			proof, err := ctx.ComputeBlobKzgProof(blob, commitment)
			if err == nil {
				require.NotNil(t, test.Output)
				require.Equal(t, test.Output[:], proof[:])
			} else {
				require.Nil(t, test.Output)
			}
		})
	}
}

func TestVerifyBlobKzgProof(t *testing.T) {
	type Test struct {
		Input struct {
			Blob       string `yaml:"blob"`
			Commitment string `yaml:"commitment"`
			Proof      string `yaml:"proof"`
		}
		Output *bool `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(verifyBlobKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			require.NoError(t, err)
			test := Test{}
			err = yaml.NewDecoder(testFile).Decode(&test)
			require.NoError(t, testFile.Close())
			require.NoError(t, err)

			var blob EthBlob
			err = blob.UnmarshalText([]byte(test.Input.Blob))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var commitment EthKzgCommitment
			err = commitment.UnmarshalText([]byte(test.Input.Commitment))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var proof EthKzgProof
			err = proof.UnmarshalText([]byte(test.Input.Proof))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			valid, err := ctx.VerifyBlobKzgProof(blob, commitment, proof)
			if err == nil {
				require.NotNil(t, test.Output)
				require.Equal(t, *test.Output, valid)
			} else {
				if test.Output != nil {
					require.Equal(t, *test.Output, valid)
				}
			}
		})
	}
}

func TestVerifyBlobKzgProofBatch(t *testing.T) {
	type Test struct {
		Input struct {
			Blobs       []string `yaml:"blobs"`
			Commitments []string `yaml:"commitments"`
			Proofs      []string `yaml:"proofs"`
		}
		Output *bool `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	var secureRandomBytes [32]byte
	_, _ = rand.Read(secureRandomBytes[:])

	tests, err := filepath.Glob(verifyBlobKZGProofBatchTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			require.NoError(t, err)
			test := Test{}
			err = yaml.NewDecoder(testFile).Decode(&test)
			require.NoError(t, testFile.Close())
			require.NoError(t, err)

			var blobs []EthBlob
			for _, b := range test.Input.Blobs {
				var blob EthBlob
				err = blob.UnmarshalText([]byte(b))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				blobs = append(blobs, blob)
			}

			var commitments []EthKzgCommitment
			for _, c := range test.Input.Commitments {
				var commitment EthKzgCommitment
				err = commitment.UnmarshalText([]byte(c))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				commitments = append(commitments, commitment)
			}

			var proofs []EthKzgProof
			for _, p := range test.Input.Proofs {
				var proof EthKzgProof
				err = proof.UnmarshalText([]byte(p))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				proofs = append(proofs, proof)
			}

			valid, err := ctx.VerifyBlobKzgProofBatch(blobs, commitments, proofs, secureRandomBytes)
			if err == nil {
				require.NotNil(t, test.Output)
				require.Equal(t, *test.Output, valid)
			} else {
				if test.Output != nil {
					require.Equal(t, *test.Output, valid)
				}
			}
		})
	}
}

// Ethereum EIP-4844 KZG tests - Parallel
// ----------------------------------------------------------

func createTestThreadpool(t *testing.T) Threadpool {
	// Ensure all C function are called from the same OS thread
	// to avoid messing up the threadpool Thread-Local-Storage.
	// Be sure to not use t.Run are subtests are run on separate goroutine as well
	runtime.LockOSThread()
	tp := ThreadpoolNew(runtime.NumCPU())

	// Register a cleanup function
	t.Cleanup(func() {
        tp.Shutdown()
		runtime.UnlockOSThread()
    })

	return tp
}

func TestBlobToKZGCommitmentParallel(t *testing.T) {
	type Test struct {
		Input struct {
			Blob string `yaml:"blob"`
		}
		Output *EthKzgCommitment `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tp := createTestThreadpool(t)

	tests, err := filepath.Glob(blobToKZGCommitmentTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		// Don't use t.Run() with parallel C code to not mess up thread-local storage
		testFile, err := os.Open(testPath)
		require.NoError(t, err)
		test := Test{}
		err = yaml.NewDecoder(testFile).Decode(&test)
		require.NoError(t, testFile.Close())
		require.NoError(t, err)

		var blob EthBlob
		err = blob.UnmarshalText([]byte(test.Input.Blob))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		commitment, err := ctx.BlobToKZGCommitmentParallel(tp, blob)
		if err == nil {
			require.NotNil(t, test.Output)
			require.Equal(t, test.Output[:], commitment[:])
		} else {
			require.Nil(t, test.Output)
		}
	}
}

func TestComputeKzgProofParallel(t *testing.T) {
	type Test struct {
		Input struct {
			Blob string `yaml:"blob"`
			Z    string `yaml:"z"`
		}
		Output *[]string `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tp := createTestThreadpool(t)

	tests, err := filepath.Glob(computeKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		// Don't use t.Run() with parallel C code to not mess up thread-local storage
		testFile, err := os.Open(testPath)
		require.NoError(t, err)
		test := Test{}
		err = yaml.NewDecoder(testFile).Decode(&test)
		require.NoError(t, testFile.Close())
		require.NoError(t, err)

		var blob EthBlob
		err = blob.UnmarshalText([]byte(test.Input.Blob))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		var z EthKzgChallenge
		err = z.UnmarshalText([]byte(test.Input.Z))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		proof, y, err := ctx.ComputeKzgProofParallel(tp, blob, z)
		if err == nil {
			require.NotNil(t, test.Output)
			var expectedProof EthKzgProof
			err = expectedProof.UnmarshalText([]byte((*test.Output)[0]))
			require.NoError(t, err)
			require.Equal(t, expectedProof[:], proof[:])
			var expectedY EthKzgEvalAtChallenge
			err = expectedY.UnmarshalText([]byte((*test.Output)[1]))
			require.NoError(t, err)
			require.Equal(t, expectedY[:], y[:])
		} else {
			require.Nil(t, test.Output)
		}
	}
}

func TestComputeBlobKzgProofParallel(t *testing.T) {
	type Test struct {
		Input struct {
			Blob       string `yaml:"blob"`
			Commitment string `yaml:"commitment"`
		}
		Output *EthKzgProof `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tp := createTestThreadpool(t)

	tests, err := filepath.Glob(computeBlobKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		// Don't use t.Run() with parallel C code to not mess up thread-local storage
		testFile, err := os.Open(testPath)
		require.NoError(t, err)
		test := Test{}
		err = yaml.NewDecoder(testFile).Decode(&test)
		require.NoError(t, testFile.Close())
		require.NoError(t, err)

		var blob EthBlob
		err = blob.UnmarshalText([]byte(test.Input.Blob))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		var commitment EthKzgCommitment
		err = commitment.UnmarshalText([]byte(test.Input.Commitment))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		proof, err := ctx.ComputeBlobKzgProofParallel(tp, blob, commitment)
		if err == nil {
			require.NotNil(t, test.Output)
			require.Equal(t, test.Output[:], proof[:])
		} else {
			require.Nil(t, test.Output)
		}
	}
}

func TestVerifyBlobKzgProofParallel(t *testing.T) {
	type Test struct {
		Input struct {
			Blob       string `yaml:"blob"`
			Commitment string `yaml:"commitment"`
			Proof      string `yaml:"proof"`
		}
		Output *bool `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tp := createTestThreadpool(t)

	tests, err := filepath.Glob(verifyBlobKZGProofTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		// Don't use t.Run() with parallel C code to not mess up thread-local storage
		testFile, err := os.Open(testPath)
		require.NoError(t, err)
		test := Test{}
		err = yaml.NewDecoder(testFile).Decode(&test)
		require.NoError(t, testFile.Close())
		require.NoError(t, err)

		var blob EthBlob
		err = blob.UnmarshalText([]byte(test.Input.Blob))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		var commitment EthKzgCommitment
		err = commitment.UnmarshalText([]byte(test.Input.Commitment))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		var proof EthKzgProof
		err = proof.UnmarshalText([]byte(test.Input.Proof))
		if err != nil {
			require.Nil(t, test.Output)
			continue
		}

		valid, err := ctx.VerifyBlobKzgProofParallel(tp, blob, commitment, proof)
		if err == nil {
			require.NotNil(t, test.Output)
			require.Equal(t, *test.Output, valid)
		} else {
			if test.Output != nil {
				require.Equal(t, *test.Output, valid)
			}
		}
	}
}

func TestVerifyBlobKzgProofBatchParallel(t *testing.T) {
	type Test struct {
		Input struct {
			Blobs       []string `yaml:"blobs"`
			Commitments []string `yaml:"commitments"`
			Proofs      []string `yaml:"proofs"`
		}
		Output *bool `yaml:"output"`
	}

	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tp := createTestThreadpool(t)

	var secureRandomBytes [32]byte
	_, _ = rand.Read(secureRandomBytes[:])

	tests, err := filepath.Glob(verifyBlobKZGProofBatchTests)
	require.NoError(t, err)
	require.True(t, len(tests) > 0)

	for _, testPath := range tests {
		// Don't use t.Run() with parallel C code to not mess up thread-local storage
		testFile, err := os.Open(testPath)
		require.NoError(t, err)
		test := Test{}
		err = yaml.NewDecoder(testFile).Decode(&test)
		require.NoError(t, testFile.Close())
		require.NoError(t, err)

		var blobs []EthBlob
		for _, b := range test.Input.Blobs {
			var blob EthBlob
			err = blob.UnmarshalText([]byte(b))
			if err != nil {
				require.Nil(t, test.Output)
				continue
			}
			blobs = append(blobs, blob)
		}

		var commitments []EthKzgCommitment
		for _, c := range test.Input.Commitments {
			var commitment EthKzgCommitment
			err = commitment.UnmarshalText([]byte(c))
			if err != nil {
				require.Nil(t, test.Output)
				continue
			}
			commitments = append(commitments, commitment)
		}

		var proofs []EthKzgProof
		for _, p := range test.Input.Proofs {
			var proof EthKzgProof
			err = proof.UnmarshalText([]byte(p))
			if err != nil {
				require.Nil(t, test.Output)
				continue
			}
			proofs = append(proofs, proof)
		}

		valid, err := ctx.VerifyBlobKzgProofBatchParallel(tp, blobs, commitments, proofs, secureRandomBytes)
		if err == nil {
			require.NotNil(t, test.Output)
			require.Equal(t, *test.Output, valid)
		} else {
			if test.Output != nil {
				require.Equal(t, *test.Output, valid)
			}
		}
	}
}

// To be removed. This is the C example ported
func TestExampleCBlsSig(t *testing.T) {
	var secKey EthBlsSecKey
	str := "Security pb becomes key mgmt pb!"
	var rawSecKey [32]byte
	copy(rawSecKey[:], str)
	status, err := secKey.Deserialize(rawSecKey)
	fmt.Println("deserialized: Status: ", status, " err = ", err)

	// Derive the matching public key
	var pubKey EthBlsPubKey
	pubKey.DerivePubKey(secKey)

	// Sign a message
	var message [32]byte
	sha256.Hash(&message, []byte("Mr F was here"), false)

	fmt.Println("message: ", message)
	var sig EthBlsSignature
	sig.Sign(secKey, message[:])
	fmt.Println("signed: status", status, " err = ", err)

	// Verify that a signature is valid for a message under the provided public key
	status, err = pubKey.Verify(message[:], sig)
	fmt.Println("verified: status", status, " err = ", err)

	// try to use batch verify; We just reuse the data from above 3 times
	pkeys := []EthBlsPubKey{pubKey, pubKey, pubKey}
	msgs := [][]byte{message[:], message[:], message[:]}
	sigs := []EthBlsSignature{sig, sig, sig}
	var srb [32]byte // leave zero
	status, err = BatchVerify(pkeys, msgs, sigs, srb)
	fmt.Println("batchverified: Status ", status, " err = ", err)
}

var (
	testDirBls                  = "../tests/protocol_blssig_pop_on_bls12381_g2_test_vectors_v0.1.1"
	aggregate_verifyTests		= filepath.Join(testDirBls, "aggregate_verify/*")
	aggregateTests				= filepath.Join(testDirBls, "aggregate/*")
	deserialization_G1Tests		= filepath.Join(testDirBls, "deserialization_G1/*")
	batch_verifyTests			= filepath.Join(testDirBls, "batch_verify/*")
	fast_aggregate_verifyTests	= filepath.Join(testDirBls, "fast_aggregate_verify/*")
	hash_to_G2Tests				= filepath.Join(testDirBls, "hash_to_G2/*")
	deserialization_G2Tests		= filepath.Join(testDirBls, "deserialization_G2/*")
	verifyTests					= filepath.Join(testDirBls, "verify/*")
	signTests					= filepath.Join(testDirBls, "sign/*")
)

// These types correspond to the serialized pub/sec keys / signatures
// (and test messages / test outputs)
type (
	EthBlsPubKeyRaw    [48]byte
	EthBlsSignatureRaw [96]byte
	EthBlsSecKeyRaw    [32]byte
	EthBlsMessage      [32]byte
	EthBlsTestOutput   [96]byte
)

// Helpers to convert the strings from the JSON files to bytes
func (dst *EthBlsPubKeyRaw) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}

func (dst *EthBlsSignatureRaw) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}

func (dst *EthBlsSecKeyRaw) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}

func (dst *EthBlsMessage) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}

func (dst *EthBlsTestOutput) UnmarshalText(input []byte) error {
	return fromHexImpl(dst[:], input)
}


func TestDeserializeG1(t *testing.T) {
	type Test struct {
		Input struct {
			PubKey string `json:"pubkey"`

		} `json:"input"`
		Output bool `json:"output"`
	}

	tests, _ := filepath.Glob(deserialization_G1Tests)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			test := Test{}
			err = json.NewDecoder(testFile).Decode(&test)

			var rawPk EthBlsPubKeyRaw
			err = rawPk.UnmarshalText([]byte(test.Input.PubKey))
			if strings.HasSuffix(testPath, "deserialization_fails_too_few_bytes.json") ||
				strings.HasSuffix(testPath, "deserialization_fails_too_many_bytes.json") {
				require.False(t, test.Output)
			} else if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var pk EthBlsPubKey
			var status bool
			status, err = pk.DeserializeCompressed(rawPk)

			if status {
				var s [48]byte
				status, err = pk.SerializeCompressed(&s)
				if err != nil {
					require.Nil(t, test.Output)
				}
				require.True(t, status)
				require.Equal(t, s[:], rawPk[:])
				// The status now must be the same as the expected output
				require.Equal(t, status, test.Output)
			} else {
				// sanity check the output matches status
				require.Equal(t, status, test.Output)
			}
		})
	}
}

func TestDeserializeG2(t *testing.T) {
	type Test struct {
		Input struct {
			Signature string `json:"signature"`

		} `json:"input"`
		Output bool `json:"output"`
	}

	tests, _ := filepath.Glob(deserialization_G2Tests)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			test := Test{}
			err = json.NewDecoder(testFile).Decode(&test)

			var rawSig EthBlsSignatureRaw
			err = rawSig.UnmarshalText([]byte(test.Input.Signature))
			if strings.HasSuffix(testPath, "deserialization_fails_too_few_bytes.json") ||
				strings.HasSuffix(testPath, "deserialization_fails_too_many_bytes.json") {
				require.NotNil(t, test.Output)
			} else if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var sig EthBlsSignature
			var status bool
			status, err = sig.DeserializeCompressed(rawSig)

			if status {
				var s [96]byte
				status, err = sig.SerializeCompressed(&s)
				if err != nil {
					require.Nil(t, test.Output)
				}
				require.True(t, status)
				require.Equal(t, s[:], rawSig[:])
				// The status now must be the same as the expected output
				require.Equal(t, status, test.Output)
			} else {
				// sanity check the output matches status
				require.Equal(t, status, test.Output)
			}
		})
	}
}

func TestSign(t *testing.T) {
	type Test struct {
		Input struct {
			PrivKey string `json:"privkey"`
			Message string `json:"message"`

		} `json:"input"`
		Output string `json:"output"`
	}

	tests, _ := filepath.Glob(signTests)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			test := Test{}
			err = json.NewDecoder(testFile).Decode(&test)

			var rawSecKey EthBlsSecKeyRaw
			err = rawSecKey.UnmarshalText([]byte(test.Input.PrivKey))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}
			var msg EthBlsMessage
			err = msg.UnmarshalText([]byte(test.Input.Message))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}
			var tOut EthBlsTestOutput
			err = tOut.UnmarshalText([]byte(test.Output))

			if strings.HasSuffix(testPath, "sign_case_zero_privkey.json") {
				require.Equal(t, test.Output, "")
			} else if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var secKey EthBlsSecKey
			var status bool
			status, err = secKey.Deserialize(rawSecKey)
			var sig EthBlsSignature
			if !status {
				// sanity check the output matches status
				require.Equal(t, test.Output, "") // one file: has `null` JSON value
				//require.Equal(t, status, test.Output)
				sig.Sign(secKey, msg[:])
			} else {
				// sign the message
				sig.Sign(secKey, msg[:])
				{ // deserialiaze output for extra codec testing
					var output EthBlsSignature
					status, err = output.DeserializeCompressed(tOut)
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					status = sig.AreEqual(output)
					if !status { // signatures mismatch
						var sigBytes  [96]byte
						var roundTrip [96]byte
						sb_status, _ := sig.SerializeCompressed(&sigBytes)
						rt_status, _ := output.SerializeCompressed(&roundTrip)
						fmt.Println("\nResult signature differs from expected \n",
							"   computed:  0x", sigBytes, " (", sb_status, ")\n",
							"   roundtrip: 0x", roundTrip, " (", rt_status, ")\n",
							"   expected:  0x", test.Output,
						)
						require.True(t, false) // fail the test case
						return
					}

				}
				{ // serialize result for extra codec testing
					var sigBytes [96]byte
					status, err = sig.SerializeCompressed(&sigBytes)
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					require.Equal(t, sigBytes[:], tOut[:])
					// TODO: else
					// fmt.Println("\nResult signature differs from expected \n",
					// "   computed: 0x", sig_bytes, " (", status2, ")\n",
					// "   expected: 0x", test.Output,
					// )
					return
				}
			}
		})
	}
}

func TestVerify(t *testing.T) {
	type Test struct {
		Input struct {
			PubKey string `json:"pubkey"`
			Message string `json:"message"`
			Signature string `json:"signature"`

		} `json:"input"`
		Output bool `json:"output"`
	}

	tests, _ := filepath.Glob(verifyTests)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			test := Test{}
			err = json.NewDecoder(testFile).Decode(&test)


			var rawPk EthBlsPubKeyRaw
			err = rawPk.UnmarshalText([]byte(test.Input.PubKey))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}
			var rawSig EthBlsSignatureRaw
			err = rawSig.UnmarshalText([]byte(test.Input.Signature))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var status bool
			var sig EthBlsSignature
			var pk EthBlsPubKey
			{ // testChecks
				status, err = pk.DeserializeCompressed(rawPk)
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				status, err = sig.DeserializeCompressed(rawSig)
				if err != nil { // expected this verification fails?
					require.Equal(t, status, test.Output)
					return
				}
				var msg EthBlsMessage
				err = msg.UnmarshalText([]byte(test.Input.Message))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				status, err = pk.Verify(msg[:], sig)

				if err != nil { // expected this verification fails?
					require.Equal(t, status, test.Output)
					return
				}
			}
			if status != test.Output {
				fmt.Println("Verification differs from expected \n",
				    "   valid sig? ", status, "\n",
				    "   expected: ", test.Output,
				)
				require.True(t, false)
				return
			} else if status {
				{
					var output [48]byte
					status, err = pk.SerializeCompressed(&output)
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					require.Equal(t, output[:], rawPk[:])
					return
				}
				{
					var output [96]byte
					status, err = sig.SerializeCompressed(&output)
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					require.Equal(t, output[:], rawSig[:])
					return
				}
			}
		})
	}
}

func TestFastAggregateVerify(t *testing.T) {
	type Test struct {
		Input struct {
			PubKeys []string `json:"pubkeys"`
			Message string `json:"message"`
			Signature string `json:"signature"`

		} `json:"input"`
		Output bool `json:"output"`
	}

	tests, _ := filepath.Glob(fast_aggregate_verifyTests)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			test := Test{}
			err = json.NewDecoder(testFile).Decode(&test)

			var rawPks []EthBlsPubKeyRaw
			for _, s := range test.Input.PubKeys {
				var rawPk EthBlsPubKeyRaw
				err = rawPk.UnmarshalText([]byte(s))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				rawPks = append(rawPks, rawPk)
			}
			var rawSig EthBlsSignatureRaw
			err = rawSig.UnmarshalText([]byte(test.Input.Signature))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}

			var pks []EthBlsPubKey
			var status bool
			{ // testChecks
				for _, rawPk := range rawPks {
					var pk EthBlsPubKey
					status, err = pk.DeserializeCompressed(rawPk)
					if err != nil {
						require.Equal(t, status, test.Output)
						return
					}
					pks = append(pks, pk)
				}
				var sig EthBlsSignature
				status, err = sig.DeserializeCompressed(rawSig)
				if err != nil {
					require.Equal(t, status, test.Output)
					return
				}
				var msg EthBlsMessage
				err = msg.UnmarshalText([]byte(test.Input.Message))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				status, err = FastAggregateVerify(pks, msg[:], sig)
			}
			require.Equal(t, status, test.Output)
			if status != test.Output {
				fmt.Println("Verification differs from expected \n",
				    "   valid sig? ", status, "\n",
				    "   expected: ", test.Output,
				)
				return
			}
		})
	}
}

func TestAggregateVerify(t *testing.T) {
	type Test struct {
		Input struct {
			PubKeys []string `json:"pubkeys"`
			Messages []string `json:"messages"`
			Signature string `json:"signature"`

		} `json:"input"`
		Output bool `json:"output"`
	}

	tests, _ := filepath.Glob(aggregate_verifyTests)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			testFile, err := os.Open(testPath)
			test := Test{}
			err = json.NewDecoder(testFile).Decode(&test)

			var rawPks []EthBlsPubKeyRaw
			for _, s := range test.Input.PubKeys {
				var rawPk EthBlsPubKeyRaw
				err = rawPk.UnmarshalText([]byte(s))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				rawPks = append(rawPks, rawPk)
			}
			var rawSig EthBlsSignatureRaw
			err = rawSig.UnmarshalText([]byte(test.Input.Signature))
			if err != nil {
				require.False(t, test.Output) // tampered signaure test
				return
			}

			var status bool
			{ // testChecks
				var pks []EthBlsPubKey
				for _, rawPk := range rawPks {
					var pk EthBlsPubKey
					status, err = pk.DeserializeCompressed(rawPk)
					if err != nil {
						require.Equal(t, status, test.Output)
						return
					}
					pks = append(pks, pk)
				}
				var sig EthBlsSignature
				status, err = sig.DeserializeCompressed(rawSig)
				if err != nil {
					require.Equal(t, status, test.Output)
					return
				}
				var msgs [][]byte
				for _, rawMsg := range test.Input.Messages {
					var msg EthBlsMessage
					err = msg.UnmarshalText([]byte(rawMsg))
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					msgs = append(msgs, msg[:])
				}
				status, err = AggregateVerify(pks, msgs[:], sig)
			}
			require.Equal(t, status, test.Output)
			if status != test.Output {
				fmt.Println("Verification differs from expected \n",
				    "   valid sig? ", status, "\n",
				    "   expected: ", test.Output,
				)
				return
			}
		})
	}
}

func TestBatchVerify(t *testing.T) {
	type Test struct {
		Input struct {
			PubKeys []string `json:"pubkeys"`
			Messages []string `json:"messages"`
			Signatures []string `json:"signatures"`

		} `json:"input"`
		Output bool `json:"output"`
	}

	// for BatchVerifyParallel
	tp := createTestThreadpool(t)

	tests, _ := filepath.Glob(batch_verifyTests)
	for _, testPath := range tests {
		// Don't use t.Run() with parallel C code to not mess up thread-local storage
		testFile, err := os.Open(testPath)
		test := Test{}
		err = json.NewDecoder(testFile).Decode(&test)

		var rawPks []EthBlsPubKeyRaw
		for _, s := range test.Input.PubKeys {
			var rawPk EthBlsPubKeyRaw
			err = rawPk.UnmarshalText([]byte(s))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}
			rawPks = append(rawPks, rawPk)
		}
		var rawSigs []EthBlsSignatureRaw
		for _, s := range test.Input.Signatures {
			var rawSig EthBlsSignatureRaw
			err = rawSig.UnmarshalText([]byte(s))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}
			rawSigs = append(rawSigs, rawSig)
		}

		var status bool
		{ // testChecks
			var pks []EthBlsPubKey
			for _, rawPk := range rawPks {
				var pk EthBlsPubKey
				status, err = pk.DeserializeCompressed(rawPk)
				if err != nil {
					require.Equal(t, status, test.Output)
					return
				}
				pks = append(pks, pk)
			}
			var sigs []EthBlsSignature
			for _, rawSig := range rawSigs {
				var sig EthBlsSignature
				status, err = sig.DeserializeCompressed(rawSig)
				if err != nil {
					require.Equal(t, status, test.Output)
					return
				}
				sigs = append(sigs, sig)
			}
			var msgs [][]byte
			for _, rawMsg := range test.Input.Messages {
				var msg EthBlsMessage
				err = msg.UnmarshalText([]byte(rawMsg))
				if err != nil {
					require.Nil(t, test.Output)
					return
				}
				msgs = append(msgs, msg[:])
			}
			var randomBytes [32]byte
			sha256.Hash(&randomBytes, []byte("totally non-secure source of entropy"), false)

			status, err = BatchVerify(pks, msgs[:], sigs, randomBytes)

			// and parallel API
			parallelStatus, _ := BatchVerifyParallel(tp, pks, msgs[:], sigs, randomBytes)
			require.Equal(t, parallelStatus, test.Output)
		}
		require.Equal(t, status, test.Output)
		if status != test.Output {
			fmt.Println("Verification differs from expected \n",
			    "   valid sig? ", status, "\n",
			    "   expected: ", test.Output,
			)
			return
		}
	}
}
