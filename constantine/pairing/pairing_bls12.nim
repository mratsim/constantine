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

# TODO: should be part of curve parameters
# The bit count must be exact for the Miller loop
const BLS12_377_ate_param = block:
  # BLS Miller loop is parametrized by u
  BigInt[64+1].fromHex("0x8508c00000000001") # +1 so that we can take *3 and NAF encode it

const BLS12_377_ate_param_isNeg = false

const BLS12_381_ate_param = block:
  # BLS Miller loop is parametrized by u
  BigInt[64+2].fromHex("0xd201000000010000") # +2 so that we can take *3 and NAF encode it

const BLS12_381_ate_param_isNeg = true

# Generic slow pairing implementation
# ----------------------------------------------------------------

const BLS12_377_finalexponent = block:
  # (p^12 - 1) / r
  # BigInt[4269].fromHex"0x1b2ff68c1abdc48ab4f04ed12cc8f9b2f161b41c7eb8865b9ad3c9bb0571dd94c6bde66548dc13624d9d741024ceb315f46a89cc2482605eb6afc6d8977e5e2ccbec348dd362d59ec2b5bc62a1b467ae44572215548abc98bb4193886ed89cceaedd0221aba84fb33e5584ac29619a87a00c315178155496857c995eab4a8a9af95f4015db27955ae408d6927d0ab37d52f3917c4ddec88f8159f7bcba7eb65f1aae4eeb4e70cb20227159c08a7fdfea9b62bb308918eac3202569dd1bcdd86b431e3646356fc3fb79f89b30775e006993adb629586b6c874b7688f86f11ef7ad94a40eb020da3c532b317232fa56dc564637b331a8e8832eab84269f00b506602c8594b7f7da5a5d8d851fff6ab1d38a354fc8e0b8958e2a9e5ce2d7e50ec36d761d9505fe5e1f317257e2df2952fcd4c93b85278c20488b4ccaee94db3fec1ce8283473e4b493843fa73abe99af8bafce29170b2b863b9513b5a47312991f60c5a4f6872b5d574212bf00d797c0bea3c0f7dfd748e63679fda9b1c50f2df74de38f38e004ae0df997a10db31d209cacbf58ba0678bfe7cd0985bc43258d72d8d5106c21635ae1e527eb01fca3032d50d97756ec9ee756eaba7f21652a808a4e2539e838ef7ec4b178b29e3b976c46bd0ecdd32c1fb75e6e0aef2d8b5661f595a98023f3520381aba8da6cce785dbb0a0bba025478d75ee749619cdb7c42a21098ece86a00c6c2046c1e00000063c69000000000000"
  # (p^12 - 1) / r * 3
  BigInt[4271].fromHex"0x518fe3a450394da01ed0ec73865aed18d4251c557c299312d07b5d31105598be5439b32fda943a26e8d85c306e6c1941dd3f9d646d87211c240f5489c67b1a8663c49da97a2880dc48213527e51d370acd05663ffda035ca31c4ba994c89d66c0c97066502f8ef19bb008e047c24cf96e02493f4683ffdc39075cc1c01df9fd0ec1dc0419176c010ac1a83b777201a77f8dab474e99c59ae840de7362f7c231d500aecc1eb52616067540d419f7f9fbfd22831919b4ac04960703d9753698941c95aa2d2a04f4bf26de9d191661a013cbb09227c09424595e2639ae94d35ce708bdec2c10628eb4f981945698ef049502d2a71994fab9898c028c73dd021f13208590be27e78f0f18a88f5ffe40157a9e9fef5aa229c0aa7fdb16a887af2c4a486258bf11fb1a5d945707a89d7bf8f67e5bb28f76a460d9a1e660cbbe91bfc456b8789d5bae1dba8cbef5b03bcd0ea30f6a7b45218292b2bf3b20ed5937cb5e2250eee395821805c6383d0286c7423beb42e79f85dab2a36df8fd154f2d89e5e9aaadaaa00e0a29ecc6e329195761d6063e0a2e136a3fb7671c9134c970a8588a7f3144642a10a5af77c105f5e90987f28c6604c5dcb604c02f7d642f7f819eea6fadb8aace7c4e146a17dab2c644d4372c6979845f261b4a20cd88a20325e0c0fc806bd9f60a8502fa8f466b6919311e232e06fd6a861cb5dc24d69274c7e631cac6b93e0254460d445a0000012b53b000000000000"

const BLS12_381_finalexponent = block:
  # (p^12 - 1) / r
  # BigInt[4314].fromHex"0x2ee1db5dcc825b7e1bda9c0496a1c0a89ee0193d4977b3f7d4507d07363baa13f8d14a917848517badc3a43d1073776ab353f2c30698e8cc7deada9c0aadff5e9cfee9a074e43b9a660835cc872ee83ff3a0f0f1c0ad0d6106feaf4e347aa68ad49466fa927e7bb9375331807a0dce2630d9aa4b113f414386b0e8819328148978e2b0dd39099b86e1ab656d2670d93e4d7acdd350da5359bc73ab61a0c5bf24c374693c49f570bcd2b01f3077ffb10bf24dde41064837f27611212596bc293c8d4c01f25118790f4684d0b9c40a68eb74bb22a40ee7169cdc1041296532fef459f12438dfc8e2886ef965e61a474c5c85b0129127a1b5ad0463434724538411d1676a53b5a62eb34c05739334f46c02c3f0bd0c55d3109cd15948d0a1fad20044ce6ad4c6bec3ec03ef19592004cedd556952c6d8823b19dadd7c2498345c6e5308f1c511291097db60b1749bf9b71a9f9e0100418a3ef0bc627751bbd81367066bca6a4c1b6dcfc5cceb73fc56947a403577dfa9e13c24ea820b09c1d9f7c31759c3635de3f7a3639991708e88adce88177456c49637fd7961be1a4c7e79fb02faa732e2f3ec2bea83d196283313492caa9d4aff1c910e9622d2a73f62537f2701aaef6539314043f7bbce5b78c7869aeb2181a67e49eeed2161daf3f881bd88592d767f67c4717489119226c2f011d4cab803e9d71650a6f80698e2f8491d12191a04406fbc8fbd5f48925f98630e68bfb24c0bcb9b55df57510"
  # (p^12 - 1) / r * 3
  BigInt[4316].fromHex"0x8ca592196587127a538fd40dc3e541f9dca04bb7dc671be77cf17715a2b2fe3bea73dfb468d8f473094aecb7315a664019fbd84913caba6579c08fd42009fe1bd6fcbce15eacb2cf3218a165958cb8bfdae2d2d54207282314fc0dea9d6ff3a07dbd34efb77b732ba5f994816e296a72928cfee133bdc3ca9412b984b9783d9c6aa81297ab1cd294a502304773528bbae8706979f28efa0d355b0224e2513d6e4a5d3bb4dde0523678105d9167ff1323d6e99ac312d8a7d762336370c4347bb5a7e405d6f3496b2dd38e722d4c1f3ac25e3167ec2cb543d69430c37c2f98fcdd0dd36caa9f5aa7994cec31b24ed5e515911037b376e521070d29c9d56cfa8c3574363efb20f28c19e4105ab99edd44084bd23725017931d6740bda71e5f07600ce6b407e543c4bc40bcd4c0b600e6c98003bf8548986b14d9098746dc89d154af91ad54f337b31c79222145dd3ed254fdeda0300c49ebcd2352765f533883a3513435f3ee452496f5166c25bf503bd6ec0a0679efda3b46ebf86211d458de749460d4a2a19abe6ea2accb451ab9a096b98465d044dc2a7f86c253a4ee57b6df108eff598a8dbc483bf8b74c2789939db85ffd7e0fd55b32bc26877f5be26fa7d750500ce2fab93c0cbe7336b126a5693d0c16484f37addccc7642590dbe98538990b88637e374d545d9b34b67448d0357e60280bbd8542f1f4e813caa8e8db57364b4e0cc14f35af381dd9b71ec9292b3a3f16e42362d2019e05f30"

{.experimental: "dynamicBindSym".}

macro get(C: static Curve, value: untyped): untyped =
  return bindSym($C & "_" & $value)

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

func finalExpGeneric[C: static Curve](f: var Fp12[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.powUnsafeExponent(C.get(finalexponent), window = 3)

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

func pow_xdiv2(r: var Fp12[BLS12_381], a: Fp12[BLS12_381], invert = BLS12_381_ate_param_isNeg) =
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

func pow_x(r: var Fp12[BLS12_381], a: Fp12[BLS12_381], invert = BLS12_381_ate_param_isNeg) =
  ## f^x with x the curve parameter
  ## For BLS12_381 f^-0xd201000000010000
  r.pow_xdiv2(a, invert)
  r.cyclotomic_square()

func pow_x(r: var Fp12[BLS12_377], a: Fp12[BLS12_377], invert = BLS12_377_ate_param_isNeg) =
  ## f^x with x the curve parameter
  ## For BLS12_377 f^-0x8508c00000000001
  ## Warning: The parameter is odd and needs a correction
  r.cyclotomic_square(a)
  r *= a
  r.cyclotomic_square()
  r *= a
  let t111 = r

  r.cycl_sqr_repeated(2)
  let t111000 = r

  r *= t111
  let t100011 = r

  r.cyclotomic_square()
  r *= t100011
  r *= t111000

  r.cycl_sqr_repeated(10)
  r *= t100011

  r.cycl_sqr_repeated(46)
  r *= a

  if invert:
    r.cyclotomic_inv()

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
  when C.get(ate_param).isEven.bool:
    v0.pow_xdiv2(v2)           # v0 = (f²)^(x/2) = f^x
  else:
    v0.pow_x(f)
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
