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
    pub ctx: *const ctt_eth_kzg_context,
    threadpool: Option<&'tp Threadpool>,
}

pub struct EthKzgContextBuilder<'tp> {
    ctx: Option<*const ctt_eth_kzg_context>,
    threadpool: Option<&'tp Threadpool>,
}

impl<'tp> Drop for EthKzgContext<'tp> {
    #[inline(always)]
    fn drop(&mut self) {
        unsafe { ctt_eth_kzg_context_delete(self.ctx as *mut ctt_eth_kzg_context) }
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
            ctt_eth_kzg_context_new(
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

    /// Create a KZG context with precomputed MSM tables for FK20 proofs (PeerDAS).
    ///
    /// `t` = base groups (stride between precomputed layers)
    /// `b` = bits per window (window size = 2^b)
    ///
    /// SPEED / MEMORY TRADEOFF (PeerDAS, compute_cells_and_kzg_proofs = 128 MSMs per blob):
    /// - no precompute, 1.8 MiB total:        7.083 ops/s   ~141 ms/blob
    /// - t= 64, b= 6, ~   32.2 MiB total:     8.724 ops/s   ~115 ms/blob
    /// - t= 64, b= 8, ~   96.0 MiB total:     9.518 ops/s   ~105 ms/blob
    /// - t= 64, b=10, ~  312.0 MiB total:    10.547 ops/s    ~95 ms/blob
    /// - t= 64, b=12, ~ 1056.0 MiB total:    11.629 ops/s    ~86 ms/blob
    /// - t=128, b= 6, ~   16.5 MiB total:     8.783 ops/s   ~114 ms/blob
    /// - t=128, b= 8, ~   48.0 MiB total:     9.965 ops/s   ~100 ms/blob
    /// - t=128, b=10, ~  156.0 MiB total:    10.561 ops/s    ~95 ms/blob
    /// - t=128, b=12, ~  528.0 MiB total:    11.505 ops/s    ~87 ms/blob
    /// - t=256, b= 6, ~    8.2 MiB total:     8.641 ops/s   ~116 ms/blob
    /// - t=256, b= 8, ~   24.0 MiB total:    10.244 ops/s    ~98 ms/blob
    /// - t=256, b=10, ~   84.0 MiB total:    10.281 ops/s    ~97 ms/blob
    /// - t=256, b=12, ~  288.0 MiB total:    10.868 ops/s    ~92 ms/blob
    ///
    /// CPU: Intel i7-265K
    /// Larger b = faster per MSM but exponentially more memory (2^b entries).
    /// Larger t = fewer doublings but more precomputed layers.
    /// Recommended (t=256, b=8): ~98 ms/blob proving, ~24 MiB total memory.
    pub fn load_trusted_setup_with_precompute(self, file_path: &Path, t: i32, b: i32) -> Result<Self, ctt_eth_trusted_setup_status> {
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
            ctt_eth_kzg_context_new_with_precompute(
                ctx_ptr,
                c_path.as_ptr(),
                ctt_eth_trusted_setup_format::cttEthTSFormat_ckzg4844,
                t,
                b,
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

// PeerDAS (EIP-7594)
// ------------------------------------------------------------

impl<'tp> EthKzgContext<'tp> {
    pub fn compute_cells_and_kzg_proofs(
        &self,
        blob: &[u8; 131_072],
    ) -> Result<(Box<[u8; 262_144]>, Box<[u8; 6_144]>), ctt_eth_kzg_status> {
        use std::mem::ManuallyDrop;
        let mut cells = ManuallyDrop::new(Box::<[u8; 262_144]>::new_uninit());
        let mut proofs = ManuallyDrop::new(Box::<[u8; 6_144]>::new_uninit());
        let status = unsafe {
            ctt_eth_kzg_compute_cells_and_kzg_proofs(
                self.ctx,
                cells.as_mut_ptr() as *mut ctt_eth_kzg_cell,
                proofs.as_mut_ptr() as *mut ctt_eth_kzg_proof,
                blob.as_ptr() as *const ctt_eth_kzg_blob,
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => {
                Ok(unsafe { (ManuallyDrop::into_inner(cells).assume_init(),
                            ManuallyDrop::into_inner(proofs).assume_init()) })
            }
            _ => {
                unsafe {
                    ManuallyDrop::drop(&mut cells);
                    ManuallyDrop::drop(&mut proofs);
                }
                Err(status)
            }
        }
    }

    pub fn verify_cell_kzg_proof_batch(
        &self,
        commitments: &[[u8; 48]],
        cell_indices: &[u64],
        cells: &[[u8; 2048]],
        proofs: &[[u8; 48]],
        secure_random_bytes: &[u8; 32],
    ) -> Result<bool, ctt_eth_kzg_status> {
        let n = commitments.len();
        if n != cell_indices.len() || n != cells.len() || n != proofs.len() {
            return Err(ctt_eth_kzg_status::cttEthKzg_InputsLengthsMismatch);
        }
        let status = unsafe {
            ctt_eth_kzg_verify_cell_kzg_proof_batch(
                self.ctx,
                commitments.as_ptr() as *const ctt_eth_kzg_commitment,
                cell_indices.as_ptr(),
                cells.as_ptr() as *const ctt_eth_kzg_cell,
                proofs.as_ptr() as *const ctt_eth_kzg_proof,
                n,
                secure_random_bytes.as_ptr(),
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => Ok(true),
            ctt_eth_kzg_status::cttEthKzg_VerificationFailure => Ok(false),
            _ => Err(status),
        }
    }

    pub fn recover_cells_and_kzg_proofs(
        &self,
        cells: &[[u8; 2048]],
        cell_indices: &[u64],
    ) -> Result<(Box<[u8; 262_144]>, Box<[u8; 6_144]>), ctt_eth_kzg_status> {
        if cells.len() != cell_indices.len() {
            return Err(ctt_eth_kzg_status::cttEthKzg_InputsLengthsMismatch);
        }
        use std::mem::ManuallyDrop;
        let mut recovered_cells = ManuallyDrop::new(Box::<[u8; 262_144]>::new_uninit());
        let mut recovered_proofs = ManuallyDrop::new(Box::<[u8; 6_144]>::new_uninit());
        let status = unsafe {
            ctt_eth_kzg_recover_cells_and_kzg_proofs(
                self.ctx,
                recovered_cells.as_mut_ptr() as *mut ctt_eth_kzg_cell,
                recovered_proofs.as_mut_ptr() as *mut ctt_eth_kzg_proof,
                cell_indices.as_ptr(),
                cells.as_ptr() as *const ctt_eth_kzg_cell,
                cells.len(),
            )
        };
        match status {
            ctt_eth_kzg_status::cttEthKzg_Success => {
                Ok(unsafe { (ManuallyDrop::into_inner(recovered_cells).assume_init(),
                            ManuallyDrop::into_inner(recovered_proofs).assume_init()) })
            }
            _ => {
                unsafe {
                    ManuallyDrop::drop(&mut recovered_cells);
                    ManuallyDrop::drop(&mut recovered_proofs);
                }
                Err(status)
            }
        }
    }

}
