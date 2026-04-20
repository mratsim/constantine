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
# Compile with:
#   nim c -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_kzg_multiproofs_research.nim
#

import
  std/[times, strformat, os],
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/math/polynomials/[polynomials, fft],
  constantine/math/io/io_fields,
  constantine/commitments/kzg_multiproofs,
  constantine/platforms/[abstractions, allocs, bithacks, views],
  constantine/platforms/metering/[reports, tracer],
  helpers/prng_unsafe,
  ../tests/math_polynomials/fft_utils

const
  # FK20 research parameters (matching ethereum-research/kzg_data_availability/fk20_multi.py)
  N = 512                                            # Polynomial size
  L = 16                                             # Coset size
  CDS = (2 * N) div L                                # Extended domain size = 64

type
  TrustedSetupResearch = object
    testPoly: PolynomialCoef[N, Fr[BLS12_381]]
    powers_of_tau_G1: PolynomialCoef[N, EC_ShortW_Aff[Fp[BLS12_381], G1]]
    omegaForFFT: Fr[BLS12_381]

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

  result.testPoly.coefs[0].fromUint(1)
  result.testPoly.coefs[1].fromUint(2)
  result.testPoly.coefs[2].fromUint(3)
  result.testPoly.coefs[3].fromUint(4)
  for i in 4 ..< 8:
    result.testPoly.coefs[i].fromUint(7)
  for i in 8 ..< N:
    result.testPoly.coefs[i].fromUint(13)

  var tau: Fr[BLS12_381]
  tau.fromHex(tauHex)
  result.powers_of_tau_G1.coefs.computePowersOfTauG1(tau)

  result.omegaForFFT = getRootOfUnityForScale(Fr[BLS12_381], int(log2_vartime(uint CDS)))

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1))
rng.seed(seed)
echo "metering FK20 research xoshiro512** seed: ", seed

proc main() =
  resetMetering()

  echo "\n=== FK20 Multiproof Metering (Research Parameters) ==="
  echo fmt"Polynomial size: {N}, Coset size: {L}, CDS: {CDS}"

  echo "Generating research setup (N=512, L=16, CDS=64)..."
  let setup = gen_setup_research()
  echo "Research setup generated successfully\n"

  echo "Creating FFT descriptors..."
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)
  let ecfft_desc = ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]].new(order = CDS, setup.omegaForFFT)
  echo "  - FFT descriptors created\n"

  echo "Computing polyphase spectrum bank..."
  var polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]]

  resetMetering()
  computePolyphaseDecompositionFourier(polyphaseSpectrumBank, setup.powers_of_tau_G1, ecfft_desc)
  echo "Polyphase spectrum bank computed\n"

  const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
  reportCli(Metrics, flags)
  resetMetering()

  var poly: PolynomialCoef[N, Fr[BLS12_381]]
  for i in 0 ..< N:
    poly.coefs[i] = rng.random_unsafe(Fr[BLS12_381])
  echo "Generated random polynomial\n"

  var proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]

  resetMetering()
  kzg_coset_prove[N, L, CDS, BLS12_381](
    proofs,
    poly,
    fr_fft_desc,
    ecfft_desc,
    polyphaseSpectrumBank
  )
  echo "FK20 multiproof computation complete\n"

  reportCli(Metrics, flags)

when isMainModule:
  main()