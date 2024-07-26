//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_sys::*;

use ::core::mem::MaybeUninit;

// --------------------------------
// ------- EVM precompiles --------
// --------------------------------

#[inline]
pub fn evm_sha256(message: &[u8]) -> Result<[u8; 32], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 32]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_sha256(
            result.as_mut_ptr() as *mut byte,
            32,
            message.as_ptr() as *const byte,
            message.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_modexp(inputs: &[u8]) -> Result<Vec<u8>, ctt_evm_status> {
    // Call Nim function to determine correct size to allocate for `result`
    unsafe {
        let mut size = 0u64;
        let status = ctt_eth_evm_modexp_result_size(
            &mut size,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        if status != ctt_evm_status::cttEVM_Success {
            return Err(status);
        }

        let mut result = vec![0u8; size as usize];
        let status = ctt_eth_evm_modexp(
            result.as_mut_ptr() as *mut byte,
            result.len() as usize,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bn254_g1add(inputs: &[u8]) -> Result<[u8; 64], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 64]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bn254_g1add(
            result.as_mut_ptr() as *mut byte,
            64,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bn254_g1mul(inputs: &[u8]) -> Result<[u8; 64], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 64]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bn254_g1mul(
            result.as_mut_ptr() as *mut byte,
            64,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bn254_ec_pairing_check(inputs: &[u8]) -> Result<[u8; 32], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 32]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bn254_ecpairingcheck(
            result.as_mut_ptr() as *mut byte,
            32,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_g1add(inputs: &[u8]) -> Result<[u8; 128], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 128]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_g1add(
            result.as_mut_ptr() as *mut byte,
            128,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_g1mul(inputs: &[u8]) -> Result<[u8; 128], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 128]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_g1mul(
            result.as_mut_ptr() as *mut byte,
            128,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_g1msm(inputs: &[u8]) -> Result<[u8; 128], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 128]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_g1msm(
            result.as_mut_ptr() as *mut byte,
            128,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_g2add(inputs: &[u8]) -> Result<[u8; 256], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 256]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_g2add(
            result.as_mut_ptr() as *mut byte,
            256,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_g2mul(inputs: &[u8]) -> Result<[u8; 256], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 256]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_g2mul(
            result.as_mut_ptr() as *mut byte,
            256,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_g2msm(inputs: &[u8]) -> Result<[u8; 256], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 256]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_g2msm(
            result.as_mut_ptr() as *mut byte,
            256,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_pairing_check(inputs: &[u8]) -> Result<[u8; 32], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 32]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_pairingcheck(
            result.as_mut_ptr() as *mut byte,
            32,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_map_fp_to_g1(inputs: &[u8]) -> Result<[u8; 128], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 128]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_map_fp_to_g1(
            result.as_mut_ptr() as *mut byte,
            128,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}

#[inline]
pub fn evm_bls12381_map_fp2_to_g2(inputs: &[u8]) -> Result<[u8; 256], ctt_evm_status> {
    let mut result: MaybeUninit<[u8; 256]> = MaybeUninit::uninit();
    unsafe {
        let status = ctt_eth_evm_bls12381_map_fp2_to_g2(
            result.as_mut_ptr() as *mut byte,
            256,
            inputs.as_ptr() as *const byte,
            inputs.len() as usize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(result.assume_init()),
            _ => Err(status),
        }
    }
}
