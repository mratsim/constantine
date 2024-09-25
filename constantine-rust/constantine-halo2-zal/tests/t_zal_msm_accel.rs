//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
//! at your option. This file may not be copied, modified, or distributed except according to those terms.

use constantine_core::hardware;
use constantine_halo2_zal::CttEngine;

use ark_std::{end_timer, start_timer};
use rand_core::OsRng;

use halo2_middleware::halo2curves::bn256;
use halo2_middleware::halo2curves::ff::Field;
use halo2_middleware::halo2curves::group::prime::PrimeCurveAffine;
use halo2_middleware::halo2curves::group::{Curve, Group};
use halo2_middleware::halo2curves::msm::msm_best;
use halo2_middleware::zal::traits::MsmAccel;

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
        let e0 = msm_best(scalars, points);
        end_timer!(t0);

        let engine = CttEngine::new(hardware::get_num_threads_os());
        let t1 = start_timer!(|| format!("CttEngine msm k={}", k));
        let e1 = engine.msm(scalars, points);
        end_timer!(t1);

        assert_eq!(e0, e1);

        // Caching API
        // -----------
        let t2 = start_timer!(|| format!("CttEngine msm cached base k={}", k));
        let base_descriptor = engine.get_base_descriptor(points);
        let e2 = engine.msm_with_cached_base(scalars, &base_descriptor);
        end_timer!(t2);

        assert_eq!(e0, e2)
    }
}

#[test]
fn t_msm_zal() {
    run_msm_zal(3, 14);
}
