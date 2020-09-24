# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ../io/io_bigints,
  ../elliptic/[
    ec_weierstrass_affine,
    ec_weierstrass_projective
  ],
  ../isogeny/frobenius,
  ./lines_projective,
  ./mul_fp12_by_lines,
  ./cyclotomic_fp12

# ############################################################
#
#                 Optimal ATE pairing for
#                      BLS12 curves
#
# ############################################################

# - Efficient Final Exponentiation
#   via Cyclotomic Structure for Pairings
#   over Families of Elliptic Curves
#   Daiki Hayashida and Kenichiro Hayasaka
#   and Tadanori Teruya, 2020
#   https://eprint.iacr.org/2020/875.pdf
#
# - Improving the computation of the optimal ate pairing
#   for a high security level.
#   Loubna Ghammam, Emmanuel Fouotsa
#   J. Appl. Math. Comput.59, 21–36 (2019)
#
# - Faster Pairing Computations on Curves with High-Degree Twists
#   Craig Costello, Tanja Lange, and Michael Naehrig, 2009
#   https://eprint.iacr.org/2009/615.pdf

# TODO: implement quadruple-and-add and octuple-and-add
#       from Costello2009 to trade multiplications in Fpᵏ
#       for multiplications in Fp

# TODO: should be part of curve parameters
const BLS12_381_param = block:
  # BLS Miller loop is parametrized by u
  BigInt[64+2].fromHex("0xd201000000010000") # +2 so that we can take *3 and NAF encode it

const BLS12_381_param_isNeg = true

# Generic slow pairing implementation
# ----------------------------------------------------------------

const BLS12_381_finalexponent = block:
  # (p^12 - 1) / r
  # BigInt[4314].fromHex"0x2ee1db5dcc825b7e1bda9c0496a1c0a89ee0193d4977b3f7d4507d07363baa13f8d14a917848517badc3a43d1073776ab353f2c30698e8cc7deada9c0aadff5e9cfee9a074e43b9a660835cc872ee83ff3a0f0f1c0ad0d6106feaf4e347aa68ad49466fa927e7bb9375331807a0dce2630d9aa4b113f414386b0e8819328148978e2b0dd39099b86e1ab656d2670d93e4d7acdd350da5359bc73ab61a0c5bf24c374693c49f570bcd2b01f3077ffb10bf24dde41064837f27611212596bc293c8d4c01f25118790f4684d0b9c40a68eb74bb22a40ee7169cdc1041296532fef459f12438dfc8e2886ef965e61a474c5c85b0129127a1b5ad0463434724538411d1676a53b5a62eb34c05739334f46c02c3f0bd0c55d3109cd15948d0a1fad20044ce6ad4c6bec3ec03ef19592004cedd556952c6d8823b19dadd7c2498345c6e5308f1c511291097db60b1749bf9b71a9f9e0100418a3ef0bc627751bbd81367066bca6a4c1b6dcfc5cceb73fc56947a403577dfa9e13c24ea820b09c1d9f7c31759c3635de3f7a3639991708e88adce88177456c49637fd7961be1a4c7e79fb02faa732e2f3ec2bea83d196283313492caa9d4aff1c910e9622d2a73f62537f2701aaef6539314043f7bbce5b78c7869aeb2181a67e49eeed2161daf3f881bd88592d767f67c4717489119226c2f011d4cab803e9d71650a6f80698e2f8491d12191a04406fbc8fbd5f48925f98630e68bfb24c0bcb9b55df57510"
  # (p^12 - 1) / r * 3
  BigInt[4316].fromHex"0x8ca592196587127a538fd40dc3e541f9dca04bb7dc671be77cf17715a2b2fe3bea73dfb468d8f473094aecb7315a664019fbd84913caba6579c08fd42009fe1bd6fcbce15eacb2cf3218a165958cb8bfdae2d2d54207282314fc0dea9d6ff3a07dbd34efb77b732ba5f994816e296a72928cfee133bdc3ca9412b984b9783d9c6aa81297ab1cd294a502304773528bbae8706979f28efa0d355b0224e2513d6e4a5d3bb4dde0523678105d9167ff1323d6e99ac312d8a7d762336370c4347bb5a7e405d6f3496b2dd38e722d4c1f3ac25e3167ec2cb543d69430c37c2f98fcdd0dd36caa9f5aa7994cec31b24ed5e515911037b376e521070d29c9d56cfa8c3574363efb20f28c19e4105ab99edd44084bd23725017931d6740bda71e5f07600ce6b407e543c4bc40bcd4c0b600e6c98003bf8548986b14d9098746dc89d154af91ad54f337b31c79222145dd3ed254fdeda0300c49ebcd2352765f533883a3513435f3ee452496f5166c25bf503bd6ec0a0679efda3b46ebf86211d458de749460d4a2a19abe6ea2accb451ab9a096b98465d044dc2a7f86c253a4ee57b6df108eff598a8dbc483bf8b74c2789939db85ffd7e0fd55b32bc26877f5be26fa7d750500ce2fab93c0cbe7336b126a5693d0c16484f37addccc7642590dbe98538990b88637e374d545d9b34b67448d0357e60280bbd8542f1f4e813caa8e8db57364b4e0cc14f35af381dd9b71ec9292b3a3f16e42362d2019e05f30"

func millerLoopGenericBLS12*[C: static Curve](
       f: var Fp12[C],
       P: ECP_SWei_Aff[Fp[C]],
       Q: ECP_SWei_Aff[Fp2[C]]
     ) =
  ## Generic Miller Loop for BLS12 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter
  # TODO: retrieve the curve parameter from the curve declaration

  # Boundary cases
  #   Loop start
  #     The litterature starts from both L-1 or L-2:
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
  #      have extra line additions after the main loop,
  #      this is needed for BN curves.
  #    - With r the order of G1 / G2 / GT,
  #      we have [r]T = Inf
  #      Hence, [r-1]T = -T
  #      so either we use complete addition
  #      or we special case line addition of T and -T (it's a vertical line)
  #      or we ensure the loop is done for a number of iterations strictly less
  #      than the curve order which is the case for BLS12 curves

  static: doAssert C == BLS12_381, "Only BLS12-381 is supported at the moment"

  var
    T {.noInit.}: ECP_SWei_Proj[Fp2[C]]
    line {.noInit.}: Line[Fp2[C], C.getSexticTwist()]
    nQ{.noInit.}: typeof(Q)

  T.projectiveFromAffine(Q)
  nQ.neg(Q)
  f.setOne()

  template u: untyped = BLS12_381_param
  let u3 = 3*BLS12_381_param
  for i in countdown(u3.bits - 2, 1):
    f.square()
    line.line_double(T, P)
    f.mul_sparse_by_line_xy000z(line)

    let naf = u3.bit(i).int8 - u.bit(i).int8 # This can throw exception
    if naf == 1:
      line.line_add(T, Q, P)
      f.mul_sparse_by_line_xy000z(line)
    elif naf == -1:
      line.line_add(T, nQ, P)
      f.mul_sparse_by_line_xy000z(line)

  when BLS12_381_param_isNeg: # TODO generic
    # In GT, x^-1 == conjugate(x)
    # Remark 7.1, chapter 7.1.1 of Guide to Pairing-Based Cryptography, El Mrabet, 2017
    f.conj()

func finalExpGeneric[C: static Curve](f: var Fp12[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  static: doAssert C == BLS12_381, "Only BLS12-381 is supported at the moment"
  f.powUnsafeExponent(BLS12_381_finalexponent, window = 3)

func pairing_bls12_reference*[C](gt: var Fp12[C], P: ECP_SWei_Proj[Fp[C]], Q: ECP_SWei_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  var Paff {.noInit.}: ECP_SWei_Aff[Fp[C]]
  var Qaff {.noInit.}: ECP_SWei_Aff[Fp2[C]]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBLS12(Paff, Qaff)
  gt.finalExpGeneric()

# Optimized pairing implementation
# ----------------------------------------------------------------

func cycl_sqr_repeated(f: var Fp12, num: int) =
  ## Repeated cyclotomic squarings
  for _ in 0 ..< num:
    f.cyclotomic_square()

func pow_xdiv2(r: var Fp12[BLS12_381], a: Fp12[BLS12_381], invert = BLS12_381_param_isNeg) =
  ## f^(x/2) with x the curve parameter
  ## For BLS12_381 f^-0xd201000000010000

  r.cyclotomic_square(a)
  r *= a
  r.cycl_sqr_repeated(2)
  r *= a
  r.cycl_sqr_repeated(3)
  r *= a
  r.cycl_sqr_repeated(9)
  r *= a
  r.cycl_sqr_repeated(32)   # TODO: use Karabina?
  r *= a
  r.cycl_sqr_repeated(16-1) # Don't do the last iteration

  if invert:
    r.cyclotomic_inv()

func pow_x(r: var Fp12[BLS12_381], a: Fp12[BLS12_381], invert = BLS12_381_param_isNeg) =
  ## f^x with x the curve parameter
  ## For BLS12_381 f^-0xd201000000010000
  r.pow_xdiv2(a, invert)
  r.cyclotomic_square()

func finalExpHard_BLS12*[C: static Curve](f: var Fp12[C]) =
  ## Hard part of the final exponentiation
  ## Specialized for BLS12 curves
  ##
  # - Efficient Final Exponentiation
  #   via Cyclotomic Structure for Pairings
  #   over Families of Elliptic Curves
  #   Daiki Hayashida and Kenichiro Hayasaka
  #   and Tadanori Teruya, 2020
  #   https://eprint.iacr.org/2020/875.pdf
  #
  # p14: 3 Φ₁₂(p(x))/r(x) = (x−1)² (x+p) (x²+p²−1) + 3
  #
  # TODO: paper costs are 4Eₓ+Eₓ/₂+7M₁₂+S₁₂+F₁+F₂
  #       so we have an extra cyclotomic squaring since we use 5Eₓ
  #
  # with
  # - Eₓ being f^x
  # - Eₓ/₂ being f^(x/2)
  # - M₁₂ being mul in Fp12
  # - S₁₂ being cyclotomic squaring
  # - Fₙ being n Frobenius applications

  var v0 {.noInit.}, v1 {.noInit.}, v2 {.noInit.}: Fp12[C]

  # Save for f³ and (x−1)²
  v2.cyclotomic_square(f)      # v2 = f²

  # (x−1)²
  v0.pow_xdiv2(v2)             # v0 = (f²)^(x/2) = f^x
  v1.cyclotomic_inv(f)         # v1 = f^-1
  v0 *= v1                     # v0 = f^(x-1)
  v1.pow_x(v0)                 # v1 = (f^(x-1))^x
  v0.cyclotomic_inv()          # v0 = (f^(x-1))^-1
  v0 *= v1                     # v0 = (f^(x-1))^(x-1) = f^((x-1)*(x-1)) = f^((x-1)²)

  # (x+p)
  v1.pow_x(v0)                 # v1 = f^((x-1)².x)
  v0.frobenius_map(v0)         # v0 = f^((x-1)².p)
  v0 *= v1                     # v0 = f^((x-1)².(x+p))

  # + 3
  f *= v2                      # f = f³

  # (x²+p²−1)
  v2.pow_x(v0, invert = false)
  v1.pow_x(v2, invert = false) # v1 = f^((x-1)².(x+p).x²)
  v2.frobenius_map(v0, 2)      # v2 = f^((x-1)².(x+p).p²)
  v0.cyclotomic_inv()          # v0 = f^((x-1)².(x+p).-1)
  v0 *= v1                     # v0 = f^((x-1)².(x+p).(x²-1))
  v0 *= v2                     # v0 = f^((x-1)².(x+p).(x²+p²-1))

  # (x−1)².(x+p).(x²+p²−1) + 3
  f *= v0

func pairing_bls12*[C](gt: var Fp12[C], P: ECP_SWei_Proj[Fp[C]], Q: ECP_SWei_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  var Paff {.noInit.}: ECP_SWei_Aff[Fp[C]]
  var Qaff {.noInit.}: ECP_SWei_Aff[Fp2[C]]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBLS12(Paff, Qaff)
  gt.finalExpEasy()
  gt.finalExpHard_BLS12()
