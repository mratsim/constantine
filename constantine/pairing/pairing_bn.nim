# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ../io/io_bigints,
  ../elliptic/[
    ec_weierstrass_affine,
    ec_weierstrass_projective
  ],
  ./lines_projective,
  ./mul_fp12_by_lines,
  ./cyclotomic_fp12,
  ../isogeny/frobenius

# ############################################################
#
#                 Optimal ATE pairing for
#                      BN curves
#
# ############################################################

# - Memory-saving computation of the pairing final exponentiation on BN curves
#   Sylvain Duquesne and Loubna Ghammam, 2015
#   https://eprint.iacr.org/2015/192
#
# - Faster hashing to G2
#   Laura Fuentes-Castañeda, Edward Knapp,
#   Francisco Jose Rodríguez-Henríquez, 2011
#   https://link.springer.com/content/pdf/10.1007%2F978-3-642-28496-0_25.pdf
#
# - Faster Pairing Computations on Curves with High-Degree Twists
#   Craig Costello, Tanja Lange, and Michael Naehrig, 2009
#   https://eprint.iacr.org/2009/615.pdf

# TODO: should be part of curve parameters
# The bit count must be exact for the Miller loop
const BN254_Snarks_ate_param = block:
  # BN Miller loop is parametrized by 6u+2
  BigInt[65+2].fromHex"0x19d797039be763ba8"

const BN254_Snarks_ate_param_isNeg = false

const BN254_Nogami_ate_param = block:
  # BN Miller loop is parametrized by 6u+2
  BigInt[65+2].fromHex"0x18300000000000004" # 65+2 bit for NAF x3 encoding

const BN254_Nogami_ate_param_isNeg = true

# Generic slow pairing implementation
# ----------------------------------------------------------------

const BN254_Snarks_finalexponent = block:
  # (p^12 - 1) / r
  BigInt[2790].fromHex"0x2f4b6dc97020fddadf107d20bc842d43bf6369b1ff6a1c71015f3f7be2e1e30a73bb94fec0daf15466b2383a5d3ec3d15ad524d8f70c54efee1bd8c3b21377e563a09a1b705887e72eceaddea3790364a61f676baaf977870e88d5c6c8fef0781361e443ae77f5b63a2a2264487f2940a8b1ddb3d15062cd0fb2015dfc6668449aed3cc48a82d0d602d268c7daab6a41294c0cc4ebe5664568dfc50e1648a45a4a1e3a5195846a3ed011a337a02088ec80e0ebae8755cfe107acf3aafb40494e406f804216bb10cf430b0f37856b42db8dc5514724ee93dfb10826f0dd4a0364b9580291d2cd65664814fde37ca80bb4ea44eacc5e641bbadf423f9a2cbf813b8d145da90029baee7ddadda71c7f3811c4105262945bba1668c3be69a3c230974d83561841d766f9c9d570bb7fbe04c7e8a6c3c760c0de81def35692da361102b6b9b2b918837fa97896e84abb40a4efb7e54523a486964b64ca86f120"

const BN254_Nogami_finalexponent = block:
  # (p^12 - 1) / r
  BigInt[2786].fromHex"0x2928fbb36b391596ee3fe4cbe857330da83e46fedf04d235a4a8daf5ff9f6eabcb4e3f20aa06f0a0d96b24f9af0cbbce750d61627dcbf5fec9139b8f1c46c86b49b4f8a202af26e4504f2c0f56570e9bd5b94c403f385d1908556486e24b396ddc2cdf13d06542f84fe8e82ccbad7b7423fc1ef4e8cc73d605e3e867c0a75f45ea7f6356d9846ce35d5a34f30396938818ad41914b97b99c289a7259b5d2e09477a77bd3c409b19f19e893f8ade90b0aed1b5fc8a07a3cebb41d4e9eee96b21a832ddb1e93e113edfb704fa532848c18593cd0ee90444a1b3499a800177ea38bdec62ec5191f2b6bbee449722f98d2173ad33077545c2ad10347e125a56fb40f086e9a4e62ad336a72c8b202ac3c1473d73b93d93dc0795ca0ca39226e7b4c1bb92f99248ec0806e0ad70744e9f2238736790f5185ea4c70808442a7d530c6ccd56b55a6973867ec6c73599bbd020bbe105da9c6b5c009ad8946cd6f0"

{.experimental: "dynamicBindSym".}

macro get(C: static Curve, value: untyped): untyped =
  return bindSym($C & "_" & $value)

func millerLoopGenericBN*[C: static Curve](
       f: var Fp12[C],
       P: ECP_SWei_Aff[Fp[C]],
       Q: ECP_SWei_Aff[Fp2[C]]
     ) =
  ## Generic Miller Loop for BN curves
  ## Computes f{6u+2,Q}(P) with u the BN curve parameter
  # TODO: retrieve the curve parameter from the curve declaration

  # TODO - boundary cases
  #   Loop start
  #     The literatture starts from both L-1 or L-2:
  #     L-1:
  #     - Scott2019, Pairing Implementation Revisited, Algorithm 1
  #     - Aranha2010, Faster Explicit Formulas ..., Algorithm 1
  #     L-2
  #     - Beuchat2010, High-Speed Software Implementation ..., Algorithm 1
  #     - Aranha2013, The Realm of The Pairings, Algorithm 1
  #     - Costello, Thesis, Algorithm 2.1
  #     - Costello2012, Pairings for Beginners, Algorithm 5.1
  #
  #     Even the guide to pairing based cryptography has both
  #     Chapter 3: L-1 (Algorithm 3.1)
  #     Chapter 11: L-2 (Algorithm 11.1) but it explains why L-2 (unrolling)
  #  Loop end
  #    - Some implementation, for example Beuchat2010 or the Guide to Pairing-Based Cryptography
  #      have an extra line addition after the main loop, this seems related to
  #      the NAF recoding and not Miller Loop
  #    - With r the order of G1 / G2 / GT,
  #      we have [r]T = Inf
  #      Hence, [r-1]T = -T
  #      so either we use complete addition
  #      or we special case line addition of T and -T (it's a vertical line)
  #      or we ensure the loop is done for a number of iterations strictly less
  #      than the curve order which is the case for BN curves

  var
    T {.noInit.}: ECP_SWei_Proj[Fp2[C]]
    line {.noInit.}: Line[Fp2[C], C.getSexticTwist()]
    nQ{.noInit.}: typeof(Q)

  T.projectiveFromAffine(Q)
  nQ.neg(Q)
  f.setOne()

  template mul(f, line): untyped =
    when C.getSexticTwist() == D_Twist:
      f.mul_sparse_by_line_xyz000(line)
    else:
      f.mul_sparse_by_line_xy000z(line)

  template u: untyped = C.get(ate_param)
  let u3 = 3*C.get(ate_param)
  for i in countdown(u3.bits - 2, 1):
    f.square()
    line.line_double(T, P)
    f.mul(line)

    let naf = u3.bit(i).int8 - u.bit(i).int8 # This can throw exception
    if naf == 1:
      line.line_add(T, Q, P)
      f.mul(line)
    elif naf == -1:
      line.line_add(T, nQ, P)
      f.mul(line)

  when C.get(ate_param_isNeg):
    # In GT, x^-1 == conjugate(x)
    # Remark 7.1, chapter 7.1.1 of Guide to Pairing-Based Cryptography, El Mrabet, 2017
    f.conj()

  # Ate pairing for BN curves need adjustment after Miller loop
  when C.get(ate_param_isNeg):
    T.neg()
  var V {.noInit.}: typeof(Q)

  V.frobenius_psi(Q)
  line.line_add(T, V, P)
  f.mul_sparse_by_line_xyz000(line)

  V.frobenius_psi2(Q)
  V.neg()
  line.line_add(T, V, P)
  f.mul_sparse_by_line_xyz000(line)

func finalExpGeneric[C: static Curve](f: var Fp12[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.powUnsafeExponent(C.get(finalexponent), window = 3)

func pairing_bn_reference*[C](gt: var Fp12[C], P: ECP_SWei_Proj[Fp[C]], Q: ECP_SWei_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BN curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  var Paff {.noInit.}: ECP_SWei_Aff[Fp[C]]
  var Qaff {.noInit.}: ECP_SWei_Aff[Fp2[C]]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBN(Paff, Qaff)
  gt.finalExpGeneric()

# Optimized pairing implementation
# ----------------------------------------------------------------

func cycl_sqr_repeated(f: var Fp12, num: int) =
  ## Repeated cyclotomic squarings
  for _ in 0 ..< num:
    f.cyclotomic_square()

func pow_u(r: var Fp12[BN254_Nogami], a: Fp12[BN254_Nogami], invert = BN254_Nogami_ate_param_isNeg) =
  ## f^u with u the curve parameter
  ## For BN254_Nogami f^-0x4080000000000001
  r = a
  r.cycl_sqr_repeated(7)
  r *= a
  r.cycl_sqr_repeated(55)
  r *= a

  if invert:
    r.cyclotomic_inv()

func pow_u(r: var Fp12[BN254_Snarks], a: Fp12[BN254_Snarks], invert = BN254_Snarks_ate_param_isNeg) =
  ## f^u with u the curve parameter
  ## For BN254_Snarks f^0x44e992b44a6909f1
  when false:
    cyclotomic_exp(
      r, a,
      BigInt[63].fromHex("0x44e992b44a6909f1"),
      invert
    )
  else:
    var # Hopefully the compiler optimizes away unused Fp12
        # because those are huge
      x10       {.noInit.}: Fp12[BN254_Snarks]
      x11       {.noInit.}: Fp12[BN254_Snarks]
      x100      {.noInit.}: Fp12[BN254_Snarks]
      x110      {.noInit.}: Fp12[BN254_Snarks]
      x1100     {.noInit.}: Fp12[BN254_Snarks]
      x1111     {.noInit.}: Fp12[BN254_Snarks]
      x10010    {.noInit.}: Fp12[BN254_Snarks]
      x10110    {.noInit.}: Fp12[BN254_Snarks]
      x11100    {.noInit.}: Fp12[BN254_Snarks]
      x101110   {.noInit.}: Fp12[BN254_Snarks]
      x1001010  {.noInit.}: Fp12[BN254_Snarks]
      x1111000  {.noInit.}: Fp12[BN254_Snarks]
      x10001110 {.noInit.}: Fp12[BN254_Snarks]

    x10       .cyclotomic_square(a)
    x11       .prod(x10, a)
    x100      .prod(x11, a)
    x110      .prod(x10, x100)
    x1100     .cyclotomic_square(x110)
    x1111     .prod(x11, x1100)
    x10010    .prod(x11, x1111)
    x10110    .prod(x100, x10010)
    x11100    .prod(x110, x10110)
    x101110   .prod(x10010, x11100)
    x1001010  .prod(x11100, x101110)
    x1111000  .prod(x101110, x1001010)
    x10001110 .prod(x10110, x1111000)

    var
      i15 {.noInit.}: Fp12[BN254_Snarks]
      i16 {.noInit.}: Fp12[BN254_Snarks]
      i17 {.noInit.}: Fp12[BN254_Snarks]
      i18 {.noInit.}: Fp12[BN254_Snarks]
      i20 {.noInit.}: Fp12[BN254_Snarks]
      i21 {.noInit.}: Fp12[BN254_Snarks]
      i22 {.noInit.}: Fp12[BN254_Snarks]
      i26 {.noInit.}: Fp12[BN254_Snarks]
      i27 {.noInit.}: Fp12[BN254_Snarks]
      i61 {.noInit.}: Fp12[BN254_Snarks]

    i15.cyclotomic_square(x10001110)
    i15 *= x1001010
    i16.prod(x10001110, i15)
    i17.prod(x1111, i16)
    i18.prod(i16, i17)

    i20.cyclotomic_square(i18)
    i20 *= i17
    i21.prod(x1111000, i20)
    i22.prod(i15, i21)

    i26.cyclotomic_square(i22)
    i26.cyclotomic_square()
    i26 *= i22
    i26 *= i18

    i27.prod(i22, i26)

    i61.prod(i26, i27)
    i61.cycl_sqr_repeated(17)
    i61 *= i27
    i61.cycl_sqr_repeated(14)
    i61 *= i21

    r = i61
    r.cycl_sqr_repeated(16)
    r *= i20

    if invert:
      r.cyclotomic_inv()

func finalExpHard_BN*[C: static Curve](f: var Fp12[C]) =
  ## Hard part of the final exponentiation
  ## Specialized for BN curves
  ##
  # - Memory-saving computation of the pairing final exponentiation on BN curves
  #   Sylvain Duquesne and Loubna Ghammam, 2015
  #   https://eprint.iacr.org/2015/192
  # - Faster hashing to G2
  #   Laura Fuentes-Castañeda, Edward Knapp,
  #   Francisco Jose Rodríguez-Henríquez, 2011
  #   https://link.springer.com/content/pdf/10.1007%2F978-3-642-28496-0_25.pdf
  #
  # We use the Fuentes-Castañeda et al algorithm without
  # memory saving optimization
  # as that variant has an exponentiation by -2u-1
  # that requires another addition chain
  var t0 {.noInit.}, t1 {.noinit.}, t2 {.noinit.}, t3 {.noinit.}, t4 {.noinit.}: Fp12[C]

  t0.pow_u(f, invert = false)  # t0 = f^|u|
  t0.cyclotomic_square()       # t0 = f^2|u|
  t1.cyclotomic_square(t0)     # t1 = f^4|u|
  t1 *= t0                     # t1 = f^6|u|
  t2.pow_u(t1, invert = false) # t2 = f^6u²

  if C.get(ate_param_is_Neg):
    t3.cyclotomic_inv(t1)      # t3 = f^6u
  else:
    t3 = t1                    # t3 = f^6u
  t1.prod(t2, t3)              # t1 = f^6u.f^6u²
  t3.cyclotomic_square(t2)     # t3 = f^12u²
  t4.pow_u(t3)                 # t4 = f^12u³
  t4 *= t1                     # t4 = f^(6u + 6u² + 12u³) = f^λ₂

  if not C.get(ate_param_is_Neg):
    t0.cyclotomic_inv()        # t0 = f^-2u
  t3.prod(t4, t0)              # t3 = f^(4u + 6u² + 12u³)

  t0.prod(t2, t4)              # t0 = f^6u.f^12u².f^12u³
  t0 *= f                      # t0 = f^(1 + 6u + 12u² + 12u³) = f^λ₀

  t2.frobenius_map(t3)         # t2 = f^(4u + 6u² + 12u³)p = f^λ₁p
  t0 *= t2                     # t0 = f^(λ₀+λ₁p)

  t2.frobenius_map(t4, 2)      # t2 = f^λ₂p²
  t0 *= t2                     # t0 = f^(λ₀ + λ₁p + λ₂p²)

  t2.cyclotomic_inv(f)         # t2 = f⁻¹
  t2 *= t3                     # t3 = f^(-1 + 4u + 6u² + 12u³) = f^λ₃

  f.frobenius_map(t2, 3)       # r = f^λ₃p³
  f *= t0                      # r = f^(λ₀ + λ₁p + λ₂p² + λ₃p³) = f^((p⁴-p²+1)/r)

func pairing_bn*[C](gt: var Fp12[C], P: ECP_SWei_Proj[Fp[C]], Q: ECP_SWei_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  var Paff {.noInit.}: ECP_SWei_Aff[Fp[C]]
  var Qaff {.noInit.}: ECP_SWei_Aff[Fp2[C]]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBN(Paff, Qaff)
  gt.finalExpEasy()
  gt.finalExpHard_BN()
