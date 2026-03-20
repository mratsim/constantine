# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        FK20 Multiproof Metering - Phase Breakdown
#
# ############################################################
#
# This file provides detailed metering of the FK20 algorithm
# to identify the exact bottleneck causing 10x slowdown vs C-kzg.
#
# Compile with:
#   nim c -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_kzg_multiproofs.nim
#

import
  std/[times, monotimes, strformat, os, strutils],
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/math/polynomials/[polynomials, fft_ec],
  constantine/math/matrix/toeplitz,
  constantine/commitments/kzg_multiproofs,
  constantine/commitments_setups/ethereum_kzg_srs,
  constantine/platforms/[abstractions, allocs, bithacks, views, primitives],
  constantine/platforms/metering/[reports, tracer],
  helpers/prng_unsafe,
  constantine/platforms/views  # For .toOpenArray(len) convenience template

const
  # PeerDAS production parameters (from ethereum_kzg_srs)
  N = ethereum_kzg_srs.FIELD_ELEMENTS_PER_BLOB       # 4096
  L = ethereum_kzg_srs.FIELD_ELEMENTS_PER_CELL       # 64
  CDS = ethereum_kzg_srs.CELLS_PER_EXT_BLOB          # 128

  # Trusted setup path (same as benchmarks)
  TrustedSetupMainnet =
    currentSourcePath.rsplit(DirSep, 1)[0] /
    ".." / "constantine" /
    "commitments_setups" /
    "trusted_setup_ethereum_kzg4844_reference.dat"

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1))
rng.seed(seed)
echo "metering FK20 xoshiro512** seed: ", seed

# Random polynomial with fixed seed
proc randomPoly(rng: var RngState): PolynomialCoef[N, Fr[BLS12_381]] =
  for i in 0 ..< N:
    result.coefs[i] = rng.random_unsafe(Fr[BLS12_381])

# Metered FK20 Phase 1 - Toeplitz accumulation loop
proc fk20Phase1Meter*[Name: static Algebra](
  u: var array[CDS, EC_ShortW_Jac[Fp[Name], G1]],
  poly: PolynomialCoef[N, Fr[Name]],
  fr_fft_desc: FrFFT_Descriptor[Fr[Name]],
  ec_fft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]],
  polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]]
) {.meter.} =
  let circulant = allocHeapArrayAligned(Fr[Name], CDS, alignment = 64)

  for offset in 0 ..< L:
    makeCirculantMatrix(circulant.toOpenArray(0, CDS - 1), poly.coefs, offset, L)

    let status = toeplitzMatVecMulPreFFT(
      u.toOpenArray(0, CDS - 1),
      circulant.toOpenArray(0, CDS - 1),
      polyphaseSpectrumBank[offset],
      fr_fft_desc,
      ec_fft_desc,
      accumulate = (offset > 0)
    )
    if status != FFT_Success:
      freeHeapAligned(circulant)
      return

  freeHeapAligned(circulant)

# Metered FK20 Phase 2 - Final FFT
proc fk20Phase2Meter*[Name: static Algebra](
  proofs: var array[CDS, EC_ShortW_Aff[Fp[Name], G1]],
  u: array[CDS, EC_ShortW_Jac[Fp[Name], G1]],
  ec_fft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]]
) {.meter.} =
  let proofsJac = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], CDS, alignment = 64)

  let status = ec_fft_desc.ec_fft_nr(proofsJac.toOpenArray(0, CDS - 1), u.toOpenArray(0, CDS - 1))
  if status != FFT_Success:
    freeHeapAligned(proofsJac)
    return

  proofs.asUnchecked().batchAffine(proofsJac, proofs.len)
  freeHeapAligned(proofsJac)



proc loadTrustedSetup(): ptr EthereumKZGContext =
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "Failed to load trusted setup: " & $tsStatus
  return ctx

proc main() =
  # Initialize metering system FIRST before any metered code runs
  resetMetering()

  echo "\n=== FK20 Multiproof Metering (PeerDAS Parameters) ==="
  echo fmt"Polynomial size: {N}, Coset size: {L}, CDS: {CDS}\n"

  # Load trusted setup
  echo "Loading trusted setup from file..."
  let ctx = loadTrustedSetup()
  if ctx == nil:
    return

  echo "Trusted setup loaded successfully"
  echo fmt"  - Field FFT order: {ctx.fft_desc_ext.order}"
  echo fmt"  - EC FFT order: {ctx.ecfft_desc_ext.order}\n"

  # Generate random polynomial
  var poly = rng.randomPoly()
  echo "Generated random polynomial (seed=", seed, ")\n"

  # Use precomputed polyphase spectrum bank from context (FK20 preprocessing - done ONCE in setup)
  echo "Using precomputed polyphase spectrum bank from context"
  echo fmt"  - Bank size: {L} × {CDS} = {L * CDS} EC points\n"

  # Phase 1: Toeplitz accumulation loop
  echo "=== Phase 1: Toeplitz Accumulation Loop ==="
  var u: array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]
  for i in 0 ..< CDS:
    u[i].setNeutral()

  resetMetering()
  fk20Phase1Meter[BLS12_381](u, poly, ctx.fft_desc_ext, ctx.ecfft_desc_ext, ctx.polyphaseSpectrumBank)
  echo "Phase 1 complete\n"

  const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
  reportCli(Metrics, flags)
  resetMetering()

  echo "\n=== Phase 2: Final FFT ==="
  var proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]

  resetMetering()
  fk20Phase2Meter[BLS12_381](proofs, u, ctx.ecfft_desc_ext)
  echo "Phase 2 complete\n"

  reportCli(Metrics, flags)
  resetMetering()

  echo "\n=== Complete FK20 (End-to-End) ==="
  resetMetering()

  # Re-run Phase 1
  for i in 0 ..< CDS:
    u[i].setNeutral()
  fk20Phase1Meter[BLS12_381](u, poly, ctx.fft_desc_ext, ctx.ecfft_desc_ext, ctx.polyphaseSpectrumBank)

  # Run Phase 2
  fk20Phase2Meter[BLS12_381](proofs, u, ctx.ecfft_desc_ext)

  echo "Complete FK20 computation finished\n"
  reportCli(Metrics, flags)

  # Cleanup
  ctx.trusted_setup_delete()

when isMainModule:
  main()