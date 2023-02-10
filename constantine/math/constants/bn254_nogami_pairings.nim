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
const BN254_Nogami_pairing_ate_param* = block:
  # BN Miller loop is parametrized by 6u+2
  BigInt[65].fromHex"0x18300000000000004"

const BN254_Nogami_pairing_ate_param_isNeg* = true

const BN254_Nogami_pairing_finalexponent* = block:
  # (p^12 - 1) / r
  BigInt[2786].fromHex"0x2928fbb36b391596ee3fe4cbe857330da83e46fedf04d235a4a8daf5ff9f6eabcb4e3f20aa06f0a0d96b24f9af0cbbce750d61627dcbf5fec9139b8f1c46c86b49b4f8a202af26e4504f2c0f56570e9bd5b94c403f385d1908556486e24b396ddc2cdf13d06542f84fe8e82ccbad7b7423fc1ef4e8cc73d605e3e867c0a75f45ea7f6356d9846ce35d5a34f30396938818ad41914b97b99c289a7259b5d2e09477a77bd3c409b19f19e893f8ade90b0aed1b5fc8a07a3cebb41d4e9eee96b21a832ddb1e93e113edfb704fa532848c18593cd0ee90444a1b3499a800177ea38bdec62ec5191f2b6bbee449722f98d2173ad33077545c2ad10347e125a56fb40f086e9a4e62ad336a72c8b202ac3c1473d73b93d93dc0795ca0ca39226e7b4c1bb92f99248ec0806e0ad70744e9f2238736790f5185ea4c70808442a7d530c6ccd56b55a6973867ec6c73599bbd020bbe105da9c6b5c009ad8946cd6f0"

# Addition chains
# ------------------------------------------------------------
#
# u = -0x4080000000000001
# Ate BN |6u+2|
# hex: 0x18300000000000004
# bin: 0x11000001100000000000000000000000000000000000000000000000000000100

func millerLoopAddchain*(
       f: var Fp12[BN254_Nogami],
       Q: ECP_ShortW_Aff[Fp2[BN254_Nogami], G2],
       P: ECP_ShortW_Aff[Fp[BN254_Nogami], G1]
     ) =
  ## Miller Loop for BN254-Nogami curve
  ## Computes f{6u+2,Q}(P) with u the BLS curve parameter
  var T {.noInit.}: ECP_ShortW_Prj[Fp2[BN254_Nogami], G2]

  f.miller_init_double_then_add(T, Q, P, 1)                # 0b11
  f.miller_accum_double_then_add(T, Q, P, 6)               # 0b11000001
  f.miller_accum_double_then_add(T, Q, P, 1)               # 0b110000011
  f.miller_accum_double_then_add(T, Q, P, 54)              # 0b110000011000000000000000000000000000000000000000000000000000001
  f.miller_accum_double_then_add(T, Q, P, 2, add = false)  # 0b11000001100000000000000000000000000000000000000000000000000000100

  # Negative AteParam
  f.conj()
  T.neg()

  # Ate pairing for BN curves needs adjustment after basic Miller loop
  f.millerCorrectionBN(T, Q, P)

func millerLoopAddchain*(
       f: var Fp12[BN254_Nogami],
       Qs: ptr UncheckedArray[ECP_ShortW_Aff[Fp2[BN254_Nogami], G2]],
       Ps: ptr UncheckedArray[ECP_ShortW_Aff[Fp[BN254_Nogami], G1]],
       N: int
     ) {.noInline.} =
  ## Miller Loop for BN254-Nogami curve
  ## Computes f{6u+2,Q}(P) with u the BLS curve parameter
  var Ts = allocStackArray(ECP_ShortW_Prj[Fp2[BN254_Nogami], G2], N)

  f.miller_init_double_then_add( Ts, Qs, Ps, N, 1)               # 0b11
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 6)               # 0b11000001
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 1)               # 0b110000011
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 54)              # 0b110000011000000000000000000000000000000000000000000000000000001
  f.miller_accum_double_then_add(Ts, Qs, Ps, N, 2, add = false)  # 0b11000001100000000000000000000000000000000000000000000000000000100

  # Negative AteParam
  f.conj()
  for i in 0 ..< N:
    Ts[i].neg()

  for i in 0 ..< N:
    f.millerCorrectionBN(Ts[i], Qs[i], Ps[i])

func cycl_exp_by_curve_param*(
       r: var Fp12[BN254_Nogami], a: Fp12[BN254_Nogami],
       invert = BN254_Nogami_pairing_ate_param_isNeg) =
  ## f^u with u the curve parameter
  ## For BN254_Nogami f^-0x4080000000000001 = 0b100000010000000000000000000000000000000000000000000000000000001
  r.cyclotomic_exp_compressed(a, [55, 7])
  r *= a

  if invert:
    r.cyclotomic_inv()

func isInPairingSubgroup*(a: Fp12[BN254_Nogami]): SecretBool =
  ## Returns true if a is in GT subgroup, i.e. a is an element of order r
  ## Warning ⚠: Assumes that a is in the cyclotomic subgroup
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #   P is in the G1 subgroup iff a^p == a^(6u²)
  var t0{.noInit.}, t1{.noInit.}: Fp12[BN254_Nogami]
  t0.cycl_exp_by_curve_param(a)   # a^p
  t1.cycl_exp_by_curve_param(t0)  # a^(p²)
  t0.square(t1) # a^(2p²)
  t0 *= t1      # a^(3p²)
  t0.square()   # a^(6p²)

  t1.frobenius_map(a)

  return t0 == t1