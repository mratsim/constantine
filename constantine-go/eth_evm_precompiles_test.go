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
	"testing"

	"github.com/stretchr/testify/require"
)

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

	require.NoError(t, fromHexImpl(inputBytes[:], []byte(input)), "hex-decode input")
	require.NoError(t, fromHexImpl(expectedBytes[:], []byte(expected)), "hex-decode expected")

	r, err := EvmSha256(inputBytes)
	require.NoError(t, err, "EvmSha256")

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
	if err != nil {
		return nil, false
	}
	defer testFile.Close()

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