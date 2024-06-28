//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::Threadpool;
use constantine_sys::*;

// Create type aliases for the C types
pub type EthBlsSecKey = ctt_eth_bls_seckey;
pub type EthBlsPubKey = ctt_eth_bls_pubkey;
pub type EthBlsSignature = ctt_eth_bls_signature;

#[must_use]
pub fn deserialize_seckey(
    skey: *mut EthBlsSecKey,
    src: &[u8; 32]
) -> Result<bool, ctt_codec_scalar_status> {
    unsafe {
        let status = ctt_eth_bls_deserialize_seckey(
            skey as *mut ctt_eth_bls_seckey,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_scalar_status::cttCodecScalar_Success => Ok(true),
            _ => Err(status),
        }
    }
}

#[must_use]
pub fn sha256_hash(
    message: &[u8], clear_memory: bool
) -> [u8; 32] {
    let mut result = [0u8; 32];
    unsafe {
        ctt_sha256_hash(
            result.as_mut_ptr() as *mut byte,
            message.as_ptr() as *const byte,
            message.len() as isize,
            clear_memory as bool
        )
    }
    return result
}

pub fn derive_pubkey(
    pkey: *mut EthBlsPubKey,
    skey: EthBlsSecKey
) {
    unsafe {
        ctt_eth_bls_derive_pubkey(
            pkey as *mut ctt_eth_bls_pubkey,
            &skey as *const ctt_eth_bls_seckey,
        );
    }
}


#[must_use]
pub fn pubkeys_are_equal(
    pkey1: EthBlsPubKey,
    pkey2: EthBlsPubKey,
) -> bool {
    unsafe {
        return ctt_eth_bls_pubkeys_are_equal(
            &pkey1 as *const ctt_eth_bls_pubkey,
            &pkey2 as *const ctt_eth_bls_pubkey,
        ) as bool;
    }
}

#[must_use]
pub fn signatures_are_equal(
    pkey1: EthBlsSignature,
    pkey2: EthBlsSignature,
) -> bool {
    unsafe {
        return ctt_eth_bls_signatures_are_equal(
            &pkey1 as *const ctt_eth_bls_signature,
            &pkey2 as *const ctt_eth_bls_signature,
        ) as bool;
    }
}

#[must_use]
pub fn serialize_pubkey_compressed(
    pkey: &EthBlsPubKey,
    dst: &mut [u8; 48],
) -> Result<bool, ctt_codec_ecc_status> {
    unsafe {
        let status = ctt_eth_bls_serialize_pubkey_compressed(
            dst.as_mut_ptr() as *mut byte,
            pkey as *const ctt_eth_bls_pubkey,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(true),
            _ => Err(status)
        }
    }

}

#[must_use]
pub fn serialize_signature_compressed(
    sig: &EthBlsSignature,
    dst: &mut [u8; 96],
) -> Result<bool, ctt_codec_ecc_status> {
    unsafe {
        let status = ctt_eth_bls_serialize_signature_compressed(
            dst.as_mut_ptr() as *mut byte,
            sig as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(true),
            _ => Err(status)
        }
    }

}

#[must_use]
pub fn deserialize_pubkey_compressed(
    pkey: *mut EthBlsPubKey,
    src: &[u8; 48],
) -> Result<bool, ctt_codec_ecc_status> {
    unsafe {
        let status = ctt_eth_bls_deserialize_pubkey_compressed(
            pkey as *mut ctt_eth_bls_pubkey,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(true),
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => Ok(true),
            _ => Err(status)
        }
    }
}

#[must_use]
pub fn deserialize_signature_compressed(
    sig: *mut EthBlsSignature,
    src: &[u8; 96],
) -> Result<bool, ctt_codec_ecc_status> {
    unsafe {
        let status = ctt_eth_bls_deserialize_signature_compressed(
            sig as *mut ctt_eth_bls_signature,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_ecc_status::cttCodecEcc_Success => Ok(true),
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => Ok(true),
            _ => Err(status)
        }
    }
}

#[must_use]
pub fn deserialize_seckey_compressed(
    skey: *mut EthBlsSecKey,
    src: &[u8; 32],
) -> Result<bool, ctt_codec_scalar_status> {
    unsafe {
        let status = ctt_eth_bls_deserialize_seckey(
            skey as *mut ctt_eth_bls_seckey,
            src.as_ptr() as *const byte,
        );
        match status {
            ctt_codec_scalar_status::cttCodecScalar_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn sign(
    sig: *mut EthBlsSignature,
    skey: EthBlsSecKey,
    message: &[u8]
) {
    unsafe {
        ctt_eth_bls_sign(
            sig as *mut ctt_eth_bls_signature,
            &skey as *const ctt_eth_bls_seckey,
            message.as_ptr() as *const byte,
            message.len() as isize
        )
    }
}

#[must_use]
pub fn verify(
    pkey: &EthBlsPubKey,
    message: &[u8],
    sig: EthBlsSignature,
) -> Result<bool, ctt_eth_bls_status> {
    unsafe {
        let status = ctt_eth_bls_verify(
            pkey as *const ctt_eth_bls_pubkey,
            message.as_ptr() as *const byte,
            message.len() as isize,
            &sig as *const ctt_eth_bls_signature
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status)
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
            pubkeys.len() as isize,
            message.as_ptr() as *const byte,
            message.len() as isize,
            signature as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status)
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
        let span = CttSpan{
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
            pubkeys.len() as isize,
            aggregate_sig as *const ctt_eth_bls_signature,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status)
        }
    }
}

#[must_use]
pub fn batch_verify(
    pubkeys: &[EthBlsPubKey],
    messages: &Vec<Vec<u8>>,
    signatures: &[EthBlsSignature],
    secure_random_bytes: &[u8; 32]
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
            messages.len() as isize,
            secure_random_bytes.as_ptr() as *const byte,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status)
        }
    }
}

#[must_use]
pub fn batch_verify_parallel(
    tp: &Threadpool,
    pubkeys: &[EthBlsPubKey],
    messages: &Vec<Vec<u8>>,
    signatures: &[EthBlsSignature],
    secure_random_bytes: &[u8; 32]
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
            messages.len() as isize,
            secure_random_bytes.as_ptr() as *const byte,
        );
        match status {
            ctt_eth_bls_status::cttEthBls_Success => Ok(true),
            _ => Err(status)
        }
    }
}
