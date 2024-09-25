//! Constantine
//! Copyright (c) 2018-2019    Status Research & Development GmbH
//! Copyright (c) 2020-Present Mamy André-Ratsimbazafy
//! Licensed and distributed under either of
//!   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
//!   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).

//! To run this benchmark:
//!
//!     cargo bench -- msm

#[macro_use]
extern crate criterion;

use constantine_core::hardware;
use constantine_halo2_zal::CttEngine;

use halo2curves::bn256::{Fr as Scalar, G1Affine as Point};
use halo2curves::ff::Field;
use halo2curves::msm::msm_best;
use halo2curves::zal::MsmAccel;

use rayon::current_thread_index;
use rayon::prelude::{IntoParallelIterator, ParallelIterator};
use rand_core::SeedableRng;
use rand_xorshift::XorShiftRng;

use criterion::{BenchmarkId, Criterion};
use std::time::SystemTime;

const SAMPLE_SIZE: usize = 10;
const SIZES: [u8; 9] = [3, 8, 10, 12, 14, 16, 18, 20, 22];
const SEED: [u8; 16] = [
    0x59, 0x62, 0xbe, 0x5d, 0x76, 0x3d, 0x31, 0x8d, 0x17, 0xdb, 0x37, 0x32, 0x54, 0x06, 0xbc, 0xe5,
];

fn generate_coefficients_and_curvepoints(k: u8) -> (Vec<Scalar>, Vec<Point>) {
    let n: u64 = {
        assert!(k < 64);
        1 << k
    };

    println!("\n\nGenerating 2^{k} = {n} coefficients and curve points..",);
    let timer = SystemTime::now();
    let coeffs = (0..n)
        .into_par_iter()
        .map_init(
            || {
                let mut thread_seed = SEED;
                let uniq = current_thread_index().unwrap().to_ne_bytes();
                assert!(std::mem::size_of::<usize>() == 8);
                for i in 0..uniq.len() {
                    thread_seed[i] += uniq[i];
                    thread_seed[i + 8] += uniq[i];
                }
                XorShiftRng::from_seed(thread_seed)
            },
            |rng, _| Scalar::random(rng),
        )
        .collect();
    let bases = (0..n)
        .into_par_iter()
        .map_init(
            || {
                let mut thread_seed = SEED;
                let uniq = current_thread_index().unwrap().to_ne_bytes();
                assert!(std::mem::size_of::<usize>() == 8);
                for i in 0..uniq.len() {
                    thread_seed[i] += uniq[i];
                    thread_seed[i + 8] += uniq[i];
                }
                XorShiftRng::from_seed(thread_seed)
            },
            |rng, _| Point::random(rng),
        )
        .collect();
    let end = timer.elapsed().unwrap();
    println!(
        "Generating 2^{k} = {n} coefficients and curve points took: {} sec.\n\n",
        end.as_secs()
    );

    (coeffs, bases)
}

fn msm(c: &mut Criterion) {
    let mut group = c.benchmark_group("msm");
    let max_k = *SIZES.iter().max().unwrap_or(&16);
    let (coeffs, bases) = generate_coefficients_and_curvepoints(max_k);

    for k in SIZES {
        group
            .bench_function(BenchmarkId::new("halo2curves", k), |b| {
                assert!(k < 64);
                let n: usize = 1 << k;
                b.iter(|| {
                    msm_best(&coeffs[..n], &bases[..n]);
                })
            })
            .sample_size(SAMPLE_SIZE);

        let engine = CttEngine::new(hardware::get_num_threads_os());
        group
            .bench_function(BenchmarkId::new("constantine", k), |b| {
                assert!(k < 64);
                let n: usize = 1 << k;
                b.iter(|| {
                    engine.msm(&coeffs[..n], &bases[..n]);
                })
            })
            .sample_size(SAMPLE_SIZE);
        drop(engine); // Explicitly drop engine out of timer measurement
    }
    group.finish();
}

criterion_group!(benches, msm);
criterion_main!(benches);
