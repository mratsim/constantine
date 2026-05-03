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
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/mratsim/constantine/constantine-go/sha256"
)

// Ethereum BLS Signature tests
// ----------------------------------------------------------
//
// Source: https://github.com/ethereum/bls-specs

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

// To be removed. This is the C example ported
func TestExampleCBlsSig(t *testing.T) {
	fmt.Println("Running BLS signature example test")
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

func TestDeserializeG1(t *testing.T) {
	fmt.Println("Running test for path: ", deserialization_G1Tests)
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
	fmt.Println("Running test for path: ", deserialization_G2Tests)
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
	fmt.Println("Running test for path: ", signTests)
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
					return
				}
			}
		})
	}
}

func TestVerify(t *testing.T) {
	fmt.Println("Running test for path: ", verifyTests)
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
	fmt.Println("Running test for path: ", fast_aggregate_verifyTests)
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
	fmt.Println("Running test for path: ", batch_verifyTests)
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