//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::{csprngs, hardware, Threadpool};
use constantine_ethereum_kzg::EthKzgContext;

use std::fs;
use std::path::{Path, PathBuf};

use glob::glob;
use hex;
use serde::Deserialize;
use serde_yaml;

#[test]
fn t_smoke_load_trusted_setup() {
    let _ctx = EthKzgContext::load_trusted_setup(Path::new(
        "../../constantine/commitments_setups/trusted_setup_ethereum_kzg4844_reference.dat",
    ))
    .expect("Trusted setup should be loaded without error.");
}

// Official Ethereum test vectors
// -----------------------------------------------------------

// Rust does not support concatenating
// compile-time &str ¯\_(ツ)_/¯, so we need to use macros, C-style.

macro_rules! test_dir {
    () => {
        "../../tests/protocol_ethereum_eip4844_deneb_kzg/"
    };
}

const BLOB_TO_KZG_COMMITMENT_TESTS: &str = concat!(test_dir!(), "blob_to_kzg_commitment/*/*/*");
const COMPUTE_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "compute_kzg_proof/*/*/*");
const COMPUTE_BLOB_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "compute_blob_kzg_proof/*/*/*");
const VERIFY_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "verify_kzg_proof/*/*/*");
const VERIFY_BLOB_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "verify_blob_kzg_proof/*/*/*");
const VERIFY_BLOB_KZG_PROOF_BATCH_TESTS: &str =
    concat!(test_dir!(), "verify_blob_kzg_proof_batch/*/*/*");

const SRS_PATH: &str =
    "../../constantine/commitments_setups/trusted_setup_ethereum_kzg4844_reference.dat";

struct OptRawBytes<const N: usize>(Option<Box<[u8; N]>>);

impl<const N: usize> hex::FromHex for OptRawBytes<N> {
    type Error = hex::FromHexError;
    fn from_hex<T: AsRef<[u8]>>(hex: T) -> Result<Self, Self::Error> {
        let mut res = Box::new([0_; N]);
        match hex::decode_to_slice(&hex.as_ref()[2..], &mut *res as &mut [u8]) {
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

#[test]
fn t_blob_to_kzg_commitment() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: OptBytes<48>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let test_files: Vec<PathBuf> = glob(BLOB_TO_KZG_COMMITMENT_TESTS)
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

        let Some(blob) = test.input.blob.opt_bytes.0 else {
            assert!(test.output.opt_bytes.0.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.blob_to_kzg_commitment(&*blob) {
            Ok(commitment) => {
                assert_eq!(commitment, *test.output.opt_bytes.0.unwrap());
                println!("{}=> SUCCESS", tv);
            }
            Err(status) => {
                assert!(test.output.opt_bytes.0.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_compute_kzg_proof() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
        z: OptBytes<32>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<(OptBytes<48>, OptBytes<32>)>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let test_files: Vec<PathBuf> = glob(COMPUTE_KZG_PROOF_TESTS)
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

        let (Some(blob), Some(opening_challenge)) = (test.input.blob.opt_bytes.0, test.input.z.opt_bytes.0)
        else {
            assert!(test.output.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.compute_kzg_proof(&*blob, &*opening_challenge) {
            Ok((proof, eval)) => {
                let (true_proof, true_eval) = test.output.unwrap();
                assert_eq!(proof, *true_proof.opt_bytes.0.unwrap());
                assert_eq!(eval, *true_eval.opt_bytes.0.unwrap());
                println!("{}=> SUCCESS", tv);
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_verify_kzg_proof() {
    #[derive(Deserialize)]
    struct Input {
        commitment: OptBytes<48>,
        z: OptBytes<32>,
        y: OptBytes<32>,
        proof: OptBytes<48>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<bool>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let test_files: Vec<PathBuf> = glob(VERIFY_KZG_PROOF_TESTS)
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

        let (Some(commitment), Some(z), Some(y), Some(proof)) = (
            &test.input.commitment.opt_bytes.0,
            &test.input.z.opt_bytes.0,
            &test.input.y.opt_bytes.0,
            &test.input.proof.opt_bytes.0,
        ) else {
            assert!(test.output.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.verify_kzg_proof(&*commitment, &*z, &*y, &*proof) {
            Ok(valid) => {
                assert_eq!(valid, test.output.unwrap());
                if valid {
                    println!("{}=> SUCCESS - successfully verified valid proof", tv);
                } else {
                    println!("{}=> SUCCESS - successfully rejected invalid proof", tv);
                }
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_compute_blob_kzg_proof() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
        commitment: OptBytes<48>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: OptBytes<48>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let test_files: Vec<PathBuf> = glob(COMPUTE_BLOB_KZG_PROOF_TESTS)
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

        let (Some(blob), Some(commitment)) = (
            test.input.blob.opt_bytes.0,
            test.input.commitment.opt_bytes.0,
        ) else {
            assert!(test.output.opt_bytes.0.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.compute_blob_kzg_proof(&*blob, &*commitment) {
            Ok(proof) => {
                assert_eq!(proof, *test.output.opt_bytes.0.unwrap());
                println!("{}=> SUCCESS", tv);
            }
            Err(status) => {
                assert!(test.output.opt_bytes.0.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_verify_blob_kzg_proof() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
        commitment: OptBytes<48>,
        proof: OptBytes<48>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<bool>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let test_files: Vec<PathBuf> = glob(VERIFY_BLOB_KZG_PROOF_TESTS)
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

        let (Some(blob), Some(commitment), Some(proof)) = (
            test.input.blob.opt_bytes.0,
            test.input.commitment.opt_bytes.0,
            test.input.proof.opt_bytes.0,
        ) else {
            assert!(test.output.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.verify_blob_kzg_proof(&*blob, &*commitment, &*proof) {
            Ok(valid) => {
                assert_eq!(valid, test.output.unwrap());
                if valid {
                    println!("{}=> SUCCESS - successfully verified valid proof", tv);
                } else {
                    println!("{}=> SUCCESS - successfully rejected invalid proof", tv);
                }
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_verify_blob_kzg_proof_batch() {
    #[derive(Deserialize)]
    struct Input {
        blobs: Vec<OptBytes<131072>>,
        commitments: Vec<OptBytes<48>>,
        proofs: Vec<OptBytes<48>>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<bool>,
    }

    let ctx = EthKzgContext::load_trusted_setup(Path::new(SRS_PATH))
        .expect("Trusted setup should be loaded without error.");

    let mut secure_random_bytes = [0u8; 32];
    csprngs::sysrand(secure_random_bytes.as_mut_slice());
    assert_ne!(secure_random_bytes, [0u8; 32]);

    let test_files: Vec<PathBuf> = glob(VERIFY_BLOB_KZG_PROOF_BATCH_TESTS)
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

        let blobs: Vec<_> = test
            .input
            .blobs
            .into_iter()
            .filter_map(|v| v.opt_bytes.0) // deserialization failure will lead to length mismatch
            .map(|v| *v)
            .collect();
        let commitments: Vec<_> = test
            .input
            .commitments
            .into_iter()
            .filter_map(|v| v.opt_bytes.0) // deserialization failure will lead to length mismatch
            .map(|v| *v)
            .collect();
        let proofs: Vec<_> = test
            .input
            .proofs
            .into_iter()
            .filter_map(|v| v.opt_bytes.0) // deserialization failure will lead to length mismatch
            .map(|v| *v)
            .collect();

        match ctx.verify_blob_kzg_proof_batch(&blobs, &commitments, &proofs, &secure_random_bytes) {
            Ok(valid) => {
                assert_eq!(valid, test.output.unwrap());
                if valid {
                    println!("{}=> SUCCESS - successfully verified valid proof", tv);
                } else {
                    println!("{}=> SUCCESS - successfully rejected invalid proof", tv);
                }
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

// Parallel tests
// -----------------------------------------------------------

#[test]
fn t_blob_to_kzg_commitment_parallel() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: OptBytes<48>,
    }

    let tp = Threadpool::new(hardware::get_num_threads_os());
    let ctx = EthKzgContext::builder()
                .load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup loaded successfully")
                .set_threadpool(&tp)
                .build()
                .expect("EthKzgContext initialized successfully");

    let test_files: Vec<PathBuf> = glob(BLOB_TO_KZG_COMMITMENT_TESTS)
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

        let Some(blob) = test.input.blob.opt_bytes.0 else {
            assert!(test.output.opt_bytes.0.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.blob_to_kzg_commitment_parallel(&*blob) {
            Ok(commitment) => {
                assert_eq!(commitment, *test.output.opt_bytes.0.unwrap());
                println!("{}=> SUCCESS", tv);
            }
            Err(status) => {
                assert!(test.output.opt_bytes.0.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_compute_kzg_proof_parallel() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
        z: OptBytes<32>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<(OptBytes<48>, OptBytes<32>)>,
    }

    let tp = Threadpool::new(hardware::get_num_threads_os());
    let ctx = EthKzgContext::builder()
                .load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup loaded successfully")
                .set_threadpool(&tp)
                .build()
                .expect("EthKzgContext initialized successfully");

    let test_files: Vec<PathBuf> = glob(COMPUTE_KZG_PROOF_TESTS)
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

        let (Some(blob), Some(opening_challenge)) = (test.input.blob.opt_bytes.0, test.input.z.opt_bytes.0)
        else {
            assert!(test.output.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.compute_kzg_proof_parallel(&*blob, &*opening_challenge) {
            Ok((proof, eval)) => {
                let (true_proof, true_eval) = test.output.unwrap();
                assert_eq!(proof, *true_proof.opt_bytes.0.unwrap());
                assert_eq!(eval, *true_eval.opt_bytes.0.unwrap());
                println!("{}=> SUCCESS", tv);
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_compute_blob_kzg_proof_parallel() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
        commitment: OptBytes<48>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: OptBytes<48>,
    }

    let tp = Threadpool::new(hardware::get_num_threads_os());
    let ctx = EthKzgContext::builder()
                .load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup loaded successfully")
                .set_threadpool(&tp)
                .build()
                .expect("EthKzgContext initialized successfully");

    let test_files: Vec<PathBuf> = glob(COMPUTE_BLOB_KZG_PROOF_TESTS)
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

        let (Some(blob), Some(commitment)) = (
            test.input.blob.opt_bytes.0,
            test.input.commitment.opt_bytes.0,
        ) else {
            assert!(test.output.opt_bytes.0.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.compute_blob_kzg_proof_parallel(&*blob, &*commitment) {
            Ok(proof) => {
                assert_eq!(proof, *test.output.opt_bytes.0.unwrap());
                println!("{}=> SUCCESS", tv);
            }
            Err(status) => {
                assert!(test.output.opt_bytes.0.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_verify_blob_kzg_proof_parallel() {
    #[derive(Deserialize)]
    struct Input {
        blob: OptBytes<131072>,
        commitment: OptBytes<48>,
        proof: OptBytes<48>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<bool>,
    }

    let tp = Threadpool::new(hardware::get_num_threads_os());
    let ctx = EthKzgContext::builder()
                .load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup loaded successfully")
                .set_threadpool(&tp)
                .build()
                .expect("EthKzgContext initialized successfully");

    let test_files: Vec<PathBuf> = glob(VERIFY_BLOB_KZG_PROOF_TESTS)
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

        let (Some(blob), Some(commitment), Some(proof)) = (
            test.input.blob.opt_bytes.0,
            test.input.commitment.opt_bytes.0,
            test.input.proof.opt_bytes.0,
        ) else {
            assert!(test.output.is_none());
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        match ctx.verify_blob_kzg_proof_parallel(&*blob, &*commitment, &*proof) {
            Ok(valid) => {
                assert_eq!(valid, test.output.unwrap());
                if valid {
                    println!("{}=> SUCCESS - successfully verified valid proof", tv);
                } else {
                    println!("{}=> SUCCESS - successfully rejected invalid proof", tv);
                }
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}

#[test]
fn t_verify_blob_kzg_proof_batch_parallel() {
    #[derive(Deserialize)]
    struct Input {
        blobs: Vec<OptBytes<131072>>,
        commitments: Vec<OptBytes<48>>,
        proofs: Vec<OptBytes<48>>,
    }

    #[derive(Deserialize)]
    struct Test {
        input: Input,
        #[serde(default)]
        output: Option<bool>,
    }

    let tp = Threadpool::new(hardware::get_num_threads_os());
    let ctx = EthKzgContext::builder()
                .load_trusted_setup(Path::new(SRS_PATH))
                .expect("Trusted setup loaded successfully")
                .set_threadpool(&tp)
                .build()
                .expect("EthKzgContext initialized successfully");

    let mut secure_random_bytes = [0u8; 32];
    csprngs::sysrand(secure_random_bytes.as_mut_slice());
    assert_ne!(secure_random_bytes, [0u8; 32]);

    let test_files: Vec<PathBuf> = glob(VERIFY_BLOB_KZG_PROOF_BATCH_TESTS)
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

        let blobs: Vec<_> = test
            .input
            .blobs
            .into_iter()
            .filter_map(|v| v.opt_bytes.0) // deserialization failure will lead to length mismatch
            .map(|v| *v)
            .collect();
        let commitments: Vec<_> = test
            .input
            .commitments
            .into_iter()
            .filter_map(|v| v.opt_bytes.0) // deserialization failure will lead to length mismatch
            .map(|v| *v)
            .collect();
        let proofs: Vec<_> = test
            .input
            .proofs
            .into_iter()
            .filter_map(|v| v.opt_bytes.0) // deserialization failure will lead to length mismatch
            .map(|v| *v)
            .collect();

        match ctx.verify_blob_kzg_proof_batch_parallel(
            &blobs,
            &commitments,
            &proofs,
            &secure_random_bytes,
        ) {
            Ok(valid) => {
                assert_eq!(valid, test.output.unwrap());
                if valid {
                    println!("{}=> SUCCESS - successfully verified valid proof", tv);
                } else {
                    println!("{}=> SUCCESS - successfully rejected invalid proof", tv);
                }
            }
            Err(status) => {
                assert!(test.output.is_none());
                println!("{}=> SUCCESS - expected failure {:?}", tv, status);
            }
        }
    }
}
