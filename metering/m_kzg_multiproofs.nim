# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        FK20 Multiproof Metering - PeerDAS Parameters
#
# ############################################################
#
# Compile with:
#   nim c -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_kzg_multiproofs.nim
#

import
  std/[times, strformat, os, strutils],
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/math/polynomials/[polynomials, fft_fields, fft_ec],
  constantine/commitments/kzg_multiproofs,
  constantine/commitments_setups/ethereum_kzg_srs,
  constantine/platforms/[abstractions, allocs, bithacks, views],
  constantine/platforms/metering/[reports, tracer],
  helpers/prng_unsafe

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

proc randomPoly(rng: var RngState): PolynomialCoef[N, Fr[BLS12_381]] =
  for i in 0 ..< N:
    result.coefs[i] = rng.random_unsafe(Fr[BLS12_381])

proc loadTrustedSetup(): ptr EthereumKZGContext =
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "Failed to load trusted setup: " & $tsStatus
  return ctx

proc main() =
  resetMetering()

  echo "\n=== FK20 Multiproof Metering (PeerDAS Parameters) ==="
  echo fmt"Polynomial size: {N}, Coset size: {L}, CDS: {CDS}"

  echo "Loading trusted setup from file..."
  let ctx = loadTrustedSetup()
  if ctx == nil:
    return

  echo "Trusted setup loaded successfully"
  echo fmt"  - Field FFT order: {ctx.fft_desc_ext.order}"
  echo fmt"  - EC FFT order: {ctx.ecfft_desc_ext.order}\n"

  var poly = rng.randomPoly()
  echo "Generated random polynomial (seed=", seed, ")\n"

  echo "Using precomputed polyphase spectrum bank from context"
  echo fmt"  - Bank size: {L} × {CDS} = {L * CDS} EC points\n"

  var proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]

  resetMetering()
  kzg_coset_prove[L, CDS, BLS12_381](
    proofs,
    poly.coefs,
    ctx.fft_desc_ext,
    ctx.ecfft_desc_ext,
    ctx.polyphaseSpectrumBank
  )
  echo "FK20 multiproof computation complete\n"

  const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
  reportCli(Metrics, flags)

  ctx.trusted_setup_delete()

when isMainModule:
  main()