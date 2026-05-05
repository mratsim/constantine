//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::csprngs;
use constantine_ethereum_kzg::EthKzgContext;
use constantine_sys::ctt_eth_kzg_status;

use std::fs;
use std::path::Path;
use std::path::PathBuf;

use glob::glob;
use hex;
use serde::Deserialize;
use serde_yaml;

macro_rules! test_dir {
    () => {
        "../../tests/protocol_ethereum_eip7594_fulu_peerdas/"
    };
}

const COMPUTE_CELLS_AND_KZG_PROOFS_TESTS: &str =
    concat!(test_dir!(), "compute_cells_and_kzg_proofs/kzg-mainnet/*/data.yaml");
const VERIFY_CELL_KZG_PROOF_BATCH_TESTS: &str =
    concat!(test_dir!(), "verify_cell_kzg_proof_batch/kzg-mainnet/*/data.yaml");
const RECOVER_CELLS_AND_KZG_PROOFS_TESTS: &str =
    concat!(test_dir!(), "recover_cells_and_kzg_proofs/kzg-mainnet/*/data.yaml");

const SRS_PATH: &str =
    "../../constantine/commitments_setups/trusted_setup_ethereum_kzg4844_reference.dat";

// OptRawBytes / OptBytes pattern from t_eth_kzg4844.rs
struct OptRawBytes<const N: usize>(Option<Box<[u8; N]>>);

impl<const N: usize> hex::FromHex for OptRawBytes<N> {
    type Error = hex::FromHexError;
    fn from_hex<T: AsRef<[u8]>>(hex: T) -> Result<Self, Self::Error> {
        let raw = hex.as_ref();
        if raw.len() < 2 || &raw[..2] != b"0x" {
            return Ok(OptRawBytes::<N> { 0: None });
        }
        let mut res = Box::new([0_; N]);
        match hex::decode_to_slice(&raw[2..], &mut *res as &mut [u8]) {
            Ok(_) => Ok(OptRawBytes::<N> { 0: Some(res) }),
            Err(_) => Ok(OptRawBytes::<N> { 0: None }),
        }
    }
}

#[derive(Deserialize)]
#[serde(transparent)]
struct OptBytes<const N: usize> {
    #[serde(deserialize_with = "hex::serde::deserialize")]
    opt_bytes: OptRawBytes<N>,
}

// ============================================================================
// compute_cells_and_kzg_proofs
// ============================================================================

#[test]
fn t_compute_cells_and_kzg_proofs() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131_072>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Option<Input>,
        #[serde(default)]
        output: Option<(Vec<OptBytes<2048>>, Vec<OptBytes<48>>)>,
    }

    let test_files: Vec<PathBuf> = glob(COMPUTE_CELLS_AND_KZG_PROOFS_TESTS)
        .unwrap()
        .map(Result::unwrap)
        .collect();
    assert!(!test_files.is_empty());

    // Run with both no-precompute and precompute (t=256, b=8) contexts
    // to exercise both kNoPrecompute and kPrecompute code paths in polyphaseSpectrumBank.
    for (label, ctx) in [
        (
            "no-precompute",
            EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup should be loaded without error."),
        ),
        (
            "precompute (t=256, b=8)",
            EthKzgContext::builder()
                .load_trusted_setup_with_precompute(Path::new(SRS_PATH), 256, 8)
                .expect("Trusted setup with precompute should be loaded without error.")
                .build()
                .expect("Builder should succeed"),
        ),
    ] {
        println!("\n  Mode: {label}");
        for test_file in &test_files {
            let test_name = test_file
                .parent()
                .unwrap()
                .file_name()
                .unwrap()
                .to_str()
                .unwrap();
            let tv = format!("    Test vector: {:<88}", test_name);
            let unparsed = fs::read_to_string(test_file).unwrap();
            let test: Test = serde_yaml::from_str(&unparsed).expect(&format!(
                "Formatting should be consistent for file \"{}\"",
                &test_name
            ));

            let Some(input) = test.input else {
                assert!(test.output.is_none());
                println!("{tv}=> SUCCESS - expected missing input");
                continue;
            };

            let Some(blob) = input.blob.opt_bytes.0 else {
                assert!(test.output.is_none());
                println!("{tv}=> SUCCESS - expected deserialization failure");
                continue;
            };

            match ctx.compute_cells_and_kzg_proofs(&*blob) {
                Ok((cells_bytes, proofs_bytes)) => {
                    let (expected_cells, expected_proofs) = test.output.unwrap();
                    assert_eq!(expected_cells.len(), 128);
                    assert_eq!(expected_proofs.len(), 128);

                    for i in 0..128 {
                        let exp_cell = expected_cells[i].opt_bytes.0.as_ref().unwrap();
                        let exp_proof = expected_proofs[i].opt_bytes.0.as_ref().unwrap();
                        let cell_start = i * 2048;
                        let proof_start = i * 48;
                        assert_eq!(
                            &cells_bytes[cell_start..cell_start + 2048],
                            &exp_cell[..],
                            "cell {} mismatch for {}",
                            i,
                            test_name
                        );
                        assert_eq!(
                            &proofs_bytes[proof_start..proof_start + 48],
                            &exp_proof[..],
                            "proof {} mismatch for {}",
                            i,
                            test_name
                        );
                    }
                    println!("{tv}=> SUCCESS");
                }
                Err(status) => {
                    assert!(test.output.is_none());
                    println!("{tv}=> SUCCESS - expected failure {:?}", status);
                }
            }
        }
    }
}

// ============================================================================
// verify_cell_kzg_proof_batch
// ============================================================================

#[test]
fn t_verify_cell_kzg_proof_batch() {
    #[derive(Deserialize)]
    struct Input {
        commitments: Vec<OptBytes<48>>,
        cell_indices: Vec<u64>,
        cells: Vec<OptBytes<2048>>,
        proofs: Vec<OptBytes<48>>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Option<Input>,
        #[serde(default)]
        output: Option<bool>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let mut secure_random_bytes = [0u8; 32];
    csprngs::sysrand(secure_random_bytes.as_mut_slice());
    assert_ne!(secure_random_bytes, [0u8; 32]);

    let test_files: Vec<PathBuf> = glob(VERIFY_CELL_KZG_PROOF_BATCH_TESTS)
        .unwrap()
        .map(Result::unwrap)
        .collect();
    assert!(!test_files.is_empty());

    for test_file in test_files {
        let test_name = test_file
            .parent()
            .unwrap()
            .file_name()
            .unwrap()
            .to_str()
            .unwrap();
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_yaml::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        // Handle input: null test vectors
        let Some(input) = test.input else {
            assert!(test.output.is_none());
            println!("{tv}=> SUCCESS - expected missing input");
            continue;
        };

        // Capture original lengths before into_iter() consumes them.
        // If ANY field had unparseable entries, the entire test case is invalid input.
        // (matches c-kzg-4844 pattern: field-by-field parse validation).
        let commitments_orig_len = input.commitments.len();
        let cells_orig_len = input.cells.len();
        let proofs_orig_len = input.proofs.len();
        let cell_indices = input.cell_indices;

        // Collect only valid commitments/cells/proofs
        let commitments_raw: Vec<_> = input
            .commitments
            .into_iter()
            .filter_map(|v| v.opt_bytes.0)
            .map(|v| *v)
            .collect();
        let cells_raw: Vec<_> = input
            .cells
            .into_iter()
            .filter_map(|v| v.opt_bytes.0)
            .map(|v| *v)
            .collect();
        let proofs_raw: Vec<_> = input
            .proofs
            .into_iter()
            .filter_map(|v| v.opt_bytes.0)
            .map(|v| *v)
            .collect();

        if commitments_raw.len() != commitments_orig_len
            || cells_raw.len() != cells_orig_len
            || proofs_raw.len() != proofs_orig_len
        {
            assert!(test.output.is_none());
            println!("{tv}=> SUCCESS - expected parse failure");
            continue;
        }

        // Length mismatch means invalid input
        if commitments_raw.len() != cells_raw.len() || commitments_raw.len() != proofs_raw.len()
            || commitments_raw.len() != cell_indices.len()
        {
            assert!(test.output.is_none());
            println!("{tv}=> SUCCESS - expected input length mismatch");
            continue;
        }

        match ctx.verify_cell_kzg_proof_batch(
            &commitments_raw,
            &cell_indices,
            &cells_raw,
            &proofs_raw,
            &secure_random_bytes,
        ) {
            Ok(valid) => {
                assert_eq!(valid, test.output.unwrap());
                if valid {
                    println!("{tv}=> SUCCESS - successfully verified valid proof");
                } else {
                    println!("{tv}=> SUCCESS - successfully rejected invalid proof");
                }
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{tv}=> SUCCESS - expected failure {:?}", status);
            }
        }
    }
}

// ============================================================================
// recover_cells_and_kzg_proofs
// ============================================================================

#[test]
fn t_recover_cells_and_kzg_proofs() {
    #[derive(Deserialize)]
    struct Input {
        cell_indices: Vec<u64>,
        cells: Vec<OptBytes<2048>>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Option<Input>,
        #[serde(default)]
        output: Option<(Vec<OptBytes<2048>>, Vec<OptBytes<48>>)>,
    }

    let test_files: Vec<PathBuf> = glob(RECOVER_CELLS_AND_KZG_PROOFS_TESTS)
        .unwrap()
        .map(Result::unwrap)
        .collect();
    assert!(!test_files.is_empty());

    // Run with both no-precompute and precompute (t=256, b=8) contexts
    // to exercise both kNoPrecompute and kPrecompute code paths in polyphaseSpectrumBank.
    for (label, ctx) in [
        (
            "no-precompute",
            EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup should be loaded without error."),
        ),
        (
            "precompute (t=256, b=8)",
            EthKzgContext::builder()
                .load_trusted_setup_with_precompute(Path::new(SRS_PATH), 256, 8)
                .expect("Trusted setup with precompute should be loaded without error.")
                .build()
                .expect("Builder should succeed"),
        ),
    ] {
        println!("\n  Mode: {label}");
        for test_file in &test_files {
            let test_name = test_file
                .parent()
                .unwrap()
                .file_name()
                .unwrap()
                .to_str()
                .unwrap();
            let tv = format!("    Test vector: {:<88}", test_name);
            let unparsed = fs::read_to_string(test_file).unwrap();
            let test: Test = serde_yaml::from_str(&unparsed).expect(&format!(
                "Formatting should be consistent for file \"{}\"",
                &test_name
            ));

            // Handle input: null test vectors
            let Some(input) = test.input else {
                assert!(test.output.is_none());
                println!("{tv}=> SUCCESS - expected missing input");
                continue;
            };

            // Capture original length before into_iter() consumes it.
            let cells_orig_len = input.cells.len();
            let cell_indices = input.cell_indices;

            // Collect only valid cells
            let cells_raw: Vec<_> = input
                .cells
                .into_iter()
                .filter_map(|v| v.opt_bytes.0)
                .map(|v| *v)
                .collect();

            // If any cells had unparseable entries, the entire test case is invalid input.
            if cells_raw.len() != cells_orig_len {
                assert!(test.output.is_none());
                println!("{tv}=> SUCCESS - expected parse failure");
                continue;
            }

            // Length mismatch means invalid input
            if cells_raw.len() != cell_indices.len() {
                assert!(test.output.is_none());
                println!("{tv}=> SUCCESS - expected input length mismatch");
                continue;
            }

            match ctx.recover_cells_and_kzg_proofs(&cells_raw, &cell_indices) {
                Ok((cells_bytes, proofs_bytes)) => {
                    let (expected_cells, expected_proofs) = test.output.unwrap();
                    assert_eq!(expected_cells.len(), 128);
                    assert_eq!(expected_proofs.len(), 128);

                    for i in 0..128 {
                        let exp_cell = expected_cells[i].opt_bytes.0.as_ref().unwrap();
                        let exp_proof = expected_proofs[i].opt_bytes.0.as_ref().unwrap();
                        let cell_start = i * 2048;
                        let proof_start = i * 48;
                        assert_eq!(
                            &cells_bytes[cell_start..cell_start + 2048],
                            &exp_cell[..],
                            "recovered cell {} mismatch for {}",
                            i,
                            test_name
                        );
                        assert_eq!(
                            &proofs_bytes[proof_start..proof_start + 48],
                            &exp_proof[..],
                            "recovered proof {} mismatch for {}",
                            i,
                            test_name
                        );
                    }
                    println!("{tv}=> SUCCESS");
                }
                Err(status) => {
                    assert!(test.output.is_none());
                    println!("{tv}=> SUCCESS - expected failure {:?}", status);
                }
            }
        }
    }
}

// ============================================================================
// Unit tests for error paths (not covered by test vectors)
// ============================================================================

#[test]
fn t_verify_cell_kzg_proof_batch_length_mismatch() {
    // FIX-5 (COV-B-003): Directly test the Rust-level length mismatch error.
    // Test vectors with mismatched lengths are filtered by the harness,
    // so the Rust-level Err(cttEthKzg_InputsLengthsMismatch) was never hit.
    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let commitments = vec![[0u8; 48]];
    let cell_indices = vec![0u64, 1u64]; // different length
    let cells = vec![[0u8; 2048]];
    let proofs = vec![[0u8; 48]];
    let sec = [0u8; 32];

    let result = ctx.verify_cell_kzg_proof_batch(
        &commitments,
        &cell_indices,
        &cells,
        &proofs,
        &sec,
    );

    assert_eq!(
        result,
        Err(ctt_eth_kzg_status::cttEthKzg_InputsLengthsMismatch)
    );
}

#[test]
fn t_recover_cells_and_kzg_proofs_length_mismatch() {
    // FIX-5 (COV-B-003): Directly test the Rust-level length mismatch error
    // for recover_cells_and_kzg_proofs.
    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let cells = vec![[0u8; 2048]];
    let cell_indices = vec![0u64, 1u64]; // different length

    let result = ctx.recover_cells_and_kzg_proofs(&cells, &cell_indices);

    assert_eq!(
        result,
        Err(ctt_eth_kzg_status::cttEthKzg_InputsLengthsMismatch)
    );
}

#[test]
fn t_recover_cells_and_kzg_proofs_cell_indices_not_ascending() {
    // Verify that non-ascending cell indices are rejected.
    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    // 64 cells (minimum for recovery) with descending indices [64, 63, ..., 1]
    let cells = vec![[0u8; 2048]; 64];
    let cell_indices: Vec<u64> = (1..=64).rev().collect();

    let result = ctx.recover_cells_and_kzg_proofs(&cells, &cell_indices);

    assert_eq!(
        result,
        Err(ctt_eth_kzg_status::cttEthKzg_CellIndicesNotAscending)
    );
}
