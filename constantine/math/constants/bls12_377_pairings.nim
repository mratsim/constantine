# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../io/io_bigints,
  ../extension_fields,
  ../elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_projective],
  ../pairings/[cyclotomic_subgroups, miller_loops],
  ../isogenies/frobenius

# Slow generic implementation
# ------------------------------------------------------------

# The bit count must be exact for the Miller loop
const BLS12_377_pairing_ate_param* = block:
  # BLS12 Miller loop is parametrized by u
  BigInt[64].fromHex"0x8508c00000000001"

const BLS12_377_pairing_ate_param_isNeg* = false

const BLS12_377_pairing_finalexponent* = block:
  # (p^12 - 1) / r * 3
  BigInt[4271].fromHex"0x518fe3a450394da01ed0ec73865aed18d4251c557c299312d07b5d31105598be5439b32fda943a26e8d85c306e6c1941dd3f9d646d87211c240f5489c67b1a8663c49da97a2880dc48213527e51d370acd05663ffda035ca31c4ba994c89d66c0c97066502f8ef19bb008e047c24cf96e02493f4683ffdc39075cc1c01df9fd0ec1dc0419176c010ac1a83b777201a77f8dab474e99c59ae840de7362f7c231d500aecc1eb52616067540d419f7f9fbfd22831919b4ac04960703d9753698941c95aa2d2a04f4bf26de9d191661a013cbb09227c09424595e2639ae94d35ce708bdec2c10628eb4f981945698ef049502d2a71994fab9898c028c73dd021f13208590be27e78f0f18a88f5ffe40157a9e9fef5aa229c0aa7fdb16a887af2c4a486258bf11fb1a5d945707a89d7bf8f67e5bb28f76a460d9a1e660cbbe91bfc456b8789d5bae1dba8cbef5b03bcd0ea30f6a7b45218292b2bf3b20ed5937cb5e2250eee395821805c6383d0286c7423beb42e79f85dab2a36df8fd154f2d89e5e9aaadaaa00e0a29ecc6e329195761d6063e0a2e136a3fb7671c9134c970a8588a7f3144642a10a5af77c105f5e90987f28c6604c5dcb604c02f7d642f7f819eea6fadb8aace7c4e146a17dab2c644d4372c6979845f261b4a20cd88a20325e0c0fc806bd9f60a8502fa8f466b6919311e232e06fd6a861cb5dc24d69274c7e631cac6b93e0254460d445a0000012b53b000000000000"

# Addition chains
# ------------------------------------------------------------
#
# u = 0x8508c00000000001
# Ate BLS |u|
# hex: 0x8508c00000000001
# bin: 0b1000010100001000110000000000000000000000000000000000000000000001
#
# 71 naive operations to build a naive addition chain
# or 68 with optimizations, though unsure how to use them in the Miller Loop
# and for multi-pairing it would use too much temporaries anyway.

func millerLoopAddchain*(
       f: var Fp12[BLS12_377],
       Q: ECP_ShortW_Aff[Fp2[BLS12_377], G2],
       P: ECP_ShortW_Aff[Fp[BLS12_377], G1]
     ) =
  ## Miller Loop for BLS12-377 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter

  var T {.noInit.}: ECP_ShortW_Prj[Fp2[BLS12_377], G2]

  f.miller_init_double_then_add(T, Q, P, 5)                # 0b100001
  f.miller_accum_double_then_add(T, Q, P, 2)               # 0b10000101
  f.miller_accum_double_then_add(T, Q, P, 5)               # 0b1000010100001
  f.miller_accum_double_then_add(T, Q, P, 4)               # 0b10000101000010001
  f.miller_accum_double_then_add(T, Q, P, 1)               # 0b100001010000100011
  f.miller_accum_double_then_add(T, Q, P, 46, add = true)  # 0b1000010100001000110000000000000000000000000000000000000000000001

func millerLoopAddchain*(
       f: var Fp12[BLS12_377],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[Fp2[BLS12_377], G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[Fp[BLS12_377], G1]],
       N: int
     ) {.noInline.} =
  ## Miller Loop for BLS12-377 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter

  var Ts = allocStackArray(ECP_ShortW_Prj[Fp2[BLS12_377], G2], N)

  f.miller_init_double_then_add( Ts, Qs, Ps, N, 5)               # 0b100001
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 2)               # 0b10000101
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 5)               # 0b1000010100001
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 4)               # 0b10000101000010001
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 1)               # 0b100001010000100011
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 46, add = true)  # 0b1000010100001000110000000000000000000000000000000000000000000001

func cycl_exp_by_curve_param*(r: var Fp12[BLS12_377], a: Fp12[BLS12_377], invert = BLS12_377_pairing_ate_param_isNeg) =
  ## f^x with x the curve parameter
  ## For BLS12_377 f^0x8508c00000000001
  r.cycl_sqr_repeated(a, 5)
  r *= a
  let t{.noInit.} = r
  r.cycl_sqr_repeated(7)
  r *= t
  r.cycl_sqr_repeated(4)
  r *= a
  r.cyclotomic_square()
  r *= a

  r.cyclotomic_exp_compressed(r, [46])
  r *= a

  if invert:
    r.cyclotomic_inv()

func isInPairingSubgroup*(a: Fp12[BLS12_377]): SecretBool =
  ## Returns true if a is in GT subgroup, i.e. a is an element of order r
  ## Warning ⚠: Assumes that a is in the cyclotomic subgroup
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #   a is in the GT subgroup iff a^p == a^u
  var t0{.noInit.}, t1{.noInit.}: Fp12[BLS12_377]
  t0.frobenius_map(a)
  t1.cycl_exp_by_curve_param(a)

  return t0 == t1