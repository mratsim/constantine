# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../config/[common, curves],
  ../arithmetic,
  ../primitives,
  ../towers,
  ../ec_shortweierstrass,
  ../io/io_bigints,
  ../isogeny/frobenius

func pow_bls12_381_abs_x[ECP: ECP_ShortW[Fp[BLS12_381], G1] or
       ECP_ShortW[Fp2[BLS12_381], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) =
  ## Does the scalar multiplication [x]P
  ## with x the absolute value of the BLS12 curve parameter
  ## For BLS12_381 [0xd201000000010000]P
  ## Requires r and P to not alias

  # In binary
  # 0b11
  r.double(P)
  r += P
  # 0b1101
  r.double_repeated(2)
  r += P
  # 0b1101001
  r.double_repeated(3)
  r += P
  # 0b1101001000000001
  r.double_repeated(9)
  r += P
  # 0b110100100000000100000000000000000000000000000001
  r.double_repeated(32)
  r += P
  # 0b1101001000000001000000000000000000000000000000010000000000000000
  r.double_repeated(16)

func pow_bls12_381_x[ECP: ECP_ShortW[Fp[BLS12_381], G1] or
       ECP_ShortW[Fp2[BLS12_381], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [x]P
  ## with x the BLS12 curve parameter
  ## For BLS12_381 [-0xd201000000010000]P
  ## Requires r and P to not alias
  pow_bls12_381_abs_x(r, P)
  r.neg()

func pow_bls12_381_minus_x[ECP: ECP_ShortW[Fp[BLS12_381], G1] or
       ECP_ShortW[Fp2[BLS12_381], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [-x]P
  ## with x the BLS12 curve parameter
  ## For BLS12_381 [0xd201000000010000]P
  ## Requires r and P to not alias
  pow_bls12_381_abs_x(r, P)

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

# https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-09#section-8.8
const Cofactor_Eff_BLS12_381_G1 = BigInt[64].fromHex"0xd201000000010001"
  ## P -> (1 - x) P
const Cofactor_Eff_BLS12_381_G2 = BigInt[636].fromHex"0xbc69f08f2ee75b3584c6a0ea91b352888e2a8e9145ad7689986ff031508ffe1329c2f178731db956d82bf015d1212b02ec0ec69d7477c1ae954cbc06689f6a359894c0adebbf6b4e8020005aaa95551"
  ## P -> (x^2 - x - 1) P + (x - 1) ψ(P) + ψ(ψ(2P))

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_381], G1]) {.inline.} =
  ## Clear the cofactor of BLS12_381 G1
  P.scalarMulGeneric(Cofactor_Eff_BLS12_381_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_381], G2]) {.inline.} =
  ## Clear the cofactor of BLS12_381 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_381_G2)

# ############################################################
#
#                Clear Cofactor - Optimized
#
# ############################################################

# BLS12 G1
# ------------------------------------------------------------

func clearCofactorFast*(P: var ECP_ShortW_Prj[Fp[BLS12_381], G1]) =
  ## Clear the cofactor of BLS12_381 G1
  ## 
  ## Wahby et al "Fast and simple constant-time hashing to the BLS12-381 elliptic curve", https://eprint.iacr.org/2019/403
  ## Optimized using endomorphisms
  ## P -> (1 - x) P
  var t{.noInit.}: typeof(P)
  t.pow_bls12_381_minus_x(P) # [-x]P
  P += t                     # [1-x]P

# BLS12 G2
# ------------------------------------------------------------
# From any point on the elliptic curve E2 of a BLS12 curve
# Obtain a point in the G2 prime-order subgroup
#
# Described in https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.4
#
# Implementations, multiple implementations are possible in increasing order of speed:
#
# - The default, canonical, implementation is h_eff * P
# - Scott et al, "Fast Hashing to G2 on Pairing-Friendly Curves", https://doi.org/10.1007/978-3-642-03298-1_8
# - Fuentes-Castaneda et al, "Fast Hashing to G2 on Pairing-Friendly Curves", https://doi.org/10.1007/978-3-642-28496-0_25
# - Budroni et al, "Hashing to G2 on BLS pairing-friendly curves", https://doi.org/10.1145/3313880.3313884
# - Wahby et al "Fast and simple constant-time hashing to the BLS12-381 elliptic curve", https://eprint.iacr.org/2019/403
# - IETF "Hashing to Elliptic Curves", https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.4
#
# In summary, the elliptic curve point multiplication is very expensive,
# the fast methods uses endomorphism acceleration instead.
#
# The method described in Wahby et al is implemented by Riad Wahby
# in C at: https://github.com/kwantam/bls12-381_hash/blob/23c1930039f58606138459557677668fabc8ce39/src/curve2/ops2.c#L106-L204
# following Budroni et al, "Efficient hash maps to G2 on BLS curves"
# https://eprint.iacr.org/2017/419
#
# "P -> [x² - x - 1] P + [x - 1] ψ(P) + ψ(ψ([2]P))"
#
# with Psi (ψ) - untwist-Frobenius-Twist function
# and x the curve BLS parameter

func clearCofactorFast*(P: var ECP_ShortW_Prj[Fp2[BLS12_381], G2]) =
  ## Clear the cofactor of BLS12_381 G2
  ## Optimized using endomorphisms
  ## P -> [x²-x-1]P + [x-1] ψ(P) + ψ²([2]P)

  var xP{.noInit.}, x2P{.noInit.}: typeof(P)

  xP.pow_bls12_381_x(P)   # 1. xP = [x]P
  x2P.pow_bls12_381_x(xP) # 2. x2P = [x²]P

  x2P.diff(x2P, xP)       # 3. x2P = [x²-x]P
  x2P.diff(x2P, P)        # 4. x2P = [x²-x-1]P

  xP.diff(xP, P)          # 5. xP = [x-1]P
  xP.frobenius_psi(xP)    # 6. xP = ψ([x-1]P) = [x-1] ψ(P)

  P.double(P)             # 7. P = [2]P
  P.frobenius_psi(P, k=2) # 8. P = ψ²([2]P)

  P.sum(P, x2P)           # 9. P = [x²-x-1]P + ψ²([2]P)
  P.sum(P, xP)            # 10. P = [x²-x-1]P + [x-1] ψ(P) + ψ²([2]P)
