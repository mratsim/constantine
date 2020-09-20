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
  ./lines_projective

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

func millerLoopGenericBLS12[C: static Curve](
       f: var Fp12[C],
       P: ECP_SWei_Proj[Fp[C]],
       Q: ECP_SWei_Proj[Fp2[C]]
     ) =
  ## Generic Miller Loop for BLS12 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter
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
  #      than the curve order which is the case for BLS12 curves

  static: doAssert C == BLS12_381, "Only BLS12-381 is supported at the moment"

  var
    T = Q
    Paff {.noInit.}: ECP_SWei_Aff[Fp[C]]
    line {.noInit.}: Line[Fp2[C], C.getSexticTwist()]
    nQ{.noInit.}: typeof(Q)

  nQ.neg(Q)
  f.setOne()
  Paff.affineFromProjective(P) # TODO, the scaling factor should be eliminated by the final exponentiation anyway

  template u: untyped = BLS12_381_param
  let u3 = 3*BLS12_381_param
  for i in countdown(u3.bits - 2, 1):
    f.square()
    line.line_double(T, Paff)
    f.mul_sparse_by_line_xy000z(line)

    let naf = u3.bit(i).int8 - u.bit(i).int8 # This can throw exception
    if naf == 1:
      line.line_add(T, Q, Paff)
      f.mul_sparse_by_line_xy000z(line)
    elif naf == -1:
      line.line_add(T, nQ, Paff)
      f.mul_sparse_by_line_xy000z(line)

  when BLS12_381_param_isNeg: # TODO generic
    # In GT, x^-1 == conjugate(x)
    # Remark 7.1, chapter 7.1.1 of Guide to Pairing-Based Cryptography, El Mrabet, 2017
    f.conj()

iterator unpack(scalarByte: byte): bool =
  yield bool((scalarByte and 0b10000000) shr 7)
  yield bool((scalarByte and 0b01000000) shr 6)
  yield bool((scalarByte and 0b00100000) shr 5)
  yield bool((scalarByte and 0b00010000) shr 4)
  yield bool((scalarByte and 0b00001000) shr 3)
  yield bool((scalarByte and 0b00000100) shr 2)
  yield bool((scalarByte and 0b00000010) shr 1)
  yield bool( scalarByte and 0b00000001)

const BLS12_381_finalexponent = block:
  BigInt[4314].fromHex("0x2ee1db5dcc825b7e1bda9c0496a1c0a89ee0193d4977b3f7d4507d07363baa13f8d14a917848517badc3a43d1073776ab353f2c30698e8cc7deada9c0aadff5e9cfee9a074e43b9a660835cc872ee83ff3a0f0f1c0ad0d6106feaf4e347aa68ad49466fa927e7bb9375331807a0dce2630d9aa4b113f414386b0e8819328148978e2b0dd39099b86e1ab656d2670d93e4d7acdd350da5359bc73ab61a0c5bf24c374693c49f570bcd2b01f3077ffb10bf24dde41064837f27611212596bc293c8d4c01f25118790f4684d0b9c40a68eb74bb22a40ee7169cdc1041296532fef459f12438dfc8e2886ef965e61a474c5c85b0129127a1b5ad0463434724538411d1676a53b5a62eb34c05739334f46c02c3f0bd0c55d3109cd15948d0a1fad20044ce6ad4c6bec3ec03ef19592004cedd556952c6d8823b19dadd7c2498345c6e5308f1c511291097db60b1749bf9b71a9f9e0100418a3ef0bc627751bbd81367066bca6a4c1b6dcfc5cceb73fc56947a403577dfa9e13c24ea820b09c1d9f7c31759c3635de3f7a3639991708e88adce88177456c49637fd7961be1a4c7e79fb02faa732e2f3ec2bea83d196283313492caa9d4aff1c910e9622d2a73f62537f2701aaef6539314043f7bbce5b78c7869aeb2181a67e49eeed2161daf3f881bd88592d767f67c4717489119226c2f011d4cab803e9d71650a6f80698e2f8491d12191a04406fbc8fbd5f48925f98630e68bfb24c0bcb9b55df57510")

func finalExpGeneric[C: static Curve](f: var Fp12[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  static: doAssert C == BLS12_381, "Only BLS12-381 is supported at the moment"
  # {.error: "Those implementations are correct exponentiations but incorrect final exponentiations, why?".}
  when false:
    f.powUnsafeExponent(BLS12_381_finalexponent, window = 3)
  else:
    var e: array[(BLS12_381_finalexponent.bits+7) div 8, byte]
    e.exportRawUint(BLS12_381_finalexponent, bigEndian)

    var t0{.noInit.}, t1{.noInit.}: Fp12[C]
    t0.setOne()
    t1.setOne()
    for eByte in e:
      for bit in unpack(eByte):
        t1.square(t0)
        if bit:
          t0.prod(t1, f)
        else:
          t0 = t1
    f = t0

func finalExpEasy[C: static Curve](f: var Fp12[C]) =
  ## Easy part of the final exponentiation
  ## We need to clear the GT cofactor to obtain
  ## an unique GT representation
  ## (reminder, GT is a multiplicative group hence we exponentiate by the cofactor)
  ##
  ## With an embedding degree of 12, the easy part of final exponentiation is
  ##
  ##  f^(p⁶−1)(p²+1)
  discard

func pairing_bls12*[C](gt: var Fp12[C], P: ECP_SWei_Proj[Fp[C]], Q: ECP_SWei_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  gt.millerLoopGenericBLS12(P, Q)
  debugEcho "\nv (ate): ", gt.toHex()
  gt.finalExpGeneric()
