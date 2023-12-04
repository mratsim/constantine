//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

//! Implementation of the ZK Accel Layer using Constantine as a backend
//! See https://github.com/privacy-scaling-explorations/halo2/issues/216

use ::core::mem::MaybeUninit;
use constantine_sys::*;
use halo2curves::bn256;
use halo2curves::zal::{MsmAccel, ZalEngine};
use std::mem;

pub struct CttEngine {
    ctx: *mut ctt_threadpool,
}

impl CttEngine {
    #[inline(always)]
    pub fn new(num_threads: usize) -> CttEngine {
        let ctx = unsafe { ctt_threadpool_new(num_threads) };
        CttEngine { ctx }
    }
}

impl Drop for CttEngine {
    fn drop(&mut self) {
        unsafe { ctt_threadpool_shutdown(self.ctx) }
    }
}

impl ZalEngine for CttEngine {}

impl MsmAccel<bn256::G1Affine> for CttEngine {
    fn msm(&self, coeffs: &[bn256::Fr], bases: &[bn256::G1Affine]) -> bn256::G1 {
        assert_eq!(coeffs.len(), bases.len());
        let mut result: MaybeUninit<bn254_snarks_g1_prj> = MaybeUninit::uninit();
        unsafe {
            ctt_bn254_snarks_g1_prj_multi_scalar_mul_fr_coefs_vartime_parallel(
                self.ctx,
                result.as_mut_ptr(),
                coeffs.as_ptr() as *const bn254_snarks_fr,
                bases.as_ptr() as *const bn254_snarks_g1_aff,
                bases.len(),
            );
            mem::transmute::<MaybeUninit<bn254_snarks_g1_prj>, bn256::G1>(result)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use ark_std::{end_timer, start_timer};
    use rand_core::OsRng;

    use halo2curves::bn256;
    use halo2curves::ff::Field;
    use halo2curves::group::prime::PrimeCurveAffine;
    use halo2curves::group::{Curve, Group};
    use halo2curves::msm::best_multiexp;
    use halo2curves::zal::MsmAccel;

    #[test]
    fn t_threadpool() {
        let tp = CttEngine::new(4);
        drop(tp);
    }

    fn run_msm_zal(min_k: usize, max_k: usize) {
        let points = (0..1 << max_k)
            .map(|_| bn256::G1::random(OsRng))
            .collect::<Vec<_>>();
        let mut affine_points = vec![bn256::G1Affine::identity(); 1 << max_k];
        bn256::G1::batch_normalize(&points[..], &mut affine_points[..]);
        let points = affine_points;

        let scalars = (0..1 << max_k)
            .map(|_| bn256::Fr::random(OsRng))
            .collect::<Vec<_>>();

        for k in min_k..=max_k {
            let points = &points[..1 << k];
            let scalars = &scalars[..1 << k];

            let t0 = start_timer!(|| format!("freestanding msm k={}", k));
            let e0 = best_multiexp(scalars, points);
            end_timer!(t0);

            let engine = CttEngine::new(num_cpus::get());
            let t1 = start_timer!(|| format!("CttEngine msm k={}", k));
            let e1 = engine.msm(scalars, points);
            end_timer!(t1);

            assert_eq!(e0, e1);
        }
    }

    #[test]
    fn t_msm_zal() {
        run_msm_zal(3, 14);
    }
}
