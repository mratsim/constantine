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
use std::{ffi::CString, path::Path};

// Trusted setup
// ------------------------------------------------------------

#[derive(Debug)]
pub struct EthKzgContext<'tp> {
    ctx: *const ctt_eth_kzg_context,
    threadpool: Option<&'tp Threadpool>,
}

pub struct EthKzgContextBuilder<'tp> {
    ctx: Option<*const ctt_eth_kzg_context>,
    threadpool: Option<&'tp Threadpool>,
}

impl<'tp> Drop for EthKzgContext<'tp> {
    #[inline(always)]
    fn drop(&mut self) {
        unsafe { ctt_eth_trusted_setup_delete(self.ctx as *mut ctt_eth_kzg_context) }
    }
}

impl<'tp> EthKzgContextBuilder<'tp> {
    pub fn load_trusted_setup(self, file_path: &Path) -> Result<Self, ctt_eth_trusted_setup_status> {
        // The joy of OS Paths / C Paths:
        // https://users.rust-lang.org/t/easy-way-to-pass-a-path-to-c/51829
        // https://doc.rust-lang.org/std/ffi/index.html#conversions
        //
        // But Rust widechar for Windows is irrelevant for fopen
        // https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/fopen-wfopen

        #[cfg(unix)]
        let raw_path = {
            use std::os::unix::prelude::OsStrExt;
            file_path.as_os_str().as_bytes()
        };

        #[cfg(windows)]
        let raw_path = {
            file_path
                .as_os_str()
                .to_str()
                .ok_or(ctt_eth_trusted_setup_status::cttEthTS_MissingOrInaccessibleFile)?
                .as_bytes()
        };

        let c_path = CString::new(raw_path)
            .map_err(|_| ctt_eth_trusted_setup_status::cttEthTS_MissingOrInaccessibleFile)?;

        let mut ctx: *mut ctt_eth_kzg_context = std::ptr::null_mut();
        let ctx_ptr: *mut *mut ctt_eth_kzg_context = &mut ctx;
        let status = unsafe {
            ctt_eth_trusted_setup_load(
                ctx_ptr,
                c_path.as_ptr(),
                ctt_eth_trusted_setup_format::cttEthTSFormat_ckzg4844,
            )
        };
        match status {
            ctt_eth_trusted_setup_status::cttEthTS_Success => Ok(Self { ctx: Some(ctx), threadpool: self.threadpool }),
            _ => Err(status),
        }
    }

    pub fn set_threadpool(self, tp: &'tp Threadpool) -> Self {
        // Copy all other parameters
        let Self { ctx, .. } = self;
        // Return with threadpool
        Self { ctx, threadpool: Some(tp)}
    }

    pub fn build(self) -> Result<EthKzgContext<'tp>, ctt_eth_trusted_setup_status> {
        let ctx = self.ctx.ok_or(ctt_eth_trusted_setup_status::cttEthTS_MissingOrInaccessibleFile)?;
        Ok(EthKzgContext{
            ctx,
            threadpool: self.threadpool,
        })
    }

}

impl<'tp> EthKzgContext<'tp> {
    pub fn builder() -> EthKzgContextBuilder<'tp> {
        EthKzgContextBuilder{ctx: None, threadpool: None}
    }

    pub fn load_trusted_setup(file_path: &Path) -> Result<Self, ctt_eth_trusted_setup_status> {
        Ok(Self::builder()
            .load_trusted_setup(file_path)?
            .build()
            .expect("Trusted setup should be loaded properly"))
    }

    #[inline]
    pub fn blob_to_kzg_commitment(
        &self,
        blob: &[u8; 4096 * 32],
    ) -> Result<[u8; 48], ctt_eth_kzg_status> {
        let mut result: MaybeUninit<[u8; 48]> = MaybeUninit::uninit();
        unsafe {
            let status = ctt_eth_kzg_blob_to_kzg_commitment(
                self.ctx,
                result.as_mut_ptr() as *mut ctt_eth_kzg_commitment,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
            );
            match status {
                ctt_eth_kzg_status::cttEthKzg_Success => Ok(result.assume_init()),
                _ => Err(status),
            }
        }
    }

    #[inline]
    pub fn compute_kzg_proof(
        &self,
        blob: &[u8; 4096 * 32],
        z_challenge: &[u8; 32],
    ) -> Result<([u8; 48], [u8; 32]), ctt_eth_kzg_status> {
        let mut proof = MaybeUninit::<[u8; 48]>::uninit();
        let mut y_eval = MaybeUninit::<[u8; 32]>::uninit();
        unsafe {
            let status = ctt_eth_kzg_compute_kzg_proof(
                self.ctx,
                proof.as_mut_ptr() as *mut ctt_eth_kzg_proof,
                y_eval.as_mut_ptr() as *mut ctt_eth_kzg_eval_at_challenge,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
                z_challenge.as_ptr() as *const ctt_eth_kzg_opening_challenge,
            );
            match status {
                ctt_eth_kzg_status::cttEthKzg_Success => {
                    Ok((proof.assume_init(), y_eval.assume_init()))
                }
                _ => Err(status),
            }
        }
    }

    #[inline]
    pub fn verify_kzg_proof(
        &self,
        commitment: &[u8; 48],
        z_challenge: &[u8; 32],
        y_eval_at_challenge: &[u8; 32],
        proof: &[u8; 48],
    ) -> Result<bool, ctt_eth_kzg_status> {
        let status = unsafe {
            ctt_eth_kzg_verify_kzg_proof(
                self.ctx,
                commitment.as_ptr() as *const ctt_eth_kzg_commitment,
                z_challenge.as_ptr() as *const ctt_eth_kzg_opening_challenge,
                y_eval_at_challenge.as_ptr() as *const ctt_eth_kzg_eval_at_challenge,
                proof.as_ptr() as *const ctt_eth_kzg_proof,
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => Ok(true),
            ctt_eth_kzg_status::cttEthKzg_VerificationFailure => Ok(false),
            _ => Err(status),
        }
    }

    #[inline]
    pub fn compute_blob_kzg_proof(
        &self,
        blob: &[u8; 4096 * 32],
        commitment: &[u8; 48],
    ) -> Result<[u8; 48], ctt_eth_kzg_status> {
        let mut proof = MaybeUninit::<[u8; 48]>::uninit();
        unsafe {
            let status = ctt_eth_kzg_compute_blob_kzg_proof(
                self.ctx,
                proof.as_mut_ptr() as *mut ctt_eth_kzg_proof,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
                commitment.as_ptr() as *const ctt_eth_kzg_commitment,
            );
            match status {
                ctt_eth_kzg_status::cttEthKzg_Success => Ok(proof.assume_init()),
                _ => Err(status),
            }
        }
    }

    #[inline]
    pub fn verify_blob_kzg_proof(
        &self,
        blob: &[u8; 4096 * 32],
        commitment: &[u8; 48],
        proof: &[u8; 48],
    ) -> Result<bool, ctt_eth_kzg_status> {
        let status = unsafe {
            ctt_eth_kzg_verify_blob_kzg_proof(
                self.ctx,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
                commitment.as_ptr() as *const ctt_eth_kzg_commitment,
                proof.as_ptr() as *const ctt_eth_kzg_proof,
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => Ok(true),
            ctt_eth_kzg_status::cttEthKzg_VerificationFailure => Ok(false),
            _ => Err(status),
        }
    }

    #[inline]
    pub fn verify_blob_kzg_proof_batch(
        &self,
        blobs: &[[u8; 4096 * 32]],
        commitments: &[[u8; 48]],
        proofs: &[[u8; 48]],
        secure_random_bytes: &[u8; 32],
    ) -> Result<bool, ctt_eth_kzg_status> {
        if blobs.len() != commitments.len() || blobs.len() != proofs.len() {
            return Err(ctt_eth_kzg_status::cttEthKzg_InputsLengthsMismatch);
        }

        let status = unsafe {
            ctt_eth_kzg_verify_blob_kzg_proof_batch(
                self.ctx,
                blobs.as_ptr() as *const ctt_eth_kzg_blob,
                commitments.as_ptr() as *const ctt_eth_kzg_commitment,
                proofs.as_ptr() as *const ctt_eth_kzg_proof,
                blobs.len(),
                secure_random_bytes.as_ptr(),
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => Ok(true),
            ctt_eth_kzg_status::cttEthKzg_VerificationFailure => Ok(false),
            _ => Err(status),
        }
    }

    // Parallel versions
    // --------------------------------------------------------------------

    #[inline]
    pub fn blob_to_kzg_commitment_parallel(
        &self,
        blob: &[u8; 4096 * 32],
    ) -> Result<[u8; 48], ctt_eth_kzg_status> {
        let mut result: MaybeUninit<[u8; 48]> = MaybeUninit::uninit();
        unsafe {
            let status = ctt_eth_kzg_blob_to_kzg_commitment_parallel(
                self.threadpool.expect("Threadpool has been set").get_private_context(),
                self.ctx,
                result.as_mut_ptr() as *mut ctt_eth_kzg_commitment,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
            );
            match status {
                ctt_eth_kzg_status::cttEthKzg_Success => Ok(result.assume_init()),
                _ => Err(status),
            }
        }
    }

    #[inline]
    pub fn compute_kzg_proof_parallel(
        &self,
        blob: &[u8; 4096 * 32],
        z_challenge: &[u8; 32],
    ) -> Result<([u8; 48], [u8; 32]), ctt_eth_kzg_status> {
        let mut proof = MaybeUninit::<[u8; 48]>::uninit();
        let mut y_eval = MaybeUninit::<[u8; 32]>::uninit();
        unsafe {
            let status = ctt_eth_kzg_compute_kzg_proof_parallel(
                self.threadpool.expect("Threadpool has been set").get_private_context(),
                self.ctx,
                proof.as_mut_ptr() as *mut ctt_eth_kzg_proof,
                y_eval.as_mut_ptr() as *mut ctt_eth_kzg_eval_at_challenge,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
                z_challenge.as_ptr() as *const ctt_eth_kzg_opening_challenge,
            );
            match status {
                ctt_eth_kzg_status::cttEthKzg_Success => {
                    Ok((proof.assume_init(), y_eval.assume_init()))
                }
                _ => Err(status),
            }
        }
    }

    #[inline]
    pub fn compute_blob_kzg_proof_parallel(
        &self,
        blob: &[u8; 4096 * 32],
        commitment: &[u8; 48],
    ) -> Result<[u8; 48], ctt_eth_kzg_status> {
        let mut proof = MaybeUninit::<[u8; 48]>::uninit();
        unsafe {
            let status = ctt_eth_kzg_compute_blob_kzg_proof_parallel(
                self.threadpool.expect("Threadpool has been set").get_private_context(),
                self.ctx,
                proof.as_mut_ptr() as *mut ctt_eth_kzg_proof,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
                commitment.as_ptr() as *const ctt_eth_kzg_commitment,
            );
            match status {
                ctt_eth_kzg_status::cttEthKzg_Success => Ok(proof.assume_init()),
                _ => Err(status),
            }
        }
    }

    #[inline]
    pub fn verify_blob_kzg_proof_parallel(
        &self,
        blob: &[u8; 4096 * 32],
        commitment: &[u8; 48],
        proof: &[u8; 48],
    ) -> Result<bool, ctt_eth_kzg_status> {
        let status = unsafe {
            ctt_eth_kzg_verify_blob_kzg_proof_parallel(
                self.threadpool.expect("Threadpool has been set").get_private_context(),
                self.ctx,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
                commitment.as_ptr() as *const ctt_eth_kzg_commitment,
                proof.as_ptr() as *const ctt_eth_kzg_proof,
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => Ok(true),
            ctt_eth_kzg_status::cttEthKzg_VerificationFailure => Ok(false),
            _ => Err(status),
        }
    }

    #[inline]
    pub fn verify_blob_kzg_proof_batch_parallel(
        &self,
        blobs: &[[u8; 4096 * 32]],
        commitments: &[[u8; 48]],
        proofs: &[[u8; 48]],
        secure_random_bytes: &[u8; 32],
    ) -> Result<bool, ctt_eth_kzg_status> {
        if blobs.len() != commitments.len() || blobs.len() != proofs.len() {
            return Err(ctt_eth_kzg_status::cttEthKzg_InputsLengthsMismatch);
        }

        let status = unsafe {
            ctt_eth_kzg_verify_blob_kzg_proof_batch_parallel(
                self.threadpool.expect("Threadpool has been set").get_private_context(),
                self.ctx,
                blobs.as_ptr() as *const ctt_eth_kzg_blob,
                commitments.as_ptr() as *const ctt_eth_kzg_commitment,
                proofs.as_ptr() as *const ctt_eth_kzg_proof,
                blobs.len(),
                secure_random_bytes.as_ptr(),
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => Ok(true),
            ctt_eth_kzg_status::cttEthKzg_VerificationFailure => Ok(false),
            _ => Err(status),
        }
    }
}
