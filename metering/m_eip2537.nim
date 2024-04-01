# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/times,
  ../constantine/platforms/metering/[reports, tracer],
  ../constantine/math/config/curves,
  ../constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  ../constantine/math/constants/zoo_subgroups,
  ../constantine/math/pairings/pairings_generic,
  ../constantine/platforms/abstractions,
  # Helpers
  ../helpers/prng_unsafe

# Metering for EIP-2537
# -------------------------------------------------------------------------------
#
# https://eips.ethereum.org/EIPS/eip-2537
#
# Compile with
#
#  nim c -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_eip2537.nim

var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

func random_point*(rng: var RngState, EC: typedesc[ECP_ShortW_Aff]): EC {.noInit.} =
  var jac = rng.random_unsafe(ECP_ShortW_Jac[EC.F, EC.G])
  jac.clearCofactor()
  result.affine(jac)

func random_point*(rng: var RngState, EC: typedesc[ECP_ShortW_Jac]): EC {.noInit.} =
  var jac = rng.random_unsafe(EC)
  jac.clearCofactor()
  result = jac

type
  G1aff = ECP_ShortW_Aff[Fp[BLS12_381], G1]
  G2aff = ECP_ShortW_Aff[Fp2[BLS12_381], G2]
  G1jac = ECP_ShortW_Jac[Fp[BLS12_381], G1]
  G2jac = ECP_ShortW_Jac[Fp2[BLS12_381], G2]

proc g1addMeter() =
  let
    P = rng.random_point(G1jac)
    Q = rng.random_point(G1jac)

  var r: G1jac
  resetMetering()
  r.sum(P, Q)

proc g2addMeter() =
  let
    P = rng.random_point(G2jac)
    Q = rng.random_point(G2jac)

  var r: G2jac
  resetMetering()
  r.sum(P, Q)

proc g1mulCTMeter() =
  let
    P = rng.random_point(G1jac)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul_vartime(n)

proc g1mulVartimeMeter() =
  let
    P = rng.random_point(G1jac)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul_vartime(n)

proc g2mulCTMeter() =
  let
    P = rng.random_point(G2jac)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul(n)

proc g2mulVartimeMeter() =
  let
    P = rng.random_point(G2jac)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul_vartime(n)

proc pairingMeter() =
  let
    P = rng.random_point(G1aff)
    Q = rng.random_point(G2aff)

  var f: Fp12[BLS12_381]

  resetMetering()
  f.pairing(P, Q)

######################################################

const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
resetMetering()

echo "\n\nG1 add - constant-time"
echo "========================================="
g1addMeter()
reportCli(Metrics, flags)

echo "\n\nG1 mul - constant-time"
echo "========================================="
g1mulCTMeter()
reportCli(Metrics, flags)

echo "\n\nG1 mul - variable-time"
echo "========================================="
g1mulVartimeMeter()
reportCli(Metrics, flags)

echo "\n\nG2 add - constant-time"
echo "========================================="
g2addMeter()
reportCli(Metrics, flags)

echo "\n\nG2 mul - constant-time"
echo "========================================="
g2mulCTMeter()
reportCli(Metrics, flags)

echo "\n\nG2 mul - variable-time"
echo "========================================="
g2mulVartimeMeter()
reportCli(Metrics, flags)

echo "\n\nPairing"
echo "========================================="
pairingMeter()
reportCli(Metrics, flags)
