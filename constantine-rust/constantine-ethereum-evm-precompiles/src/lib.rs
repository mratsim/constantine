//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::Threadpool;
use constantine_sys::*;

// --------------------------------
// ------- EVM precompiles --------
// --------------------------------

#[must_use]
pub fn evm_sha256(
    result: &mut [u8; 32],
    message: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_sha256(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            message.as_ptr() as *const byte,
            message.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_modexp(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_modexp(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bn254_g1add(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bn254_g1add(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bn254_g1mul(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bn254_g1mul(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bn254_ec_pairing_check(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bn254_ecpairingcheck(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}
pub fn evm_bls12381_g1add(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_g1add(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_g1mul(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_g1mul(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_g1msm(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_g1msm(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_g2add(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_g2add(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_g2mul(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_g2mul(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_g2msm(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_g2msm(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}


pub fn evm_bls12381_pairing_check(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_pairingcheck(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_map_fp_to_g1(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_map_fp_to_g1(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}

pub fn evm_bls12381_map_fp2_to_g2(
    result: &mut [u8],
    inputs: &[u8]
) -> Result<bool, ctt_evm_status> {
    unsafe {
        let status = ctt_eth_evm_bls12381_map_fp2_to_g2(
            result.as_mut_ptr() as *mut byte,
            result.len() as isize,
            inputs.as_ptr() as *const byte,
            inputs.len() as isize,
        );
        match status {
            ctt_evm_status::cttEVM_Success => Ok(true),
            _ => Err(status)
        }
    }
}
