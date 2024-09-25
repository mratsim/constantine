//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_ethereum_evm_precompiles::*;
use constantine_sys::ctt_evm_status;

use std::fs;

use hex;
use serde::Deserialize;
use serde_json;

// Rust does not support concatenating
// compile-time &str ¯\_(ツ)_/¯, so we need to use macros, C-style.

macro_rules! test_dir {
    () => {
        "../../tests/protocol_ethereum_evm_precompiles/"
    };
}

const MODEXP_TESTS: &str = concat!(test_dir!(), "modexp.json");
const MODEXP_EIP2565_TESTS: &str = concat!(test_dir!(), "modexp_eip2565.json");

const BN256ADD_TESTS: &str = concat!(test_dir!(), "bn256Add.json");
const BN256SCALARMUL_TESTS: &str = concat!(test_dir!(), "bn256ScalarMul.json");
const BN256PAIRING_TESTS: &str = concat!(test_dir!(), "bn256Pairing.json");

const ADD_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/add_G1_bls.json");
const FAIL_ADD_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/fail-add_G1_bls.json");
const ADD_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/add_G2_bls.json");
const FAIL_ADD_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/fail-add_G2_bls.json");

const MUL_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/mul_G1_bls.json");
const FAIL_MUL_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/fail-mul_G1_bls.json");
const MUL_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/mul_G2_bls.json");
const FAIL_MUL_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/fail-mul_G2_bls.json");

const MULTIEXP_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/multiexp_G1_bls.json");
const FAIL_MULTIEXP_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/fail-multiexp_G1_bls.json");
const MULTIEXP_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/multiexp_G2_bls.json");
const FAIL_MULTIEXP_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/fail-multiexp_G2_bls.json");

const PAIRING_CHECK_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/pairing_check_bls.json");
const FAIL_PAIRING_CHECK_BLS_TESTS: &str =
    concat!(test_dir!(), "eip-2537/fail-pairing_check_bls.json");

const MAP_FP_TO_G1_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/map_fp_to_G1_bls.json");
const FAIL_MAP_FP_TO_G1_BLS_TESTS: &str =
    concat!(test_dir!(), "eip-2537/fail-map_fp_to_G1_bls.json");
const MAP_FP2_TO_G2_BLS_TESTS: &str = concat!(test_dir!(), "eip-2537/map_fp2_to_G2_bls.json");
const FAIL_MAP_FP2_TO_G2_BLS_TESTS: &str =
    concat!(test_dir!(), "eip-2537/fail-map_fp2_to_G2_bls.json");

type HexString = String;

#[allow(dead_code, non_snake_case)]
#[derive(Deserialize, Debug)]
struct PrecompileTest {
    Input: HexString,
    #[serde(default)]
    Expected: Option<HexString>,
    #[serde(default)]
    ExpectedError: Option<String>,
    Name: String,
    #[serde(default)]
    Gas: i64,
    #[serde(default)]
    NoBenchmark: bool,
}

fn from_hex(hex: HexString) -> Option<Vec<u8>> {
    // data does not always have `0x` prefix in JSON files!
    // Check for the '0x' prefix
    let href: &[u8] = hex.as_ref();
    let href = if href.starts_with(b"0x") {
        &href[2..]
    } else {
        href
    };
    // TODO: why cannot use `with_capacity`?
    let mut result = vec![0u8; href.len() / 2];
    match hex::decode_to_slice(href, result.as_mut_slice() as &mut [u8]) {
        Ok(_) => Some(result),
        Err(_) => None,
    }
}

fn t_generate<T, F>(test_name: String, func: F)
where
    T: IntoIterator<Item = u8>,
    F: Fn(&[u8]) -> Result<T, ctt_evm_status>,
{
    type TestVectors = Vec<PrecompileTest>;

    let unparsed = fs::read_to_string(&test_name).unwrap();
    let vectors: TestVectors = serde_json::from_str(&unparsed).expect(&format!(
        "Formatting should be consistent for file \"{}\"",
        &test_name
    ));

    for vector in vectors {
        println!("Running test case: {}", vector.Name);

        let input = vector.Input;
        let expected = vector.Expected;

        let input_bytes =
            from_hex(input).expect("Test failed; input bytes could not be unmarshaled.");
        // Call the test function
        let result = func(&input_bytes);
        match result {
            Ok(r) => {
                assert!(expected.is_some());
                let expected_bytes = from_hex(expected.unwrap());
                assert!(r.into_iter().collect::<Vec<u8>>() == expected_bytes.unwrap());
            }
            Err(_) => {
                // in case of error there must not be an `expected` field
                assert!(expected.is_none());
                let expected_error = vector.ExpectedError;
                assert!(expected_error.is_some());
            }
        };
    }
}

#[test]
fn t_modexp() {
    let test_name = MODEXP_TESTS.to_string();
    t_generate(test_name, evm_modexp);
}

#[test]
fn t_modexp_eip2565_tests() {
    let test_name = MODEXP_EIP2565_TESTS.to_string();
    t_generate(test_name, evm_modexp);
}

#[test]
fn t_bn256add_tests() {
    let test_name = BN256ADD_TESTS.to_string();
    t_generate(test_name, evm_bn254_g1add);
}
#[test]
fn t_bn256scalarmul_tests() {
    let test_name = BN256SCALARMUL_TESTS.to_string();
    t_generate(test_name, evm_bn254_g1mul);
}

#[test]
fn t_bn256pairing_tests() {
    let test_name = BN256PAIRING_TESTS.to_string();
    t_generate(test_name, evm_bn254_ec_pairing_check);
}

#[test]
fn t_add_g1_bls_tests() {
    let test_name = ADD_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g1add);
}
#[test]
fn t_fail_add_g1_bls_tests() {
    let test_name = FAIL_ADD_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g1add);
}
#[test]
fn t_add_g2_bls_tests() {
    let test_name = ADD_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g2add);
}
#[test]
fn t_fail_add_g2_bls_tests() {
    let test_name = FAIL_ADD_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g2add);
}

#[test]
fn t_mul_g1_bls_tests() {
    let test_name = MUL_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g1mul);
}
#[test]
fn t_fail_mul_g1_bls_tests() {
    let test_name = FAIL_MUL_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g1mul);
}
#[test]
fn t_mul_g2_bls_tests() {
    let test_name = MUL_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g2mul);
}
#[test]
fn t_fail_mul_g2_bls_tests() {
    let test_name = FAIL_MUL_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g2mul);
}

#[test]
fn t_multiexp_g1_bls_tests() {
    let test_name = MULTIEXP_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g1msm);
}
#[test]
fn t_fail_multiexp_g1_bls_tests() {
    let test_name = FAIL_MULTIEXP_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g1msm);
}
#[test]
fn t_multiexp_g2_bls_tests() {
    let test_name = MULTIEXP_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g2msm);
}
#[test]
fn t_fail_multiexp_g2_bls_tests() {
    let test_name = FAIL_MULTIEXP_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_g2msm);
}

#[test]
fn t_pairing_check_bls_tests() {
    let test_name = PAIRING_CHECK_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_pairing_check);
}
#[test]
fn t_fail_pairing_check_bls_tests() {
    let test_name = FAIL_PAIRING_CHECK_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_pairing_check);
}

#[test]
fn t_map_fp_to_g1_bls_tests() {
    let test_name = MAP_FP_TO_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_map_fp_to_g1);
}
#[test]
fn t_fail_map_fp_to_g1_bls_tests() {
    let test_name = FAIL_MAP_FP_TO_G1_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_map_fp_to_g1);
}
#[test]
fn t_map_fp2_to_g2_bls_tests() {
    let test_name = MAP_FP2_TO_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_map_fp2_to_g2);
}
#[test]
fn t_fail_map_fp2_to_g2_bls_tests() {
    let test_name = FAIL_MAP_FP2_TO_G2_BLS_TESTS.to_string();
    t_generate(test_name, evm_bls12381_map_fp2_to_g2);
}
