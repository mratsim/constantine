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
  std/[times, strformat],
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/math/polynomials/[polynomials, fft_fields, fft_ec],
  constantine/commitments/kzg_multiproofs,
  constantine/platforms/[abstractions, allocs, bithacks, views],
  constantine/platforms/metering/[reports, tracer],
  helpers/prng_unsafe,
  ../tests/commitments/trusted_setup_generator,
  ../tests/math_polynomials/fft_utils

const
  # FK20 research parameters (matching ethereum-research/kzg_data_availability/fk20_multi.py)
  N = 512                                            # Polynomial size
  L = 16                                             # Coset size
  CDS = (2 * N) div L                                # Extended domain size = 64
  maxWidth = CDS * (N div L)                         # Full domain size = 2048

proc main() =
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1))
  rng.seed(seed)
  echo "metering FK20 research xoshiro512** seed: ", seed

  resetMetering()

  echo "\n=== FK20 Multiproof Metering (Research Parameters) ==="
  echo fmt"Polynomial size: {N}, Coset size: {L}, CDS: {CDS}, maxWidth: {maxWidth}"

  echo "Generating research setup (N=512, L=16, CDS=64)..."
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"
  let setup = gen_setup(N, L, maxWidth, tauHex)
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
  kzg_coset_prove[L, CDS, BLS12_381](
    proofs,
    poly.coefs,
    fr_fft_desc,
    ecfft_desc,
    polyphaseSpectrumBank
  )
  echo "FK20 multiproof computation complete\n"

  reportCli(Metrics, flags)

when isMainModule:
  main()