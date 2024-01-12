//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

//! Implementation of the ZK Accel Layer using Constantine as a backend
//! See https://github.com/privacy-scaling-explorations/halo2/issues/216

use constantine_core::Threadpool;
use constantine_sys::*;

use ::core::mem::MaybeUninit;
use std::mem;

use halo2curves::{bn256, pasta::pallas, pasta::vesta};
use halo2curves::zal::{MsmAccel, ZalEngine};
use halo2curves::CurveAffine;

#[derive(Debug)]
pub struct CttEngine(Threadpool);

impl CttEngine {
    #[inline(always)]
    pub fn new(num_threads: usize) -> Self {
        Self(Threadpool::new(num_threads))
    }
}

#[derive(Debug)]
pub struct CttMsmCoeffsDesc<'c, C: CurveAffine> {
    raw: &'c [C::Scalar],
}

#[derive(Debug)]
pub struct CttMsmBaseDesc<'b, C: CurveAffine> {
    raw: &'b [C],
}

impl ZalEngine for CttEngine {}

impl MsmAccel<bn256::G1Affine> for CttEngine {
    fn msm(&self, coeffs: &[bn256::Fr], bases: &[bn256::G1Affine]) -> bn256::G1 {
        assert_eq!(coeffs.len(), bases.len());
        let mut result = MaybeUninit::<bn254_snarks_g1_prj>::uninit();
        unsafe {
            ctt_bn254_snarks_g1_prj_multi_scalar_mul_fr_coefs_vartime_parallel(
                self.0.get_private_context(),
                result.as_mut_ptr(),
                coeffs.as_ptr() as *const bn254_snarks_fr,
                bases.as_ptr() as *const bn254_snarks_g1_aff,
                bases.len(),
            );
            mem::transmute::<MaybeUninit<bn254_snarks_g1_prj>, bn256::G1>(result)
        }
    }

    // Caching API
    // -------------------------------------------------

    type CoeffsDescriptor<'c> = CttMsmCoeffsDesc<'c, bn256::G1Affine>;
    type BaseDescriptor<'b> = CttMsmBaseDesc<'b, bn256::G1Affine>;

    fn get_coeffs_descriptor<'c>(&self, coeffs: &'c [bn256::Fr]) -> Self::CoeffsDescriptor<'c> {
        // Do expensive device/library specific preprocessing here
        Self::CoeffsDescriptor { raw: coeffs }
    }
    fn get_base_descriptor<'b>(&self, base: &'b [bn256::G1Affine]) -> Self::BaseDescriptor<'b> {
        // Do expensive device/library specific preprocessing here
        Self::BaseDescriptor { raw: base }
    }

    fn msm_with_cached_scalars(
        &self,
        coeffs: &Self::CoeffsDescriptor<'_>,
        base: &[bn256::G1Affine],
    ) -> bn256::G1 {
        self.msm(coeffs.raw, base)
    }

    fn msm_with_cached_base(
        &self,
        coeffs: &[bn256::Fr],
        base: &Self::BaseDescriptor<'_>,
    ) -> bn256::G1 {
        self.msm(coeffs, base.raw)
    }

    fn msm_with_cached_inputs(
        &self,
        coeffs: &Self::CoeffsDescriptor<'_>,
        base: &Self::BaseDescriptor<'_>,
    ) -> bn256::G1 {
        self.msm(coeffs.raw, base.raw)
    }
}

impl MsmAccel<pallas::Affine> for CttEngine {
    fn msm(&self, coeffs: &[pallas::Scalar], bases: &[pallas::Affine]) -> pallas::Point {
        assert_eq!(coeffs.len(), bases.len());
        let mut result = MaybeUninit::<vesta_ec_jac>::uninit();
        unsafe {
            ctt_vesta_ec_jac_multi_scalar_mul_fr_coefs_vartime_parallel(
                self.0.get_private_context(),
                result.as_mut_ptr(),
                coeffs.as_ptr() as *const vesta_fr,
                bases.as_ptr() as *const vesta_ec_aff,
                bases.len(),
            );
            mem::transmute::<MaybeUninit<vesta_ec_jac>, pallas::Point>(result)
        }
    }

    // Caching API
    // -------------------------------------------------

    type CoeffsDescriptor<'c> = CttMsmCoeffsDesc<'c, pallas::Affine>;
    type BaseDescriptor<'b> = CttMsmBaseDesc<'b, pallas::Affine>;

    fn get_coeffs_descriptor<'c>(&self, coeffs: &'c [pallas::Scalar]) -> Self::CoeffsDescriptor<'c> {
        // Do expensive device/library specific preprocessing here
        Self::CoeffsDescriptor { raw: coeffs }
    }
    fn get_base_descriptor<'b>(&self, base: &'b [pallas::Affine]) -> Self::BaseDescriptor<'b> {
        // Do expensive device/library specific preprocessing here
        Self::BaseDescriptor { raw: base }
    }

    fn msm_with_cached_scalars(
        &self,
        coeffs: &Self::CoeffsDescriptor<'_>,
        base: &[pallas::Affine],
    ) -> pallas::Point {
        self.msm(coeffs.raw, base)
    }

    fn msm_with_cached_base(
        &self,
        coeffs: &[pallas::Scalar],
        base: &Self::BaseDescriptor<'_>,
    ) -> pallas::Point {
        self.msm(coeffs, base.raw)
    }

    fn msm_with_cached_inputs(
        &self,
        coeffs: &Self::CoeffsDescriptor<'_>,
        base: &Self::BaseDescriptor<'_>,
    ) -> pallas::Point {
        self.msm(coeffs.raw, base.raw)
    }
}

impl MsmAccel<vesta::Affine> for CttEngine {
    fn msm(&self, coeffs: &[vesta::Scalar], bases: &[vesta::Affine]) -> vesta::Point {
        assert_eq!(coeffs.len(), bases.len());
        let mut result = MaybeUninit::<vesta_ec_jac>::uninit();
        unsafe {
            ctt_vesta_ec_jac_multi_scalar_mul_fr_coefs_vartime_parallel(
                self.0.get_private_context(),
                result.as_mut_ptr(),
                coeffs.as_ptr() as *const vesta_fr,
                bases.as_ptr() as *const vesta_ec_aff,
                bases.len(),
            );
            mem::transmute::<MaybeUninit<vesta_ec_jac>, vesta::Point>(result)
        }
    }

    // Caching API
    // -------------------------------------------------

    type CoeffsDescriptor<'c> = CttMsmCoeffsDesc<'c, vesta::Affine>;
    type BaseDescriptor<'b> = CttMsmBaseDesc<'b, vesta::Affine>;

    fn get_coeffs_descriptor<'c>(&self, coeffs: &'c [vesta::Scalar]) -> Self::CoeffsDescriptor<'c> {
        // Do expensive device/library specific preprocessing here
        Self::CoeffsDescriptor { raw: coeffs }
    }
    fn get_base_descriptor<'b>(&self, base: &'b [vesta::Affine]) -> Self::BaseDescriptor<'b> {
        // Do expensive device/library specific preprocessing here
        Self::BaseDescriptor { raw: base }
    }

    fn msm_with_cached_scalars(
        &self,
        coeffs: &Self::CoeffsDescriptor<'_>,
        base: &[vesta::Affine],
    ) -> vesta::Point {
        self.msm(coeffs.raw, base)
    }

    fn msm_with_cached_base(
        &self,
        coeffs: &[vesta::Scalar],
        base: &Self::BaseDescriptor<'_>,
    ) -> vesta::Point {
        self.msm(coeffs, base.raw)
    }

    fn msm_with_cached_inputs(
        &self,
        coeffs: &Self::CoeffsDescriptor<'_>,
        base: &Self::BaseDescriptor<'_>,
    ) -> vesta::Point {
        self.msm(coeffs.raw, base.raw)
    }
}
