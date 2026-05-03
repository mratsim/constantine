/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy Andr&eacute;-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */

package constantine

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"
)

// Ethereum EIP-7594 PeerDAS tests
// ----------------------------------------------------------
//
// Source: https://github.com/ethereum/consensus-spec-tests

var (
	peerdasTestDir             = "../tests/protocol_ethereum_eip7594_fulu_peerdas"
	computeCellsAndProofsTests = filepath.Join(peerdasTestDir, "compute_cells_and_kzg_proofs/kzg-mainnet/*/data.yaml")
	verifyCellKzgProofTests    = filepath.Join(peerdasTestDir, "verify_cell_kzg_proof_batch/kzg-mainnet/*/data.yaml")
	recoverCellsAndProofsTests = filepath.Join(peerdasTestDir, "recover_cells_and_kzg_proofs/kzg-mainnet/*/data.yaml")
)

// hexUnmarshal decodes a hex string (with optional 0x prefix) into dst.
// Returns ErrInvalidHex if the length doesn't match.
var ErrInvalidHex = fmt.Errorf("invalid hex length")

func hexUnmarshal(dst []byte, s string) error {
	if len(s) >= 2 && s[0:2] == "0x" {
		s = s[2:]
	}
	decoded, err := hex.DecodeString(s)
	if err != nil {
		return err
	}
	if len(decoded) != len(dst) {
		return ErrInvalidHex
	}
	copy(dst, decoded)
	return nil
}

func (dst *EthKzgCell) UnmarshalText(input []byte) error {
	return hexUnmarshal(dst[:], string(input))
}

// ---- compute_cells_and_kzg_proofs ----

type computeTestInput struct {
	Blob *string `yaml:"blob"`
}

type computeTest struct {
	Input  *computeTestInput `yaml:"input"`
	Output *[][]string       `yaml:"output"` // [[cells...], [proofs...]]
}

func TestComputeCellsAndKzgProofs(t *testing.T) {
	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(computeCellsAndProofsTests)
	require.NoError(t, err)
	require.NotEmpty(t, tests)

	for _, tf := range tests {
		testName := filepath.Base(filepath.Dir(tf))
		raw, rErr := os.ReadFile(tf)
		require.NoError(t, rErr)

		var test computeTest
		require.NoError(t, yaml.Unmarshal(raw, &test))

		// Invalid input -> no output
		if test.Input == nil || test.Input.Blob == nil {
			require.Nil(t, test.Output, "expected no output for missing input in %s", testName)
			t.Logf("    PASS: %s - missing input, no output expected", testName)
			continue
		}

		var blob EthBlob
		if err := hexUnmarshal(blob[:], *test.Input.Blob); err != nil {
			require.Nil(t, test.Output, "expected no output for invalid blob in %s", testName)
			t.Logf("    PASS: %s - invalid blob, no output expected", testName)
			continue
		}

		cells, proofs, err := ctx.ComputeCellsAndKzgProofs(blob)
		if err != nil {
			require.Nil(t, test.Output, "expected failure for %s", testName)
			t.Logf("    PASS: %s - expected failure", testName)
			continue
		}

		require.NotNil(t, test.Output, "expected output for %s", testName)

		expCells := (*test.Output)[0]
		expProofs := (*test.Output)[1]
		require.Len(t, expCells, 128)
		require.Len(t, expProofs, 128)

		for i := 0; i < 128; i++ {
			expCell, _ := hex.DecodeString(expCells[i][2:])
			expProof, _ := hex.DecodeString(expProofs[i][2:])
			require.Equal(t, expCell, cells[i][:], "cell %d mismatch in %s", i, testName)
			require.Equal(t, expProof, proofs[i][:], "proof %d mismatch in %s", i, testName)
		}

		t.Logf("    PASS: %s", testName)
	}
}

// ---- verify_cell_kzg_proof_batch ----

func TestVerifyCellKzgProofBatch(t *testing.T) {
	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	var secureRandomBytes [32]byte
	_, _ = rand.Read(secureRandomBytes[:])

	tests, err := filepath.Glob(verifyCellKzgProofTests)
	require.NoError(t, err)
	require.NotEmpty(t, tests)

	for _, tf := range tests {
		testName := filepath.Base(filepath.Dir(tf))
		raw, rErr := os.ReadFile(tf)
		require.NoError(t, rErr)

		// Parse YAML: format is {input: {commitments, cell_indices, cells, proofs}, output: bool|null}
		type verifyInput struct {
			Commitments []string `yaml:"commitments"`
			CellIndices []uint64 `yaml:"cell_indices"`
			Cells       []string `yaml:"cells"`
			Proofs      []string `yaml:"proofs"`
		}
		type verifyTest struct {
			Input  *verifyInput `yaml:"input"`
			Output *bool        `yaml:"output"`
		}

		var test verifyTest
		require.NoError(t, yaml.Unmarshal(raw, &test))

		commitments := []string{}
		cellIndices := []uint64{}
		cellsRaw := []string{}
		proofsRaw := []string{}
		output := test.Output

		if test.Input != nil {
			commitments = test.Input.Commitments
			cellIndices = test.Input.CellIndices
			cellsRaw = test.Input.Cells
			proofsRaw = test.Input.Proofs
		}

		// No input at all -> no output
		if test.Input == nil {
			require.Nil(t, output, "expected no output for missing input in %s", testName)
			t.Logf("    PASS: %s - missing input", testName)
			continue
		}

		// Empty arrays (all zero-length) -> spec says verification succeeds
		if len(commitments) == 0 && len(cellIndices) == 0 && len(cellsRaw) == 0 && len(proofsRaw) == 0 {
			require.NotNil(t, output, "expected output for empty arrays in %s", testName)
			require.True(t, *output, "empty batch should verify as true in %s", testName)
			t.Logf("    PASS: %s - empty arrays, output is true", testName)
			continue
		}

		// Decode commitments
		commitmentsDec := make([]EthKzgCommitment, len(commitments))
		badCommitment := false
		for i, c := range commitments {
			if err := hexUnmarshal(commitmentsDec[i][:], c); err != nil {
				badCommitment = true
				break
			}
		}
		if badCommitment {
			require.Nil(t, output, "expected no output for invalid commitment in %s", testName)
			t.Logf("    PASS: %s - invalid commitment", testName)
			continue
		}

		// Decode cells
		cellsDec := make([]EthKzgCell, len(cellsRaw))
		badCell := false
		for i, c := range cellsRaw {
			if err := hexUnmarshal(cellsDec[i][:], c); err != nil {
				badCell = true
				break
			}
		}
		if badCell {
			require.Nil(t, output, "expected no output for invalid cell in %s", testName)
			t.Logf("    PASS: %s - invalid cell", testName)
			continue
		}

		// Decode proofs
		proofsDec := make([]EthKzgProof, len(proofsRaw))
		badProof := false
		for i, p := range proofsRaw {
			if err := hexUnmarshal(proofsDec[i][:], p); err != nil {
				badProof = true
				break
			}
		}
		if badProof {
			require.Nil(t, output, "expected no output for invalid proof in %s", testName)
			t.Logf("    PASS: %s - invalid proof", testName)
			continue
		}

		// Length mismatch -> no expected output
		if len(commitmentsDec) != len(cellIndices) ||
			len(commitmentsDec) != len(cellsDec) ||
			len(commitmentsDec) != len(proofsDec) {
			require.Nil(t, output, "expected no output for length mismatch in %s", testName)
			t.Logf("    PASS: %s - input length mismatch", testName)
			continue
		}

		// Empty arrays -> special case
		if len(commitmentsDec) == 0 {
			require.Nil(t, output, "expected no output for empty arrays in %s", testName)
			t.Logf("    PASS: %s - empty arrays", testName)
			continue
		}

		valid, err := ctx.VerifyCellKzgProofBatch(
			commitmentsDec, cellIndices, cellsDec, proofsDec, secureRandomBytes,
		)

		if err != nil {
			require.Nil(t, output, "expected failure for %s: %v", testName, err)
			t.Logf("    PASS: %s - expected failure: %v", testName, err)
			continue
		}

		require.NotNil(t, output, "expected output for %s", testName)
		require.Equal(t, *output, valid, "verification result mismatch in %s", testName)
		t.Logf("    PASS: %s", testName)
	}
}

// ---- recover_cells_and_kzg_proofs ----

type recoverTestInput struct {
	CellIndices []uint64 `yaml:"cell_indices"`
	Cells       []string `yaml:"cells"`
}

type recoverTest struct {
	Input  recoverTestInput `yaml:"input"`
	Output *[][]string      `yaml:"output"` // [[cells...], [proofs...]]
}

func TestRecoverCellsAndKzgProofs(t *testing.T) {
	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	tests, err := filepath.Glob(recoverCellsAndProofsTests)
	require.NoError(t, err)
	require.NotEmpty(t, tests)

	for _, tf := range tests {
		testName := filepath.Base(filepath.Dir(tf))
		raw, rErr := os.ReadFile(tf)
		require.NoError(t, rErr)

		var test recoverTest
		require.NoError(t, yaml.Unmarshal(raw, &test))

		// Decode cells
		cellsDec := make([]EthKzgCell, len(test.Input.Cells))
		badCell := false
		for i, c := range test.Input.Cells {
			if err := hexUnmarshal(cellsDec[i][:], c); err != nil {
				badCell = true
				break
			}
		}
		if badCell {
			require.Nil(t, test.Output, "expected no output for invalid cell in %s", testName)
			t.Logf("    PASS: %s - invalid cell", testName)
			continue
		}

		// Length mismatch
		if len(cellsDec) != len(test.Input.CellIndices) {
			require.Nil(t, test.Output, "expected no output for length mismatch in %s", testName)
			t.Logf("    PASS: %s - length mismatch", testName)
			continue
		}

		// Empty arrays
		if len(cellsDec) == 0 {
			require.Nil(t, test.Output, "expected no output for empty input in %s", testName)
			t.Logf("    PASS: %s - empty input", testName)
			continue
		}

		recoveredProofs, recoveredCells, err := ctx.RecoverCellsAndKzgProofs(
			cellsDec, test.Input.CellIndices,
		)

		if err != nil {
			require.Nil(t, test.Output, "expected failure for %s: %v", testName, err)
			t.Logf("    PASS: %s - expected failure: %v", testName, err)
			continue
		}

		require.NotNil(t, test.Output, "expected output for %s", testName)

		expCells := (*test.Output)[0]
		expProofs := (*test.Output)[1]
		require.Len(t, expCells, 128)
		require.Len(t, expProofs, 128)

		for i := 0; i < 128; i++ {
			expCell, _ := hex.DecodeString(expCells[i][2:])
			expProof, _ := hex.DecodeString(expProofs[i][2:])
			require.Equal(t, expCell, recoveredCells[i][:], "recovered cell %d mismatch in %s", i, testName)
			require.Equal(t, expProof, recoveredProofs[i][:], "recovered proof %d mismatch in %s", i, testName)
		}

		t.Logf("    PASS: %s", testName)
	}
}

// ---- Unit tests for error paths (not covered by test vectors) ----

func TestVerifyCellKzgProofBatch_LengthMismatch(t *testing.T) {
	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	var secRand [32]byte
	// commitments has 1 element, cellIndices has 2 — should return length mismatch error
	_, err := ctx.VerifyCellKzgProofBatch(
		[]EthKzgCommitment{{}},
		[]uint64{0, 1}, // different length
		[]EthKzgCell{{}},
		[]EthKzgProof{{}},
		secRand,
	)
	require.Error(t, err)
	require.Contains(t, err.Error(), "Lengths of inputs do not match")
}

func TestRecoverCellsAndKzgProofs_LengthMismatch(t *testing.T) {
	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	// cells has 1 element, cellIndices has 2 — should return length mismatch error
	_, _, err := ctx.RecoverCellsAndKzgProofs(
		[]EthKzgCell{{}},
		[]uint64{0, 1}, // different length
	)
	require.Error(t, err)
	require.Contains(t, err.Error(), "Lengths of inputs do not match")
}

// ---- Unit tests for ascending order check ----

func TestRecoverCellsAndKzgProofs_CellIndicesNotAscending(t *testing.T) {
	ctx, tsErr := EthKzgContextNew(trustedSetupFile)
	require.NoError(t, tsErr)
	defer ctx.Delete()

	// Provide 64 cells (minimum for recovery) with descending indices — should return error
	cels := make([]EthKzgCell, 64)
	// indices [64, 63, ..., 1] is not in ascending order
	indices := make([]uint64, 64)
	for i := 0; i < 64; i++ {
		indices[i] = uint64(64 - i)
	}
	_, _, err := ctx.RecoverCellsAndKzgProofs(cels, indices)
	require.Error(t, err)
	require.Contains(t, err.Error(), "CellIndicesNotAscending")
}
