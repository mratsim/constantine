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
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"encoding/json"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"

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
	trustedSetupFile             = "../constantine/commitments_setups/trusted_setup_ethereum_kzg4844_reference.dat"
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

func TestBlobToKzgCommitment(t *testing.T) {
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

			commitment, err := ctx.BlobToKzgCommitment(blob)
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

func TestBlobToKzgCommitmentParallel(t *testing.T) {
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
	ctx.SetThreadpool(tp)

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

		commitment, err := ctx.BlobToKzgCommitmentParallel(blob)
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
	ctx.SetThreadpool(tp)

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

		proof, y, err := ctx.ComputeKzgProofParallel(blob, z)
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
	ctx.SetThreadpool(tp)

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

		proof, err := ctx.ComputeBlobKzgProofParallel(blob, commitment)
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
	ctx.SetThreadpool(tp)

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

		valid, err := ctx.VerifyBlobKzgProofParallel(blob, commitment, proof)
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
	ctx.SetThreadpool(tp)

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

		valid, err := ctx.VerifyBlobKzgProofBatchParallel(blobs, commitments, proofs, secureRandomBytes)
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
	str := "Security pb becomes key mgmt pb!"
	var rawSecKey [32]byte
	copy(rawSecKey[:], str)
	secKey, err := DeserializeSecKey(rawSecKey)
	fmt.Println("deserialized: err = ", err)

	// Derive the matching public key
	pubKey := DerivePubKey(secKey)

	// Sign a message
	message := sha256.Hash([]byte("Mr F was here"), false)

	fmt.Println("message: ", message)
	sig := Sign(secKey, message[:])
	fmt.Println("signed:  err = ", err)

	// Verify that a signature is valid for a message under the provided public key
	status, err := pubKey.Verify(message[:], sig)
	fmt.Println("verified: status", status, " err = ", err)

	// try to use batch verify; We just reuse the data from above 3 times
	pkeys := []EthBlsPubKey{pubKey, pubKey, pubKey}
	msgs := [][]byte{message[:], message[:], message[:]}
	sigs := []EthBlsSignature{sig, sig, sig}
	var srb [32]byte // leave zero
	status, err = BatchVerifySoA(pkeys, msgs, sigs, srb)
	fmt.Println("batchverified: Status ", status, " err = ", err)
}

var (
	testDirBls                 = "../tests/protocol_blssig_pop_on_bls12381_g2_test_vectors_v0.1.1"
	aggregate_verifyTests      = filepath.Join(testDirBls, "aggregate_verify/*")
	aggregateTests             = filepath.Join(testDirBls, "aggregate/*")
	deserialization_G1Tests    = filepath.Join(testDirBls, "deserialization_G1/*")
	batch_verifyTests          = filepath.Join(testDirBls, "batch_verify/*")
	fast_aggregate_verifyTests = filepath.Join(testDirBls, "fast_aggregate_verify/*")
	hash_to_G2Tests            = filepath.Join(testDirBls, "hash_to_G2/*")
	deserialization_G2Tests    = filepath.Join(testDirBls, "deserialization_G2/*")
	verifyTests                = filepath.Join(testDirBls, "verify/*")
	signTests                  = filepath.Join(testDirBls, "sign/*")
)

// These types correspond to the serialized pub/sec keys / signatures
// (and test messages / test outputs)
type (
	EthBlsPubKeyRaw    Bytes48
	EthBlsSignatureRaw Bytes96
	EthBlsSecKeyRaw    Bytes32
	EthBlsMessage      Bytes32
	EthBlsTestOutput   Bytes96
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

			pk, err := DeserializePubKeyCompressed(Bytes48(rawPk))

			if err == nil {
				s, err := pk.SerializeCompressed()
				if err != nil {
					require.Nil(t, test.Output)
				}
				require.Equal(t, s[:], rawPk[:])
				// Indicates test is supposed to pass
				require.Equal(t, true, test.Output)
			} else {
				// Indicates test is supposed to fail
				require.Equal(t, false, test.Output)
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

			sig, err := DeserializeSignatureCompressed(Bytes96(rawSig))

			if err == nil {
				s, err := sig.SerializeCompressed()
				if err != nil {
					require.Nil(t, test.Output)
				}
				require.Equal(t, s[:], rawSig[:])
				// Indicates test intends to pass
				require.Equal(t, true, test.Output)
			} else {
				// Indicates test is supposed to fail
				require.Equal(t, false, test.Output)
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

			secKey, err := DeserializeSecKey(Bytes32(rawSecKey))
			if err != nil {
				// sanity check the output matches status
				require.Equal(t, test.Output, "") // one file: has `null` JSON value
				//require.Equal(t, status, test.Output)
				_ = Sign(secKey, msg[:])
			} else {
				// sign the message
				sig := Sign(secKey, msg[:])
				{ // deserialiaze output for extra codec testing
					output, err := DeserializeSignatureCompressed(Bytes96(tOut))
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					status := sig.AreEqual(output)
					if !status { // signatures mismatch
						var sigBytes Bytes96
						var roundTrip Bytes96
						sigBytes, sb_err := sig.SerializeCompressed()
						roundTrip, rt_err := output.SerializeCompressed()
						fmt.Println("\nResult signature differs from expected \n",
							"   computed:  0x", sigBytes, " (", sb_err, ")\n",
							"   roundtrip: 0x", roundTrip, " (", rt_err, ")\n",
							"   expected:  0x", test.Output,
						)
						require.True(t, false) // fail the test case
						return
					}

				}
				{ // serialize result for extra codec testing
					sigBytes, err := sig.SerializeCompressed()
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
			PubKey    string `json:"pubkey"`
			Message   string `json:"message"`
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


			// Test checks
			var status bool
			pk, err := DeserializePubKeyCompressed(Bytes48(rawPk))
			if err != nil {
				require.Nil(t, test.Output)
				return
			}
			sig, err := DeserializeSignatureCompressed(Bytes96(rawSig))
			if err != nil { // expected this verification fails?
				require.Equal(t, false, test.Output)
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
			if status != test.Output {
				fmt.Println("Verification differs from expected \n",
					"   valid sig? ", status, "\n",
					"   expected: ", test.Output,
				)
				require.True(t, false)
				return
			} else if status {
				{
					output, err := pk.SerializeCompressed()
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					require.Equal(t, output[:], rawPk[:])
				}
				{
					output, err := sig.SerializeCompressed()
					if err != nil {
						require.Nil(t, test.Output)
						return
					}
					require.Equal(t, output[:], rawSig[:])
				}
			}
		})
	}
}

func TestFastAggregateVerify(t *testing.T) {
	type Test struct {
		Input struct {
			PubKeys   []string `json:"pubkeys"`
			Message   string   `json:"message"`
			Signature string   `json:"signature"`
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
					pk, err := DeserializePubKeyCompressed(Bytes48(rawPk))
					if err != nil {
						require.Equal(t, status, test.Output)
						return
					}
					pks = append(pks, pk)
				}
				sig, err := DeserializeSignatureCompressed(Bytes96(rawSig))
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

// NOTE: The aggregate verify test case is currently not used, because at the moment
// we don't wrap aggregate test. It requires to expose the `BLSAggregateSigAccumulator`
// type from Nim to C similarly to the batch sig accumulator. Once we have done so
// we'll add back the test.

//func TestAggregateVerify(t *testing.T) {
//	type Test struct {
//		Input struct {
//			PubKeys []string `json:"pubkeys"`
//			Messages []string `json:"messages"`
//			Signature string `json:"signature"`
//
//		} `json:"input"`
//		Output bool `json:"output"`
//	}
//
//	tests, _ := filepath.Glob(aggregate_verifyTests)
//	for _, testPath := range tests {
//		t.Run(testPath, func(t *testing.T) {
//			testFile, err := os.Open(testPath)
//			test := Test{}
//			err = json.NewDecoder(testFile).Decode(&test)
//
//			var rawPks []EthBlsPubKeyRaw
//			for _, s := range test.Input.PubKeys {
//				var rawPk EthBlsPubKeyRaw
//				err = rawPk.UnmarshalText([]byte(s))
//				if err != nil {
//					require.Nil(t, test.Output)
//					return
//				}
//				rawPks = append(rawPks, rawPk)
//			}
//			var rawSig EthBlsSignatureRaw
//			err = rawSig.UnmarshalText([]byte(test.Input.Signature))
//			if err != nil {
//				require.False(t, test.Output) // tampered signaure test
//				return
//			}
//
//			var status bool
//			{ // testChecks
//				var pks []EthBlsPubKey
//				for _, rawPk := range rawPks {
//					var pk EthBlsPubKey
//					status, err = pk.DeserializeCompressed(rawPk)
//					if err != nil {
//						require.Equal(t, status, test.Output)
//						return
//					}
//					pks = append(pks, pk)
//				}
//				var sig EthBlsSignature
//				status, err = sig.DeserializeCompressed(rawSig)
//				if err != nil {
//					require.Equal(t, status, test.Output)
//					return
//				}
//				var msgs [][]byte
//				for _, rawMsg := range test.Input.Messages {
//					var msg EthBlsMessage
//					err = msg.UnmarshalText([]byte(rawMsg))
//					if err != nil {
//						require.Nil(t, test.Output)
//						return
//					}
//					msgs = append(msgs, msg[:])
//				}
//				status, err = AggregateVerify(pks, msgs[:], sig)
//
//				// And now the Go version
//				status, err = AggregateVerifyGo(pks, msgs[:], sig)
//			}
//			require.Equal(t, status, test.Output)
//			if status != test.Output {
//				fmt.Println("Verification differs from expected \n",
//				    "   valid sig? ", status, "\n",
//				    "   expected: ", test.Output,
//				)
//				return
//			}
//		})
//	}
//}

func TestBatchVerify(t *testing.T) {
	type Test struct {
		Input struct {
			PubKeys    []string `json:"pubkeys"`
			Messages   []string `json:"messages"`
			Signatures []string `json:"signatures"`
		} `json:"input"`
		Output bool `json:"output"`
	}

	tests, _ := filepath.Glob(batch_verifyTests)
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
					pk, err := DeserializePubKeyCompressed(Bytes48(rawPk))
					if err != nil {
						require.Equal(t, status, test.Output)
						return
					}
					pks = append(pks, pk)
				}
				var sigs []EthBlsSignature
				for _, rawSig := range rawSigs {
					sig, err := DeserializeSignatureCompressed(Bytes96(rawSig))
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
				randomBytes := sha256.Hash([]byte("totally non-secure source of entropy"), false)

				// Now batch verify using SoA API
				status, err = BatchVerifySoA(pks, msgs[:], sigs, randomBytes)
				require.Equal(t, status, test.Output)

				// And using triplets of the data and use `BatchVerifyAoS`
				trp := make([]BatchVerifyTriplet, len(pks), len(pks))
				for i, _ := range trp {
					trp[i] = BatchVerifyTriplet{pub: pks[i], message: msgs[i], sig: sigs[i]}
				}
				status, err = BatchVerifyAoS(trp, randomBytes)
				require.Equal(t, status, test.Output)

				// TODO: The parallel API needs to be reimplemented using parallelism on the Go side
				// and parallel API
				// parallelStatus, _ := BatchVerifyParallel(tp, pks, msgs[:], sigs, randomBytes)
				// require.Equal(t, parallelStatus, test.Output)
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

// --------------------------------
// ------- EVM precompiles --------
// --------------------------------

func TestSha256(t *testing.T) {
	input := "38d18acb67d25c8bb9942764b62f18e17054f66a817bd4295423adf9ed98873e000000000000000000000000000000000000000000000000000000000000001b38d18acb67d25c8bb9942764b62f18e17054f66a817bd4295423adf9ed98873e789d1dd423d25f0772d2748d60f7e4b81bb14d086eba8e8e8efb6dcff8a4ae02"
	expected := "811c7003375852fabd0d362e40e68607a12bdabae61a7d068fe5fdd1dbbf2a5d"
	fmt.Println("Running SHA256 tests")

	var inputBytes []byte
	inputBytes = make([]byte, len(input)/2, len(input)/2)
	var expectedBytes []byte
	expectedBytes = make([]byte, len(expected)/2, len(expected)/2)

	err := fromHexImpl(inputBytes[:], []byte(input))
	if err != nil {
		require.True(t, false)
	}
	err = fromHexImpl(expectedBytes[:], []byte(expected))
	if err != nil {
		require.True(t, false)
	}

	r, err := EvmSha256(inputBytes)
	if err != nil {
		require.True(t, false)
	}

	require.Equal(t, r[:], expectedBytes[:])
	fmt.Println("Success")
}

var (
	testDirEvm = "../tests/protocol_ethereum_evm_precompiles/"

	modexp_tests         = filepath.Join(testDirEvm, "modexp.json")
	modexp_eip2565_tests = filepath.Join(testDirEvm, "modexp_eip2565.json")

	bn256Add_tests       = filepath.Join(testDirEvm, "bn256Add.json")
	bn256ScalarMul_tests = filepath.Join(testDirEvm, "bn256ScalarMul.json")
	bn256Pairing_tests   = filepath.Join(testDirEvm, "bn256Pairing.json")

	add_G1_bls_tests      = filepath.Join(testDirEvm, "eip-2537/add_G1_bls.json")
	fail_add_G1_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-add_G1_bls.json")
	add_G2_bls_tests      = filepath.Join(testDirEvm, "eip-2537/add_G2_bls.json")
	fail_add_G2_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-add_G2_bls.json")

	mul_G1_bls_tests      = filepath.Join(testDirEvm, "eip-2537/mul_G1_bls.json")
	fail_mul_G1_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-mul_G1_bls.json")
	mul_G2_bls_tests      = filepath.Join(testDirEvm, "eip-2537/mul_G2_bls.json")
	fail_mul_G2_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-mul_G2_bls.json")

	multiexp_G1_bls_tests      = filepath.Join(testDirEvm, "eip-2537/multiexp_G1_bls.json")
	fail_multiexp_G1_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-multiexp_G1_bls.json")
	multiexp_G2_bls_tests      = filepath.Join(testDirEvm, "eip-2537/multiexp_G2_bls.json")
	fail_multiexp_G2_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-multiexp_G2_bls.json")

	pairing_check_bls_tests      = filepath.Join(testDirEvm, "eip-2537/pairing_check_bls.json")
	fail_pairing_check_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-pairing_check_bls.json")

	map_fp_to_G1_bls_tests       = filepath.Join(testDirEvm, "eip-2537/map_fp_to_G1_bls.json")
	fail_map_fp_to_G1_bls_tests  = filepath.Join(testDirEvm, "eip-2537/fail-map_fp_to_G1_bls.json")
	map_fp2_to_G2_bls_tests      = filepath.Join(testDirEvm, "eip-2537/map_fp2_to_G2_bls.json")
	fail_map_fp2_to_G2_bls_tests = filepath.Join(testDirEvm, "eip-2537/fail-map_fp2_to_G2_bls.json")
)

type HexString string
type PrecompileTest struct {
	Input       HexString
	Expected    HexString
	Name        string
	Gas         int
	NoBenchmark bool
}

func loadVectors(fname string) (result []PrecompileTest, status bool) {
	var test []PrecompileTest

	testFile, err := os.Open(fname)
	err = json.NewDecoder(testFile).Decode(&test)
	if err != nil {
		return test, false
	}

	return test, true
}

func parseTest(vec PrecompileTest) (inputBytes []byte, expectedBytes []byte, success bool) {
	input := vec.Input
	expected := vec.Expected

	inputBytes = make([]byte, len(input)/2, len(input)/2)
	expectedBytes = make([]byte, len(expected)/2, len(expected)/2)

	err := fromHexImpl(inputBytes[:], []byte(input))
	if err != nil {
		return inputBytes, expectedBytes, false
	}
	err = fromHexImpl(expectedBytes[:], []byte(expected))
	if err != nil {
		return inputBytes, expectedBytes, false
	}

	return inputBytes, expectedBytes, true
}

type TF func([]byte) ([]byte, error)
type TF32 func([]byte) (Bytes32, error)
type TF64 func([]byte) (Bytes64, error)
type TF128 func([]byte) (Bytes128, error)
type TF256 func([]byte) (Bytes256, error)

// Helper function to simplify the test generation. No need to duplicate test logic, all the same
func runTestSlice(t *testing.T, testPath string, fn TF) {
	fmt.Println("Running test for path: ", testPath)
	tests, _ := filepath.Glob(testPath)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			// Load from the given path
			vectors, pStatus := loadVectors(testPath)
			if !pStatus {
				require.True(t, false)
			}
			for _, vec := range vectors {
				fmt.Println("Running test case: ", vec.Name)

				inputBytes, expectedBytes, status := parseTest(vec)
				if !status {
					require.True(t, false)
				}

				// Call the test function
				r, err := fn(inputBytes)
				if err != nil {
					// in this case expected should be empty
					require.Equal(t, expectedBytes[:], r[:])
				} else {
					require.Equal(t, expectedBytes[:], r[:])
				}
			}
		})
	}
}

func runTestB32(t *testing.T, testPath string, fn TF32) {
	fmt.Println("Running test for path: ", testPath)
	tests, _ := filepath.Glob(testPath)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			// Load from the given path
			vectors, pStatus := loadVectors(testPath)
			if !pStatus {
				require.True(t, false)
			}
			for _, vec := range vectors {
				fmt.Println("Running test case: ", vec.Name)

				inputBytes, expectedBytes, status := parseTest(vec)
				if !status {
					require.True(t, false)
				}

				// Call the test function
				r, err := fn(inputBytes)
				if err != nil {
					// in this case expected should be empty
					require.Equal(t, 0, len(expectedBytes))
				} else {
					require.Equal(t, expectedBytes[:], r[:])
				}
			}
		})
	}
}

func runTestB64(t *testing.T, testPath string, fn TF64) {
	fmt.Println("Running test for path: ", testPath)
	tests, _ := filepath.Glob(testPath)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			// Load from the given path
			vectors, pStatus := loadVectors(testPath)
			if !pStatus {
				require.True(t, false)
			}
			for _, vec := range vectors {
				fmt.Println("Running test case: ", vec.Name)

				inputBytes, expectedBytes, status := parseTest(vec)
				if !status {
					require.True(t, false)
				}


				// Call the test function
				r, err := fn(inputBytes)
				if err != nil {
					// in this case expected should be empty
					require.Equal(t, 0, len(expectedBytes))
				} else {
					require.Equal(t, expectedBytes[:], r[:])
				}
			}
		})
	}
}

func runTestB128(t *testing.T, testPath string, fn TF128) {
	fmt.Println("Running test for path: ", testPath)
	tests, _ := filepath.Glob(testPath)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			// Load from the given path
			vectors, pStatus := loadVectors(testPath)
			if !pStatus {
				require.True(t, false)
			}
			for _, vec := range vectors {
				fmt.Println("Running test case: ", vec.Name)

				inputBytes, expectedBytes, status := parseTest(vec)
				if !status {
					require.True(t, false)
				}

				// Call the test function
				r, err := fn(inputBytes)
				if err != nil {
					// in this case expected should be empty
					require.Equal(t, 0, len(expectedBytes))
				} else {
					require.Equal(t, expectedBytes[:], r[:])
				}
			}
		})
	}
}

func runTestB256(t *testing.T, testPath string, fn TF256) {
	fmt.Println("Running test for path: ", testPath)
	tests, _ := filepath.Glob(testPath)
	for _, testPath := range tests {
		t.Run(testPath, func(t *testing.T) {
			// Load from the given path
			vectors, pStatus := loadVectors(testPath)
			if !pStatus {
				require.True(t, false)
			}
			for _, vec := range vectors {
				fmt.Println("Running test case: ", vec.Name)

				inputBytes, expectedBytes, status := parseTest(vec)
				if !status {
					require.True(t, false)
				}

				// Call the test function
				r, err := fn(inputBytes)
				if err != nil {
					// in this case expected should be empty
					require.Equal(t, 0, len(expectedBytes))
				} else {
					require.Equal(t, expectedBytes[:], r[:])
				}
			}
		})
	}
}

func TestModexp(t *testing.T) {
	runTestSlice(t, modexp_tests, EvmModexp)
}

func TestModexpEip2565(t *testing.T) {
	runTestSlice(t, modexp_eip2565_tests, EvmModexp)
}

func TestBn256Add(t *testing.T) {
	runTestB64(t, bn256Add_tests, EvmBn254G1Add)
}

func TestBn256ScalarMul(t *testing.T) {
	runTestB64(t, bn256ScalarMul_tests, EvmBn254G1Mul)
}

func TestBn256Pairing(t *testing.T) {
	runTestB32(t, bn256Pairing_tests, EvmBn254G1EcPairingCheck)
}

func TestAddG1Bls(t *testing.T) {
	runTestB128(t, add_G1_bls_tests, EvmBls12381G1Add)
}

func TestFailAddG1Bls(t *testing.T) {
	runTestB128(t, fail_add_G1_bls_tests, EvmBls12381G1Add)
}

func TestAddG2Bls(t *testing.T) {
	runTestB256(t, add_G2_bls_tests, EvmBls12381G2Add)
}

func TestFailAddG2Bls(t *testing.T) {
	runTestB256(t, fail_add_G2_bls_tests, EvmBls12381G2Add)
}

func TestMulG1Bls(t *testing.T) {
	runTestB128(t, mul_G1_bls_tests, EvmBls12381G1Mul)
}

func TestFailMulG1Bls(t *testing.T) {
	runTestB128(t, fail_mul_G1_bls_tests, EvmBls12381G1Mul)
}

func TestMulG2Bls(t *testing.T) {
	runTestB256(t, mul_G2_bls_tests, EvmBls12381G2Mul)
}

func TestFailMulG2Bls(t *testing.T) {
	runTestB256(t, fail_mul_G2_bls_tests, EvmBls12381G2Mul)
}

func TestMsmG1Bls(t *testing.T) {
	runTestB128(t, multiexp_G1_bls_tests, EvmBls12381G1Msm)
}

func TestFailMsmG1Bls(t *testing.T) {
	runTestB128(t, fail_multiexp_G1_bls_tests, EvmBls12381G1Msm)
}

func TestMsmG2Bls(t *testing.T) {
	runTestB256(t, multiexp_G2_bls_tests, EvmBls12381G2Msm)
}

func TestFailMsmG2Bls(t *testing.T) {
	runTestB256(t, fail_multiexp_G2_bls_tests, EvmBls12381G2Msm)
}

func TestPairingCheckBls(t *testing.T) {
	runTestB32(t, pairing_check_bls_tests, EvmBls12381PairingCheck)
}

func TestFailPairingCheckBls(t *testing.T) {
	runTestB32(t, fail_pairing_check_bls_tests, EvmBls12381PairingCheck)
}

func TestMapFpToG1Bls(t *testing.T) {
	runTestB128(t, map_fp_to_G1_bls_tests, EvmBls12381MapFpToG1)
}

func TestFailMapFpToG1Bls(t *testing.T) {
	runTestB128(t, fail_map_fp_to_G1_bls_tests, EvmBls12381MapFpToG1)
}

func TestMapFp2ToG2Bls(t *testing.T) {
	runTestB256(t, map_fp2_to_G2_bls_tests, EvmBls12381MapFp2ToG2)
}

func TestFailMapFp2ToG2Bls(t *testing.T) {
	runTestB256(t, fail_map_fp2_to_G2_bls_tests, EvmBls12381MapFp2ToG2)
}
