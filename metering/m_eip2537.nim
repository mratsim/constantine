# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/times,
  constantine/platforms/metering/[reports, tracer],
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/named/zoo_subgroups,
  constantine/math/pairings/pairings_generic,
  constantine/platforms/abstractions,
  # Helpers
  helpers/prng_unsafe

# Metering for EIP-2537
# -------------------------------------------------------------------------------
#
# https://eips.ethereum.org/EIPS/eip-2537
#
# Compile with
#
#  nim c --cc:clang -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_eip2537.nim

var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

func random_point*(rng: var RngState, EC: typedesc[EC_ShortW_Aff]): EC {.noInit.} =
  var jac = rng.random_unsafe(EC_ShortW_Jac[EC.F, EC.G])
  jac.clearCofactor()
  result.affine(jac)

func random_point*(rng: var RngState, EC: typedesc[EC_ShortW_Jac or EC_ShortW_Prj]): EC {.noInit.} =
  var P = rng.random_unsafe(EC)
  P.clearCofactor()
  result = P

type
  G1aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
  G2aff = EC_ShortW_Aff[Fp2[BLS12_381], G2]
  G1jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
  G2jac = EC_ShortW_Jac[Fp2[BLS12_381], G2]
  G1prj = EC_ShortW_Prj[Fp[BLS12_381], G1]
  G2prj = EC_ShortW_Prj[Fp2[BLS12_381], G2]

proc g1addMeter(EC: typedesc) =
  let
    P = rng.random_point(EC)
    Q = rng.random_point(EC)

  var r: EC
  resetMetering()
  r.sum(P, Q)

proc g2addMeter(EC: typedesc) =
  let
    P = rng.random_point(EC)
    Q = rng.random_point(EC)

  var r: EC
  resetMetering()
  r.sum(P, Q)

proc g1mulCTMeter(EC: typedesc) =
  let
    P = rng.random_point(EC)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul(n)

proc g1mulVartimeMeter(EC: typedesc) =
  let
    P = rng.random_point(EC)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul_vartime(n)

proc g2mulCTMeter(EC: typedesc) =
  let
    P = rng.random_point(EC)
    k = rng.random_unsafe(Fr[BLS12_381])

  var r = P
  let n = k.toBig()
  resetMetering()
  r.scalarMul(n)

proc g2mulVartimeMeter(EC: typedesc) =
  let
    P = rng.random_point(EC)
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

#################################################

echo "\n\n## G1 add jacobian - constant-time"
g1addMeter(G1jac)
reportCli(Metrics, flags)

echo "\n\n## G1 add projective - constant-time"
g1addMeter(G1prj)
reportCli(Metrics, flags)

#################################################

echo "\n\n## G1 mul jacobian - constant-time"
g1mulCTMeter(G1jac)
reportCli(Metrics, flags)

echo "\n\n## G1 mul projective - constant-time"
g1mulCTMeter(G1prj)
reportCli(Metrics, flags)

echo "\n\n## G1 mul jacobian - variable-time"
g1mulVartimeMeter(G1jac)
reportCli(Metrics, flags)

echo "\n\n## G1 mul projective - variable-time"
g1mulVartimeMeter(G1prj)
reportCli(Metrics, flags)

#################################################

echo "\n\n## G2 add jacobian - constant-time"
g2addMeter(G2jac)
reportCli(Metrics, flags)

echo "\n\n## G2 add projective - constant-time"
g2addMeter(G2prj)
reportCli(Metrics, flags)

#################################################

echo "\n\n## G2 mul jacobian - constant-time"
g2mulCTMeter(G2jac)
reportCli(Metrics, flags)

echo "\n\n## G2 mul projective - constant-time"
g2mulCTMeter(G2prj)
reportCli(Metrics, flags)

echo "\n\n## G2 mul jacobian - variable-time"
g2mulVartimeMeter(G2jac)
reportCli(Metrics, flags)

echo "\n\n## G2 mul projective - variable-time"
g2mulVartimeMeter(G2prj)
reportCli(Metrics, flags)

#################################################

echo "\n\n## Pairing"
pairingMeter()
reportCli(Metrics, flags)
