//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_ethereum_kzg::EthKzgContext;
use std::path::{Path, PathBuf};
use std::fs;
use glob::glob;
use serde::Deserialize;
use serde_yaml;
use hex;

#[test]
fn t_smoke_load_trusted_setup() {
    let _ctx = EthKzgContext::load_trusted_setup(
        Path::new("../../constantine/trusted_setups/trusted_setup_ethereum_kzg4844_reference.dat")
    ).expect("Trusted setup should be loaded without error.");
}

// Official Ethereum test vectors
// -----------------------------------------------------------

// Rust does not support concatenating
// compile-time &str ¯\_(ツ)_/¯, so we need to use macros, C-style.

macro_rules! test_dir {
    () => ( "../../tests/protocol_ethereum_eip4844_deneb_kzg/" )
}

const BLOB_TO_KZG_COMMITMENT_TESTS: &str = concat!(test_dir!(), "blob_to_kzg_commitment/*/*/*");
const COMPUTE_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "compute_kzg_proof/*/*/*");
const COMPUTE_BLOB_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "compute_blob_kzg_proof/*/*/*");
const VERIFY_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "verify_kzg_proof/*/*/*");
const VERIFY_BLOB_KZG_PROOF_TESTS: &str = concat!(test_dir!(), "verify_blob_kzg_proof/*/*/*");
const VERIFY_BLOB_KZG_PROOF_BATCH_TESTS: &str = concat!(test_dir!(), "verify_blob_kzg_proof_batch/*/*/*");

const SRS_PATH: &str = "../../constantine/trusted_setups/trusted_setup_ethereum_kzg4844_reference.dat";

// Rust abysmal support for const generics is extremely annoying
// See:
//   - https://docs.rs/hex/0.4.3/src/hex/lib.rs.html#220
//   - https://docs.rs/serde-hex/0.1.0/src/serde_hex/lib.rs.html#299
//
// And you can't implement external traits like FromHex yourself
// because "only traits defined in the current crate can be implemented for arbitrary types"

struct OptRawBytes<const N: usize>(Option<Box<[u8; N]>>);

// hex still doesn't use const generics
impl<const N: usize> hex::FromHex for OptRawBytes<N> {
    type Error = hex::FromHexError;
    fn from_hex<T: AsRef<[u8]>>(hex: T) -> Result<Self, Self::Error> {
        let mut res = Box::new([0_; N]);
        match hex::decode_to_slice(&hex.as_ref()[2..], &mut *res as &mut [u8]) {
            Ok(_) => Ok(OptRawBytes::<N>{0: Some(res) }),
            Err(_) => Ok(OptRawBytes::<N>{0: None }),
        }
    }
}

#[derive(Deserialize)]
#[serde(transparent)]
struct OptBytes<const N: usize> {
    #[serde(deserialize_with = "hex::serde::deserialize")]
    opt_bytes: OptRawBytes<N>
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

    let ctx = EthKzgContext::load_trusted_setup(
        Path::new(SRS_PATH)
    ).expect("Trusted setup should be loaded without error.");

    let test_files: Vec<PathBuf> = glob(BLOB_TO_KZG_COMMITMENT_TESTS)
        .unwrap()
        .map(Result::unwrap)
        .collect();
    assert!(!test_files.is_empty());

    for test_file in test_files {
        let unparsed = fs::read_to_string(test_file).unwrap();
        let test: Test = serde_yaml::from_str(&unparsed).unwrap();

        let Some(blob) = &test.input.blob.opt_bytes.0 else {
            assert!(test.output.opt_bytes.0.is_none());
            continue;
        };
    };
}
