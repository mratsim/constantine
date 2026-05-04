# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#          KZG Multiproof Benchmarks (PeerDAS EIP-7594)
#
# ############################################################
#
# Benchmarks for kzg_coset_prove_naive and kzg_coset_prove (FK20)
# using Ethereum PeerDAS parameters: N=4096, L=64, CDS=128
#

import
  # Benchmark infrastructure
  ./bench_blueprint,
  # Trusted setup
  constantine/commitments_setups/ethereum_kzg_srs,
  # Functions being benched
  constantine/commitments/kzg_multiproofs,
  constantine/math/matrix/toeplitz,
  # Math types
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, polynomials/polynomials, polynomials/fft_ec],
  # PRNG for polynomial generation
  helpers/prng_unsafe,
  # Standard library
  std/[os, strutils, monotimes, importutils]

const
  # PeerDAS production parameters (from ethereum_kzg_srs)
  N = ethereum_kzg_srs.FIELD_ELEMENTS_PER_BLOB       # 4096
  L = ethereum_kzg_srs.FIELD_ELEMENTS_PER_CELL       # 64
  CDS = ethereum_kzg_srs.CELLS_PER_EXT_BLOB          # 128

  # Trusted setup path
  TrustedSetupMainnet =
    currentSourcePath.rsplit(DirSep, 1)[0] /
    ".." / "constantine" /
    "commitments_setups" /
    "trusted_setup_ethereum_kzg4844_reference.dat"

  # Benchmark iterations
  ItersFK20 = 10
  ItersNaive = 3
  ItersComponents = 50
  ItersPolyphase = 3

  # Random seed for reproducibility
  RngSeed = 42

proc generateTestPoly(): PolynomialCoef[N, Fr[BLS12_381]] =
  ## Generate random polynomial using PRNG with fixed seed
  var rng: RngState
  rng.seed(RngSeed)

  rng.random_unsafe(result.coefs)

proc loadTrustedSetup(): ptr EthereumKZGContext =
  ## Load trusted setup from file
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "Failed to load trusted setup: " & $tsStatus
  return ctx

proc report(op: string, size: int, startTime, stopTime: MonoTime,
            startClk, stopClk: int64, iters: int) =
  ## Report benchmark results in standard format
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} size {size:>5}    {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles"
  else:
    echo &"{op:<60} size {size:>5}    {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, size: int, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, size, startTime, stopTime, startClk, stopClk, iters)

proc benchPolyphasePrecomputation(srs_monomial_g1: PolynomialCoef[N, EC_ShortW_Aff[Fp[BLS12_381], G1]],
                                   ecfft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]],
                                   iters: int) =
  ## Measure one-time polyphase spectrum bank computation cost
  ## This runs once during trusted setup initialization

  let polyphaseSpectrumBank = allocHeapAligned(array[L, array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]], 64)
  defer: freeHeapAligned(polyphaseSpectrumBank)

  bench("computePolyphaseDecompositionFourier", CDS*L, iters):
    computePolyphaseDecompositionFourier(polyphaseSpectrumBank[], srs_monomial_g1, ecfft_desc)
proc benchFK20_Phase1_Full(ctx: ptr EthereumKZGContext,
                           poly: PolynomialCoef[N, Fr[BLS12_381]],
                           iters: int) =
  ## Complete FK20 Phase 1: 64 iterations of ToeplitzAccumulator accumulate+finish
  ## This is the main FK20 proving loop

  var u: array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]

  # Type aliases matching ToeplitzAccumulator
  type BLS12_381_G1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
  type BLS12_381_G1_jac = EC_ShortW_Jac[Fp[BLS12_381], G1]

  # Allow direct access to private 'offset' field for benchmark reuse
  privateAccess(toeplitz.ToeplitzAccumulator)

  # Initialize accumulator once outside the benchmark loop to avoid
  # allocation overhead (3 x allocHeapAligned, ~772 KB total) in timing.
  var accum: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, Fr[BLS12_381]]
  doAssert accum.init(ctx.fft_desc_ext, ctx.ecfft_desc_ext, CDS, L) == Toeplitz_Success

  bench("fk20_phase1_accumulation_loop", CDS, iters):
    # Reset accumulator state for this iteration (avoids free+alloc)
    accum.offset = 0
    var circulant: array[CDS, Fr[BLS12_381]]
    for offset in 0 ..< L:
      makeCirculantMatrix(circulant, poly.coefs, offset, L)
      doAssert accum.accumulate(circulant) == Toeplitz_Success
    doAssert accum.finish(u, ctx.polyphaseSpectrumBank) == Toeplitz_Success

proc benchFK20_Phase2(u: var array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]],
                      ecfft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]],
                      iters: int) =
  ## Final EC FFT to get proofs (size 128)

  var proofsJac: array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]

  bench("fk20_phase2_final_ec_fft", CDS, iters):
    let status = ecfft_desc.ec_fft_nr(proofsJac, u)
    doAssert status == FFT_Success

proc benchKZGCosetProve_FK20(ctx: ptr EthereumKZGContext,
                             poly: PolynomialCoef[N, Fr[BLS12_381]],
                             iters: int) =
  ## Complete FK20 proving (kzg_coset_prove)
  ## Excludes polyphase precomputation (already in ctx.polyphaseSpectrumBank)

  var proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]

  bench("kzg_coset_prove_fk20", CDS, iters):
    kzg_coset_prove(
      proofs,
      poly.coefs,
      ctx.fft_desc_ext,
      ctx.ecfft_desc_ext,
      ctx.polyphaseSpectrumBank
    )

proc benchKZGCosetProve_Naive(ctx: ptr EthereumKZGContext,
                              poly: PolynomialCoef[N, Fr[BLS12_381]],
                              iters: int) =
  ## Naive O(n²) KZG multiproof proving (kzg_coset_prove_naive)
  ## Benchmark single coset proof

  var proof: EC_ShortW_Aff[Fp[BLS12_381], G1]
  let h = ctx.domain_brp.rootsOfUnity[0]  # First coset shift

  bench("kzg_coset_prove_naive", L, iters):
    kzg_coset_prove_naive[N, BLS12_381](
      proof,
      poly,
      h,
      L,
      ctx.srs_monomial_g1
    )

proc main() =
  echo "KZG Multiproof Benchmarks (PeerDAS EIP-7594)"
  echo "N=4096, L=64, CDS=128"
  echo "Random polynomial with seed=", RngSeed
  echo ""

  # Load trusted setup
  echo "Loading trusted setup..."
  let ctx = loadTrustedSetup()
  echo "Trusted setup loaded successfully\n"

  # Generate test polynomial
  echo "Generating test polynomial..."
  let poly = generateTestPoly()
  echo "Test polynomial generated\n"

  separator(145)
  echo "Polyphase Precomputation (One-Time Setup Cost)"
  separator(145)
  benchPolyphasePrecomputation(ctx.srs_monomial_g1, ctx.ecfft_desc_ext, ItersPolyphase)
  echo ""

  separator(145)
  echo "FK20 Phase 1 - Toeplitz Accumulation Loop"
  separator(145)
  benchFK20_Phase1_Full(ctx, poly, ItersComponents)
  echo ""

  separator(145)
  echo "FK20 Phase 2 - Final EC FFT"
  separator(145)
  var u {.noInit.}: array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]
  # Initialize u with dummy data
  for i in 0 ..< CDS:
    u[i].setNeutral()
  benchFK20_Phase2(u, ctx.ecfft_desc_ext, ItersComponents)
  echo ""

  separator(145)
  echo "Complete FK20 Proving"
  separator(145)
  benchKZGCosetProve_FK20(ctx, poly, ItersFK20)
  echo ""

  separator(145)
  echo "Naive O(n²) Proving"
  separator(145)
  benchKZGCosetProve_Naive(ctx, poly, ItersNaive)
  echo ""

  separator(145)
  echo "Summary"
  separator(145)
  echo "FK20 vs Naive speedup: O(n log n) vs O(n²)"
  echo "Note: Polyphase precomputation is a one-time cost, excluded from FK20 timing"

  ctx.trusted_setup_delete()

when isMainModule:
  main()