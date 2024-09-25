//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::{hardware, Threadpool};
use constantine_ethereum_bls_sig::*;

use std::fs;
use std::path::PathBuf;

use glob::glob;
use hex;
use hex::FromHex;
use serde::{Deserialize, Deserializer};
use serde_json;

// Rust does not support concatenating
// compile-time &str ¯\_(ツ)_/¯, so we need to use macros, C-style.

macro_rules! test_dir {
    () => {
        "../../tests/protocol_blssig_pop_on_bls12381_g2_test_vectors_v0.1.1/"
    };
}

const AGGREGATE_VERIFY_TESTS: &str = concat!(test_dir!(), "aggregate_verify/*");
// const AGGREGATE_TESTS: &str = concat!(test_dir!(), "aggregate/*");
const DESERIALIZATION_G1_TESTS: &str = concat!(test_dir!(), "deserialization_G1/*");
const BATCH_VERIFY_TESTS: &str = concat!(test_dir!(), "batch_verify/*");
const FAST_AGGREGATE_VERIFY_TESTS: &str = concat!(test_dir!(), "fast_aggregate_verify/*");
// const HASH_TO_G2_TESTS: &str = concat!(test_dir!(), "hash_to_G2/*");
const DESERIALIZATION_G2_TESTS: &str = concat!(test_dir!(), "deserialization_G2/*");
const VERIFY_TESTS: &str = concat!(test_dir!(), "verify/*");
const SIGN_TESTS: &str = concat!(test_dir!(), "sign/*");

#[test]
fn t_example_bls_sig() {
    let raw_sec_str = "Security pb becomes key mgmt pb!".as_bytes();
    let mut raw_sec = [0u8; 32];
    raw_sec.copy_from_slice(raw_sec_str);

    let result = deserialize_seckey(&raw_sec);
    println!("deserialized: Status: {} ", result.is_ok());
    let sec_key = result.unwrap();

    let pub_key = derive_pubkey(sec_key);

    let msg = sha256_hash("Mr F was here".as_bytes(), false);
    println!("msg: {:?}", msg);

    // verify
    let sig = sign(sec_key, &msg);
    let result = verify(pub_key, &msg, sig);
    match result {
        Ok(_v) => println!("Verified correctly"),
        Err(e) => {
            println!("Failed to verify: {}", e);
            assert!(false, "Failure")
        }
    }

    // batch verify
    let pkeys = [pub_key, pub_key, pub_key];
    let msgs = vec![msg.to_vec(), msg.to_vec(), msg.to_vec()];
    let sigs = [sig, sig, sig];
    // leave zero
    let srb = [0u8; 32];
    let result = batch_verify(&pkeys, &msgs, &sigs, &srb);
    match result {
        Ok(_v) => println!("Batch verified correctly"),
        Err(e) => {
            println!("Failed to batch verify {}", e);
            assert!(false, "Failure");
        }
    }
}

#[derive(Debug)]
struct OptRawBytes<const N: usize>(Option<Box<[u8; N]>>);

impl<const N: usize> hex::FromHex for OptRawBytes<N> {
    type Error = hex::FromHexError;
    fn from_hex<T: AsRef<[u8]>>(hex: T) -> Result<Self, Self::Error> {
        let mut res = Box::new([0_; N]);
        // data does not always have `0x` prefix in JSON files!
        // Check for the '0x' prefix
        let href = hex.as_ref();
        let href = if href.starts_with(b"0x") {
            &href[2..]
        } else {
            href
        };
        match hex::decode_to_slice(href, &mut *res as &mut [u8]) {
            Ok(_) => Ok(OptRawBytes::<N> { 0: Some(res) }),
            Err(_) => Ok(OptRawBytes::<N> { 0: None }),
        }
    }
}

// Need a cusom deserializer for the case where JSON might have `null` fields (`sign` test case)
impl<'de, const N: usize> Deserialize<'de> for OptRawBytes<N> {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let opt_hex: Option<String> = Option::deserialize(deserializer)?;
        match opt_hex {
            Some(hex_str) => OptRawBytes::from_hex(hex_str).map_err(serde::de::Error::custom),
            None => Ok(OptRawBytes::<N>(Some(Box::new([0u8; N])))), // Handle `null` by returning an empty array
        }
    }
}

#[derive(Deserialize, Debug)]
#[serde(transparent)]
struct OptBytes<const N: usize> {
    opt_bytes: OptRawBytes<N>, // use custom deserializer to handle `null`
}

impl<const N: usize> std::fmt::Display for OptBytes<N> {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match &self.opt_bytes.0 {
            Some(bytes) => {
                for byte in bytes.iter() {
                    write!(f, "{:02x}", byte)?;
                }
                Ok(())
            }
            None => write!(f, ""),
        }
    }
}

#[test]
fn t_deserialize_g1() {
    #[derive(Deserialize)]
    struct Input {
        pubkey: OptBytes<48>,
    }
    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: bool,
    }

    let test_files: Vec<PathBuf> = glob(DESERIALIZATION_G1_TESTS)
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
        println!("    Test vector: {:<88}", test_name);
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let Some(inp) = test.input.pubkey.opt_bytes.0 else {
            assert!(!test.output);
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        let pub_key = deserialize_pubkey_compressed(inp.as_ref());
        match pub_key {
            Ok(v_pub) => {
                let s = serialize_pubkey_compressed(&v_pub);
                match s {
                    // Serialized key must match our initial input
                    Ok(v) => assert!(v == *inp),
                    Err(_e) => {
                        assert!(false); // should not happen!
                    }
                }
            }
            Err(_e) => {
                // In this case test must be expected to fail
                assert!(!test.output);
            }
        }
    }
}

#[test]
fn t_deserialize_g2() {
    #[derive(Deserialize, Debug)]
    struct Input {
        signature: OptBytes<96>,
    }
    #[derive(Deserialize, Debug)]
    struct Test {
        input: Input,
        output: bool,
    }

    let test_files: Vec<PathBuf> = glob(DESERIALIZATION_G2_TESTS)
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
        println!("    Test vector: {:<88}", test_name);

        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let Some(inp) = test.input.signature.opt_bytes.0 else {
            assert!(!test.output);
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        let sig = deserialize_signature_compressed(inp.as_ref());
        match sig {
            Ok(v_sig) => {
                let s = serialize_signature_compressed(&v_sig);
                match s {
                    // Serialized key must match our initial input
                    Ok(v) => assert!(v == *inp),
                    Err(_e) => {
                        assert!(false) // should not happen
                    }
                }
            }
            Err(_e) => {
                // In this case test must be expected to fail
                assert!(!test.output);
            }
        }
    }
}

#[test]
fn t_sign() {
    #[derive(Deserialize, Debug)]
    struct Input {
        privkey: OptBytes<32>,
        message: OptBytes<32>,
    }
    #[derive(Deserialize, Debug)]
    struct Test {
        input: Input,
        output: OptBytes<96>,
    }

    let test_files: Vec<PathBuf> = glob(SIGN_TESTS).unwrap().map(Result::unwrap).collect();
    assert!(!test_files.is_empty());
    for test_file in test_files {
        let test_name = test_file
            .parent()
            .unwrap()
            .file_name()
            .unwrap()
            .to_str()
            .unwrap();
        println!("    Test file: {:<88}", test_file.display());
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let Some(inp) = test.input.privkey.opt_bytes.0 else {
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        let skey = deserialize_seckey(inp.as_ref());
        match skey {
            Err(_e) => {
                // empty output due to `null` JSON value
                let (Some(tout), Some(_)) =
                    (test.output.opt_bytes.0, test.input.message.opt_bytes.0)
                else {
                    assert!(false);
                    continue;
                };
                assert!(*tout == [0u8; 96]);
                // Note: We cannot sign a message with `skey` in case of error
            }
            Ok(v_sec) => {
                let (Some(tout), Some(tmsg)) =
                    (test.output.opt_bytes.0, test.input.message.opt_bytes.0)
                else {
                    assert!(false);
                    continue;
                };
                let sig = sign(v_sec, &*tmsg);
                // deserialize output for extra codec testing
                let output = deserialize_signature_compressed(tout.as_ref());
                match output {
                    Ok(_v) => (),
                    Err(_v) => assert!(*tout == [0u8; 96]),
                }
                let sigs_match = signatures_are_equal(sig, output.unwrap());
                if !sigs_match {
                    let sig_bytes = serialize_signature_compressed(&sig);
                    let round_trip = serialize_signature_compressed(&output.unwrap());
                    println!(
                        "\nResult signature differs from expected \n
                                    computed:  0x{:#?} (, {}, )\n
                                    roundtrip: 0x{:#?} (, {}, \n
                                    expected:  0x{:#?} ",
                        sig_bytes.unwrap(),
                        sig_bytes.unwrap_err(),
                        round_trip.unwrap(),
                        round_trip.unwrap_err(),
                        tout
                    );
                    assert!(false);
                    continue;
                }
                // serialize result for extra codec testing
                let sig_bytes = serialize_signature_compressed(&sig);
                match sig_bytes {
                    Ok(_v) => (),
                    Err(_e) => assert!(*tout == [0u8; 96]),
                }
                assert!(sig_bytes.unwrap() == *tout);
            }
        }
    }
}

#[test]
fn t_verify() {
    #[derive(Deserialize, Debug)]
    struct Input {
        pubkey: OptBytes<48>,
        message: OptBytes<32>,
        signature: OptBytes<96>,
    }
    #[derive(Deserialize, Debug)]
    struct Test {
        input: Input,
        output: bool,
    }

    let test_files: Vec<PathBuf> = glob(VERIFY_TESTS).unwrap().map(Result::unwrap).collect();
    assert!(!test_files.is_empty());
    for test_file in test_files {
        let test_name = test_file
            .parent()
            .unwrap()
            .file_name()
            .unwrap()
            .to_str()
            .unwrap();
        println!("    Test file: {:<88}", test_file.display());
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let (Some(tpkey), Some(tmsg), Some(tsig)) = (
            test.input.pubkey.opt_bytes.0,
            test.input.message.opt_bytes.0,
            test.input.signature.opt_bytes.0,
        ) else {
            assert!(!test.output);
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };

        {
            // test checks
            let pkey = deserialize_pubkey_compressed(tpkey.as_ref());
            match pkey {
                Err(_e) => {
                    assert!(!test.output);
                    continue;
                } // expected test failure
                Ok(_v) => (),
            };

            let sig = deserialize_signature_compressed(tsig.as_ref());
            match sig {
                Err(_e) => {
                    assert!(!test.output);
                    continue;
                } // expected test failure
                Ok(_v) => (), // signature might be valid, even if test fails!
            };

            let status = verify(pkey.unwrap(), &*tmsg, sig.unwrap());
            match status {
                Err(_e) => assert!(!test.output), // expected test failure
                Ok(v) => {
                    if !test.output {
                        // Test failure!
                        println!(
                            "Verification differs from expected \n
				  valid sig? {}\n
				  expected: {}",
                            v, test.output
                        );
                        assert!(test.output == true); // will fail
                    } else {
                        let output = serialize_pubkey_compressed(&pkey.unwrap());
                        match output {
                            Ok(v_o) => assert!(v_o == *tpkey),
                            Err(_e) => assert!(test.output == false), // TODO THINK ABOUT better just assert!(false);?
                        }
                        let output = serialize_signature_compressed(&sig.unwrap());
                        match output {
                            Ok(v_o) => assert!(v_o == *tsig),
                            Err(_e) => assert!(test.output == false), // TODO THINK ABOUT better just assert!(false);?
                        }
                    }
                }
            };
        }
    }
}

#[test]
fn t_fast_aggregate_verify() {
    #[derive(Deserialize)]
    struct Input {
        pubkeys: Vec<OptBytes<48>>,
        message: OptBytes<32>,
        signature: OptBytes<96>,
    }
    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: bool,
    }

    let test_files: Vec<PathBuf> = glob(FAST_AGGREGATE_VERIFY_TESTS)
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
        println!("    Test file: {:<88}", test_file.display());
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let (Some(tmsg), Some(tsig)) = (
            test.input.message.opt_bytes.0,
            test.input.signature.opt_bytes.0,
        ) else {
            assert!(!test.output);
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };
        let mut pks = Vec::new();
        for raw_pk in test.input.pubkeys.iter() {
            let Some(ref tpk) = raw_pk.opt_bytes.0 else {
                assert!(!test.output);
                println!("{}=> SUCCESS - expected deserialization failure", tv);
                continue;
            };
            let pk = deserialize_pubkey_compressed(tpk);
            match pk {
                Ok(_v) => pks.push(_v),
                Err(_e) => {
                    assert!(test.output == false);
                    continue;
                }
            }
        }

        let sig = deserialize_signature_compressed(tsig.as_ref());
        match sig {
            Err(_e) => {
                assert!(test.output == false);
                continue;
            } // expected test failure
            Ok(_v) => (),
        };

        let status = fast_aggregate_verify(&pks, &*tmsg, &sig.unwrap());
        match status {
            Err(_e) => assert!(!test.output), // expected test failure
            Ok(v) => {
                if v != test.output {
                    println!(
                        "Verification differs from expected \n
			      valid sig? {}\n
 			      expected: {}",
                        v, test.output
                    );
                }
                assert!(v == test.output);
            }
        }
    }
}

#[test]
fn t_aggregate_verify() {
    #[derive(Deserialize)]
    struct Input {
        pubkeys: Vec<OptBytes<48>>,
        messages: Vec<OptBytes<32>>,
        signature: OptBytes<96>,
    }
    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: bool,
    }

    let test_files: Vec<PathBuf> = glob(AGGREGATE_VERIFY_TESTS)
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
        println!("    Test file: {:<88}", test_file.display());
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let Some(tsig) = test.input.signature.opt_bytes.0 else {
            assert!(!test.output);
            println!("{}=> SUCCESS - expected deserialization failure", tv);
            continue;
        };
        let mut pks = Vec::new();
        for raw_pk in test.input.pubkeys.iter() {
            let Some(ref tpk) = raw_pk.opt_bytes.0 else {
                assert!(!test.output);
                println!("{}=> SUCCESS - expected deserialization failure", tv);
                continue;
            };
            let pk = deserialize_pubkey_compressed(tpk);
            match pk {
                Ok(v) => pks.push(v),
                Err(_e) => assert!(!test.output),
            }
        }
        let mut msgs = Vec::new();
        for raw_msg in test.input.messages.iter() {
            let Some(ref msg) = raw_msg.opt_bytes.0 else {
                assert!(!test.output);
                println!("{}=> SUCCESS - expected deserialization failure", tv);
                continue;
            };
            msgs.push((*msg).to_vec());
        }
        let sig = deserialize_signature_compressed(tsig.as_ref());
        match sig {
            Err(_e) => {
                assert!(!test.output);
                continue;
            } // expected test failure
            Ok(_v) => (),
        };
        let status = aggregate_verify(&pks, &msgs, &sig.unwrap());
        match status {
            Err(_e) => assert!(!test.output), // expected test failure
            Ok(v) => {
                if v != test.output {
                    println!(
                        "Verification differs from expected \n
			      valid sig? {}\n
 			      expected: {}",
                        v, test.output
                    );
                }
                assert!(v == test.output);
            }
        }
    }
}

#[test]
fn t_batch_verify() {
    #[derive(Deserialize)]
    struct Input {
        pubkeys: Vec<OptBytes<48>>,
        messages: Vec<OptBytes<32>>,
        signatures: Vec<OptBytes<96>>,
    }
    #[derive(Deserialize)]
    struct Test {
        input: Input,
        output: bool,
    }

    let tp = Threadpool::new(hardware::get_num_threads_os());

    let test_files: Vec<PathBuf> = glob(BATCH_VERIFY_TESTS)
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
        println!("    Test file: {:<88}", test_file.display());
        let tv = format!("    Test vector: {:<88}", test_name);
        let unparsed = fs::read_to_string(&test_file).unwrap();
        let test: Test = serde_json::from_str(&unparsed).expect(&format!(
            "Formatting should be consistent for file \"{}\"",
            &test_name
        ));

        let mut pks = Vec::new();
        for raw_pk in test.input.pubkeys.iter() {
            let Some(ref tpk) = raw_pk.opt_bytes.0 else {
                assert!(!test.output);
                println!("{}=> SUCCESS - expected deserialization failure", tv);
                continue;
            };
            let pk = deserialize_pubkey_compressed(tpk);
            match pk {
                Ok(v) => pks.push(v),
                Err(_e) => assert!(test.output == false),
            }
        }
        let mut sigs = Vec::new();
        for raw_sig in test.input.signatures.iter() {
            let Some(ref tsig) = raw_sig.opt_bytes.0 else {
                assert!(!test.output);
                println!("{}=> SUCCESS - expected deserialization failure", tv);
                continue;
            };
            let sig = deserialize_signature_compressed(tsig);
            match sig {
                Ok(v) => sigs.push(v),
                Err(_e) => assert!(test.output == false),
            }
        }
        let mut msgs = Vec::new();
        for raw_msg in test.input.messages.iter() {
            let Some(ref msg) = raw_msg.opt_bytes.0 else {
                assert!(!test.output);
                println!("{}=> SUCCESS - expected deserialization failure", tv);
                continue;
            };
            msgs.push((*msg).to_vec());
        }
        let random_bytes = sha256_hash("totally non-secure source of entropy".as_bytes(), false);

        // serial
        let status = batch_verify(&pks, &msgs, &sigs, &random_bytes);
        match status {
            Err(_e) => assert!(!test.output), // expected test failure
            Ok(v) => {
                if v != test.output {
                    println!(
                        "Verification differs from expected \n
			      valid sig? {}\n
 			      expected: {}",
                        v, test.output
                    );
                }
                assert!(v == test.output);
            }
        }

        // parallel
        let status = batch_verify_parallel(&tp, &pks, &msgs, &sigs, &random_bytes);
        match status {
            Err(_e) => assert!(!test.output), // expected test failure
            Ok(v) => {
                if v != test.output {
                    println!(
                        "Verification differs from expected \n
			      valid sig? {}\n
 			      expected: {}",
                        v, test.output
                    );
                }
                assert!(v == test.output);
            }
        }
    }
}
