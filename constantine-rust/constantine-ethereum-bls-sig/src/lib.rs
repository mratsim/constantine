//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::Threadpool;
use constantine_sys::*;

use ::core::mem::MaybeUninit;

// Create type aliases for the C types
pub type EthBlsSecKey = ctt_eth_bls_seckey;
pub type EthBlsPubKey = ctt_eth_bls_pubkey;
pub type EthBlsSignature = ctt_eth_bls_signature;

#[must_use]
pub fn sha256_hash(message: &[u8], clear_memory: bool) -> [u8; 32] {
    let mut result = [0u8; 32];
    unsafe {
        ctt_sha256_hash(
            result.as_mut_ptr() as *mut byte,
            message.as_ptr() as *const byte,
            message.len() as usize,
            clear_memory as bool,
        )
    }
    return result;
}

#[must_use]
pub fn derive_pubkey(skey: EthBlsSecKey) -> EthBlsPubKey {
    let mut result: MaybeUninit<EthBlsPubKey> = MaybeUninit::uninit();
    unsafe {
        ctt_eth_bls_derive_pubkey(
            result.as_mut_ptr() as *mut ctt_eth_bls_pubkey,
            &skey as *const ctt_eth_bls_seckey,
        );
        return result.assume_init();
    }
}

#[must_use]
pub fn pubkeys_are_equal(pkey1: EthBlsPubKey, pkey2: EthBlsPubKey) -> bool {
    unsafe {
        return ctt_eth_bls_pubkeys_are_equal(
            &pkey1 as *const ctt_eth_bls_pubkey,
            &pkey2 as *const ctt_eth_bls_pubkey,
        ) as bool;
    }
}

#[must_use]
pub fn signatures_are_equal(pkey1: EthBlsSignature, pkey2: EthBlsSignature) -> bool {
    unsafe {
        return ctt_eth_bls_signatures_are_equal(
            &pkey1 as *const ctt_eth_bls_signature,
            &pkey2 as *const ctt_eth_bls_signature,
        ) as bool;
    }
}

#[must_use]
pub fn validate_seckey(sec: &EthBlsSecKey) -> Result<(), ctt_codec_scalar_status> {
    unsafe {
        let status = ctt_eth_bls_validate_seckey(sec as *const ctt_eth_bls_seckey);
        match status {
            ctt_codec_scalar_status::cttCodecScalar_Success => Ok(()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn validate_pubkey(pkey: &EthBlsPubKey) -> Result<(), ctt_codec_ecc_status> {
    unsafe {
        let status = ctt_eth_bls_validate_pubkey(pkey as *const ctt_eth_bls_pubkey);
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn validate_signature(sig: &EthBlsSignature) -> Result<(), ctt_codec_ecc_status> {
    unsafe {
        let status = ctt_eth_bls_validate_signature(sig as *const ctt_eth_bls_signature);
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn serialize_seckey(sec: &EthBlsSecKey) -> Result<[u8; 32], ctt_codec_scalar_status> {
    let mut dst = [0u8; 32];
    unsafe {
        let status = ctt_eth_bls_serialize_seckey(
            dst.as_mut_ptr() as *mut byte,
            sec as *const ctt_eth_bls_seckey,
        );
        match status {
            ctt_codec_scalar_status::cttCodecScalar_Success => Ok(dst),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn serialize_pubkey_compressed(pkey: &EthBlsPubKey) -> Result<[u8; 48], ctt_codec_ecc_status> {
    let mut dst = [0u8; 48];
    unsafe {
        let status = ctt_eth_bls_serialize_pubkey_compressed(
            dst.as_mut_ptr() as *mut byte,
            pkey as *const ctt_eth_bls_pubkey,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(dst),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn serialize_signature_compressed(
    sig: &EthBlsSignature,
) -> Result<[u8; 96], ctt_codec_ecc_status> {
    let mut dst = [0u8; 96];
    unsafe {
        let status = ctt_eth_bls_serialize_signature_compressed(
            dst.as_mut_ptr() as *mut byte,
            sig as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(dst),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn deserialize_seckey(src: &[u8; 32]) -> Result<EthBlsSecKey, ctt_codec_scalar_status> {
    let mut result: MaybeUninit<EthBlsSecKey> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_bls_deserialize_seckey(
            result.as_mut_ptr() as *mut ctt_eth_bls_seckey,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_scalar_status::cttCodecScalar_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn deserialize_pubkey_compressed_unchecked(
    src: &[u8; 48],
) -> Result<EthBlsPubKey, ctt_codec_ecc_status> {
    let mut result: MaybeUninit<EthBlsPubKey> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_bls_deserialize_pubkey_compressed_unchecked(
            result.as_mut_ptr() as *mut ctt_eth_bls_pubkey,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(result.assume_init()),
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn deserialize_signature_compressed_unchecked(
    src: &[u8; 96],
) -> Result<EthBlsSignature, ctt_codec_ecc_status> {
    let mut result: MaybeUninit<EthBlsSignature> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_bls_deserialize_signature_compressed_unchecked(
            result.as_mut_ptr() as *mut ctt_eth_bls_signature,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(result.assume_init()),
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn deserialize_pubkey_compressed(src: &[u8; 48]) -> Result<EthBlsPubKey, ctt_codec_ecc_status> {
    let mut result: MaybeUninit<EthBlsPubKey> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_bls_deserialize_pubkey_compressed(
            result.as_mut_ptr() as *mut ctt_eth_bls_pubkey,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(result.assume_init()),
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn deserialize_signature_compressed(
    src: &[u8; 96],
) -> Result<EthBlsSignature, ctt_codec_ecc_status> {
    let mut result: MaybeUninit<EthBlsSignature> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_bls_deserialize_signature_compressed(
            result.as_mut_ptr() as *mut ctt_eth_bls_signature,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(result.assume_init()),
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

pub fn sign(skey: EthBlsSecKey, message: &[u8]) -> EthBlsSignature {
    let mut result: MaybeUninit<EthBlsSignature> = MaybeUninit::uninit();
    unsafe {
        ctt_eth_bls_sign(
            result.as_mut_ptr() as *mut ctt_eth_bls_signature,
            &skey as *const ctt_eth_bls_seckey,
            message.as_ptr() as *const byte,
            message.len() as usize,
        );
        return result.assume_init();
    }
}

#[must_use]
pub fn verify(
    pkey: EthBlsPubKey,
    message: &[u8],
    sig: EthBlsSignature,
) -> Result<bool, ctt_eth_bls_status> {
    unsafe {
        let status = ctt_eth_bls_verify(
            &pkey as *const ctt_eth_bls_pubkey,
            message.as_ptr() as *const byte,
            message.len() as usize,
            &sig as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn fast_aggregate_verify(
    pubkeys: &[EthBlsPubKey],
    message: &[u8],
    signature: &EthBlsSignature,
) -> Result<bool, ctt_eth_bls_status> {
    // TODO: do we really have to clone here, just to assign to CttSpan due to a *mut field?
    //let spans = to_span(&mut msg);

    unsafe {
        let status = ctt_eth_bls_fast_aggregate_verify(
            pubkeys.as_ptr() as *const ctt_eth_bls_pubkey,
            pubkeys.len() as usize,
            message.as_ptr() as *const byte,
            message.len() as usize,
            signature as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status),
        }
    }
}

// Define a byte compatible version of ctt_span so that we have
// access to the fields
#[repr(C)]
pub struct CttSpan {
    pub data: *mut u8,
    pub len: usize,
}

#[must_use]
fn to_span(vec: &mut Vec<Vec<u8>>) -> Vec<CttSpan> {
    let mut spans = Vec::with_capacity(vec.len());
    for v in vec {
        let span = CttSpan {
            data: v.as_mut_ptr() as *mut byte,
            len: v.len(),
        };
        spans.push(span);
    }
    return spans;
}

#[must_use]
pub fn aggregate_verify(
    pubkeys: &[EthBlsPubKey],
    messages: &Vec<Vec<u8>>,
    aggregate_sig: &EthBlsSignature,
) -> Result<bool, ctt_eth_bls_status> {
    // TODO: do we really have to clone here, just to assign to CttSpan due to a *mut field?
    // Funny irony, that we can hand (nested) pointers from Rust (contrary to Go), but pointer
    // sanity logic makes us have to copy anyway?
    let mut msg = messages.clone();
    let spans = to_span(&mut msg);

    unsafe {
        let status = ctt_eth_bls_aggregate_verify(
            pubkeys.as_ptr() as *const ctt_eth_bls_pubkey,
            spans.as_ptr() as *const ctt_span,
            pubkeys.len() as usize,
            aggregate_sig as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn batch_verify(
    pubkeys: &[EthBlsPubKey],
    messages: &Vec<Vec<u8>>,
    signatures: &[EthBlsSignature],
    secure_random_bytes: &[u8; 32],
) -> Result<bool, ctt_eth_bls_status> {
    // TODO: do we really have to clone here, just to assign to CttSpan due to a *mut field?
    // Funny irony, that we can hand (nested) pointers from Rust (contrary to Go), but pointer
    // sanity logic makes us have to copy anyway?
    let mut msg = messages.clone();
    let spans = to_span(&mut msg);

    unsafe {
        let status = ctt_eth_bls_batch_verify(
            pubkeys.as_ptr() as *const ctt_eth_bls_pubkey,
            spans.as_ptr() as *const ctt_span,
            signatures.as_ptr() as *const ctt_eth_bls_signature,
            messages.len() as usize,
            secure_random_bytes.as_ptr() as *const byte,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn batch_verify_parallel(
    tp: &Threadpool,
    pubkeys: &[EthBlsPubKey],
    messages: &Vec<Vec<u8>>,
    signatures: &[EthBlsSignature],
    secure_random_bytes: &[u8; 32],
) -> Result<bool, ctt_eth_bls_status> {
    // TODO: do we really have to clone here, just to assign to CttSpan due to a *mut field?
    // Funny irony, that we can hand (nested) pointers from Rust (contrary to Go), but pointer
    // sanity logic makes us have to copy anyway?
    let mut msg = messages.clone();
    let spans = to_span(&mut msg);

    unsafe {
        let status = ctt_eth_bls_batch_verify_parallel(
            tp.get_private_context(),
            pubkeys.as_ptr() as *const ctt_eth_bls_pubkey,
            spans.as_ptr() as *const ctt_span,
            signatures.as_ptr() as *const ctt_eth_bls_signature,
            messages.len() as usize,
            secure_random_bytes.as_ptr() as *const byte,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status),
        }
    }
}
