# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        FK20 Multiproof Metering - Research Parameters
#
# ############################################################
#
# This file meters FK20 with research parameters matching
# ethereum-research/kzg_data_availability/fk20_multi.py
#
# Expected: ~1472 G1 multiplications for N=512, L=16
#
# Compile with:
#   nim c -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_kzg_multiproofs_research.nim
#

import
  std/[times, monotimes, strformat, os, strutils],
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/math/polynomials/[polynomials, fft],
  constantine/math/matrix/toeplitz,
  constantine/math/io/io_fields,
  constantine/commitments/kzg_multiproofs,
  constantine/platforms/[abstractions, allocs, bithacks, views, primitives],
  constantine/platforms/metering/[reports, tracer],
  helpers/prng_unsafe,
  constantine/platforms/views

const
  # FK20 research parameters (matching ethereum-research/kzg_data_availability/fk20_multi.py)
  N = 512                                            # Polynomial size (matches Python N_POINTS)
  L = 16                                             # Coset size (matches Python l=16)
  # CDS = 2 * N / L to satisfy: CDS * L == 2 * N (from computePolyphaseDecompositionFourier assertion)
  CDS = (2 * N) div L                                # Extended domain size = 64
  maxWidth = N                                       # Full domain size = 512

type
  TrustedSetupResearch = object
    testPoly: PolynomialCoef[N, Fr[BLS12_381]]
    powers_of_tau_G1: PolynomialCoef[N, EC_ShortW_Aff[Fp[BLS12_381], G1]]
    omegaForFFT: Fr[BLS12_381]
  
  FK20PolyphaseSpectrumBankResearch = array[L, array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]]

# Metered FK20 Phase 1 - Toeplitz accumulation loop (FIXED: accumulate in Fourier domain)
proc fk20Phase1Meter*[Name: static Algebra](
  u: var array[CDS, EC_ShortW_Jac[Fp[Name], G1]],
  poly: PolynomialCoef[N, Fr[Name]],
  fr_fft_desc: FrFFT_Descriptor[Fr[Name]],
  ec_fft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]],
  polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]]
) {.meter.} =
  let circulant = allocHeapArrayAligned(Fr[Name], CDS, alignment = 64)
  
  # Accumulate in Fourier domain (matching Python/C-kzg/Go-kzg)
  let hext_fft = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], CDS, alignment = 64)
  for i in 0 ..< CDS:
    hext_fft[i].setNeutral()
  
  for offset in 0 ..< L:
    makeCirculantMatrix(circulant.toOpenArray(0, CDS - 1), poly.coefs, offset, L)
    
    # Accumulate Hadamard product in Fourier domain (NO IFFT yet!)
    let status = toeplitzHadamardProductPreFFT(
      hext_fft.toOpenArray(0, CDS - 1),
      circulant.toOpenArray(0, CDS - 1),
      polyphaseSpectrumBank[offset],
      fr_fft_desc,
      accumulate = (offset > 0)
    )
    if status != FFT_Success:
      freeHeapAligned(circulant)
      freeHeapAligned(hext_fft)
      return
  
  # ONE IFFT at the end (matching Python/C-kzg/Go-kzg)
  let status2 = ec_ifft_rn(ec_fft_desc, u.toOpenArray(0, CDS - 1), hext_fft.toOpenArray(0, CDS - 1))
  freeHeapAligned(hext_fft)
  freeHeapAligned(circulant)
  if status2 != FFT_Success:
    return

# Minimal setup generation without fft_utils dependency
func computePowersOfTauG1(powers_of_tau: var array[N, EC_ShortW_Aff[Fp[BLS12_381], G1]], secret: Fr[BLS12_381]) =
  var prev {.noInit.}: EC_ShortW_Jac[Fp[BLS12_381], G1]
  prev.setGenerator()
  powers_of_tau[0].affine(prev)
  let secretBig = secret.toBig()
  for i in 1 ..< N:
    var next {.noInit.}: EC_ShortW_Jac[Fp[BLS12_381], G1]
    next.scalarMul_vartime(secretBig, prev)
    powers_of_tau[i].affine(next)
    prev = next

func gen_setup_research(): TrustedSetupResearch =
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"
  
  # Polynomial coefficients: [1, 2, 3, 4, 7, 7, 7, 7, 13, 13, ...]
  result.testPoly.coefs[0].fromUint(1)
  result.testPoly.coefs[1].fromUint(2)
  result.testPoly.coefs[2].fromUint(3)
  result.testPoly.coefs[3].fromUint(4)
  for i in 4 ..< 8:
    result.testPoly.coefs[i].fromUint(7)
  for i in 8 ..< N:
    result.testPoly.coefs[i].fromUint(13)
  
  # Powers of tau
  var tau: Fr[BLS12_381]
  tau.fromHex(tauHex)
  result.powers_of_tau_G1.coefs.computePowersOfTauG1(tau)
  
  # FFT root - CDS-th root of unity
  # Using precomputed value from ethereum_kzg_srs for scale=6 (CDS=64, 2^6=64)
  result.omegaForFFT = Fr[BLS12_381].fromHex("0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53")

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1))
rng.seed(seed)
echo "metering FK20 research xoshiro512** seed: ", seed

# Random polynomial with fixed seed
proc randomPoly(rng: var RngState): PolynomialCoef[N, Fr[BLS12_381]] =
  for i in 0 ..< N:
    result.coefs[i] = rng.random_unsafe(Fr[BLS12_381])

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

proc main() =
  # Initialize metering system FIRST before any metered code runs
  resetMetering()
  
  echo "\n=== FK20 Multiproof Metering (Research Parameters) ==="
  echo fmt"Polynomial size: {N}, Coset size: {L}, CDS: {CDS}"
  echo fmt"Expected G1 multiplications: ~{L * CDS + CDS * 2} (matching Python FK20)\n"
  
  # Generate research setup (matching Python FK20)
  echo "Generating research setup (N=512, L=16, CDS=64)..."
  let setup = gen_setup_research()
  echo "Research setup generated successfully"
  echo "  - FFT omega: ", setup.omegaForFFT.toHex()
  echo fmt"  - Domain size: {maxWidth}\n"
  
  # Create FFT descriptors for research parameters
  echo "Creating FFT descriptors..."
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)
  echo "  - Fr FFT descriptor created, order: ", fr_fft_desc.order
  let ecfft_desc = ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]].new(order = CDS, setup.omegaForFFT)
  echo "  - EC FFT descriptor created, order: ", ecfft_desc.order
  
  # Generate random polynomial
  echo "\nGenerating random polynomial..."
  var poly = rng.randomPoly()
  echo "Generated random polynomial (seed=", seed, ")\n"
  
  # Compute polyphase spectrum bank (FK20 preprocessing - done ONCE in setup)
  echo "Computing polyphase spectrum bank..."
  echo "  - powers_of_tau_G1 length: ", setup.powers_of_tau_G1.coefs.len
  echo "  - L: ", L, ", CDS: ", CDS
  stdout.flushFile()
  var polyphaseSpectrumBank: FK20PolyphaseSpectrumBankResearch
  
  resetMetering()
  echo "  - Calling computePolyphaseDecompositionFourier..."
  stdout.flushFile()
  computePolyphaseDecompositionFourier(polyphaseSpectrumBank, setup.powers_of_tau_G1, ecfft_desc)
  echo "Polyphase spectrum bank computed\n"
  echo fmt"  - Bank size: {L} × {CDS} = {L * CDS} EC points\n"
  stdout.flushFile()
  
  const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
  reportCli(Metrics, flags)
  resetMetering()
  
  # Phase 1: Toeplitz accumulation loop
  echo "=== Phase 1: Toeplitz Accumulation Loop ==="
  var u: array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]
  for i in 0 ..< CDS:
    u[i].setNeutral()
  
  resetMetering()
  fk20Phase1Meter[BLS12_381](u, poly, fr_fft_desc, ecfft_desc, polyphaseSpectrumBank)
  echo "Phase 1 complete\n"
  
  reportCli(Metrics, flags)
  resetMetering()
  
  echo "\n=== Phase 2: Final FFT ==="
  var proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  
  resetMetering()
  fk20Phase2Meter[BLS12_381](proofs, u, ecfft_desc)
  echo "Phase 2 complete\n"
  
  reportCli(Metrics, flags)
  resetMetering()
  
  echo "\n=== Complete FK20 (End-to-End) ==="
  resetMetering()
  
  # Re-run Phase 1
  for i in 0 ..< CDS:
    u[i].setNeutral()
  fk20Phase1Meter[BLS12_381](u, poly, fr_fft_desc, ecfft_desc, polyphaseSpectrumBank)
  
  # Run Phase 2
  fk20Phase2Meter[BLS12_381](proofs, u, ecfft_desc)
  
  echo "Complete FK20 computation finished\n"
  reportCli(Metrics, flags)

when isMainModule:
  main()