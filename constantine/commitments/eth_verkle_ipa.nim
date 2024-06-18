# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./pedersen_commitments,
  ./eth_verkle_transcripts,
  ../math/config/[curves, type_ff],
  ../math/polynomials/polynomials,
  ../math/[arithmetic, ec_shortweierstrass, ec_twistededwards],
  ../math/elliptic/ec_multi_scalar_mul,
  ../platforms/[abstractions, views]

## ############################################################
##
##                 Inner Product Arguments
##              Ethereum Verkle Tries flavor
##
## ############################################################

# This file implements Inner Product Arguments (IPA) commitment.
# While generic in theory and usable beyond Ethereum,
# the transcript hardcodes Ethereum challenges and would need to be
# modified to be compatible with other IPA implementations like Halo2.
#
# - https://eprint.iacr.org/2019/1021
# - https://zcash.github.io/halo2/background/pc-ipa.html
# - https://raw.githubusercontent.com/daira/halographs/master/deepdive.pdf
# - https://hackmd.io/yA9DlU5YQ3WtiFxC_2LAlg
# - https://eprint.iacr.org/2020/499
# - https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html
#
# Note:
#   Halo2-like IPA is slightly different from Bulletproofs
#   (https://doc-internal.dalek.rs/bulletproofs/notes/inner_product_proof/index.html)
#   see 2019/1021, 3.1, the vector b is fixed and part of the Common Reference String
#   in our case it's instantiated to the Lagrange basis polynomial.
#   Hence the vector H mentioned in
#   https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html
#  is not necessary as well.
#
# Notation
# --------
#
# We denote the scalar multiplication [k]P = P + .... + P, done k times
# Vectors are a bar, like ā or Ḡ
# Group elements (i.e. elliptic curve) are in uppercase.
# We overload the inner product notation for the multiscalar multiplication
# i.e. ⟨ā,Ḡ⟩ = ∑ᵢ[aᵢ]Gᵢ
#
# Non-interactivity via Fiat-Shamir transform
# -------------------------------------------
#
# In the following protocol, all "random" factors are coming from a transcript.
# The transcript is reproduced by both the prover and verifier,
# based on public inputs or proof data, simulating interaction of
# challenge queries -> answers.
#
# The transcript inputs feeds a cryptographic hash function entropy pool.
# Hence the "random" outputs cannot be forged
# so that the prover cancel out terms in the following
# proving protocol relations without manipulating the polynomial they want to commit to
# (which they don't control since
#  it's the state of the Ethereum blockchain represented as a polynomial coefficients)
#
# Prover
# ------
#
# The Pedersen vector commitment is C = ⟨ā,Ḡ⟩
#
# In this implementation ā corresponds to the Lagrange evaluations
# of the polynomial we are committing to.
#
# We will prove the commitment indirectly
# via an inner product proof of the commitment
#   C' = ⟨ā,Ḡ⟩ + [⟨ā,b̄⟩]Q
#
# Q is chosen as [w]G, with w a "random" scaling factor not in control of the prover
#   and G the curve generator (which is different from Ḡ, the CRS public generators).
# b̄ are the Lagrange basis polynomials, evaluated at the opening challenge z
#
# Then we compute a new commitment
#   C'′= uL + C' + u⁻¹R
# by splitting ā, b̄, Ḡ into half: with indices l for left and r for right
#   L = ⟨āᵣ,Ḡₗ⟩ + [⟨āᵣ,b̄ₗ⟩]Q
#   R = ⟨āₗ,Ḡᵣ⟩ + [⟨āₗ,b̄ᵣ⟩]Q
#
#   Each C' is valid iff C is valid.
#   u is a "randomly sampled" challenge.
#     (Note that in actual implementation, u will be called x)
#
# For next round we set:
#   a' = āₗ + u.āᵣ i.e. it's half sized
#   b' = b̄ₗ + u⁻¹.b̄ᵣ
#   G' = Ḡₗ + [u⁻¹]Ḡᵣ
# we stop when we reach vectors of size 1
# and call such singleton a₀, b₀ and G₀.
#
# The prover sends to the verifier:
# - The evaluation at the opening challenge z of the polynomial p,
#   which is an inner product between evaluations at the evaulation domain
#   and the Lagrange basis polynomial:
#     p(z) = ∑ⱼ f(j).lⱼ(z) = ⟨ā,b̄⟩
# - The proof triplet: L̄, R̄, a₀
# The verifier can recompute the rest as they are all public.
#
# Verifier
# --------
#
# The verifier then can check whether the following relation holds true:
#
#     ∑ᵢ[uᵢ]Lᵢ + C' + ∑ᵢ[uᵢ⁻¹]Rᵢ = a₀G₀ + [a₀.b₀]Q
#
# Notice that Lᵢ and Rᵢ are log₂ the length of ā

type IpaProof*[logN: static int, EC, F] = object
  # Notation from https://eprint.iacr.org/2019/1021.pdf
  L*{.align: 64.}: array[logN, EC] # arrays of left elements for each of the log₂(N) iterations of ipa_prove
  R*{.align: 64.}: array[logN, EC] # arrays of right elements for each of the log₂(N) iterations of ipa_prove
  a0*: F                           # unique a0 coefficient after recursively

func innerProduct[F](r: var F, a, b: View[F]) =
  ## Compute the inner product ⟨a, b⟩ = ∑aᵢ.bᵢ
  debug: doAssert a.len == b.len
  r.setZero()
  for i in 0 ..< a.len:
    var t {.noInit.}: F
    t.prod(a[i], b[i])
    r += t

func ipa_commit*[N: static int, EC, F](
      crs: PolynomialEval[N, EC],
      r: var EC,
      poly: PolynomialEval[N, F]) =
  crs.pedersen_commit(r, poly)

func ipa_prove*[N, logN: static int, EcAff, F](
      crs: PolynomialEval[N, EcAff],
      domain: PolyEvalLinearDomain[N, F],
      transcript: var EthVerkleTranscript,
      eval_at_challenge: var F,
      proof: var IpaProof[logN, EcAff, F],
      poly: PolynomialEval[N, F],
      commitment: EcAff,
      opening_challenge: F) =

  static:
    doAssert N.isPowerOf2_vartime()
    doAssert logN == N.log2_vartime()

  when EcAff is ECP_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  # Allocs
  # -----------------------------------
  let basisPolysOpened = allocHeapAligned(array[N, F])
  domain.getLagrangeBasisPolysAt(basisPolysOpened[], opening_challenge)

  let gprime = allocHeapArrayAligned(Ec, N div 2)

  # Aliases and unowned views for zero-copy splitting
  # -------------------------------------------------
  var a = poly.evals.toView()
  var G = crs.evals.toView()
  var b = basisPolysOpened[].toView()

  # Protocol
  # -------------------------------------------------
  transcript.domainSeparator("ipa")

  eval_at_challenge.innerProduct(a, b)

  # Feed the transcript entropy pool so that the prover
  # cannot forge special scalars, b is fixed so no need to feed it.
  transcript.absorb("C", commitment)
  transcript.absorb("input point", opening_challenge)
  transcript.absorb("output point", eval_at_challenge)

  # "Random" basis for challenging the inner product proof.
  var w {.noInit.}: matchingOrderBigInt(F.C)
  var Q {.noInit.}: EC
  Q.generator()
  transcript.squeezeChallenge("w", w)
  Q.scalarMul_vartime(w)

  # log₂(N) round of recursive proof compression
  for i in 0 ..< logN:
    # L = ⟨āᵣ,Ḡₗ⟩ + [⟨āᵣ,b̄ₗ⟩]Q
    # R = ⟨āₗ,Ḡᵣ⟩ + [⟨āₗ,b̄ᵣ⟩]Q
    let (aL, aR) = a.splitHalf()
    let (gL, gR) = G.splitHalf()
    let (bL, bR) = b.splitHalf()

    var aRbL {.noinit.}, aLbR {.noInit.}: F
    var aRbL_Q {.noinit.}, aLbR_Q {.noInit.}: EC
    aRbL.innerProduct(aR, bL)
    aLbR.innerProduct(aL, bR)
    aRbL_Q.scalarMul_vartime(aRbL, Q)
    aLbR_Q.scalarMul_vartime(aLbR, Q)

    # We could compute [⟨āᵣ,b̄ₗ⟩]Q and [⟨āₗ,b̄ᵣ⟩]Q in the MSMs
    # but that's extra allocations / data movements.
    var lrAff {.noInit.}: array[2, EcAff]
    var lr    {.noInit.}: array[2, Ec]
    gL.pedersen_commit(lr[0], aR)
    gR.pedersen_commit(lr[1], aL)
    lr[0] ~+= aRbL_Q
    lr[1] ~+= aLbR_Q

    lrAff.batchAffine(lr)
    transcript.absorb("L", lrAff[0])
    transcript.absorb("R", lrAff[1])
    proof.buf.L[i] = lrAff[0]
    proof.buf.R[i] = lrAff[1]

    var x {.noInit.}, xinv {.noInit.}: F
    transcript.squeezeChallenge("x", x)
    xinv.inv(x)

    # Change of basis for next round
    # a' = āₗ + x.āᵣ
    # b' = b̄ₗ + x⁻¹.b̄ᵣ
    # G' = Ḡₗ + [x⁻¹]Ḡᵣ
    for j in 0 ..< aL.len:
      var xar {.noInit.}: F
      xar.prod(x, aR[j])
      aL[j] += xar
    a = aL

    if i == logN-1:
      break

    for j in 0 ..< bL.len:
      var xinvbr {.noInit.}: F
      xinvbr.prod(xinv, bR[j])
      bL[j] += xinvbr
    b = bL

    let xinvbig {.noInit.} = xinv.toBig()
    for j in 0 ..< gL.len:
      gprime[j].fromAffine(gR[j])
      gprime[j].scalarMul_vartime(xinvbig)
      gprime ~+= gL[j]

    batchAffine(
      gL.toOpenArray(),
      gprime.toOpenArray(0, gL.len-1)
    )
    G = gL

  proof.a0 = a[0]

  # Deallocs
  # -----------------------------------
  freeHeapAligned(gprime)
  freeHeapAligned(b)

func computeChangeOfBasisFactors[F](
      s: MutableView[F],
      u: View[F],
      multiplier: F) =
  ## Compute the successive change of basis factors.
  ## To be applied via inner-product / Multi-scalar-mul.
  # from https://eprint.iacr.org/2019/1021.pdf
  # Eq (1) in 3.1 Modified Inner Product, p8
  #
  #   s̄ = (
  #     u₁⁻¹ u₂⁻¹ … uₖ⁻¹,
  #     u₁   u₂⁻¹ … uₖ⁻¹,
  #     u₁⁻¹ u₂   … uₖ⁻¹,
  #     u₁   u₂   … uₖ⁻¹,
  #     ⋮    ⋮      ⋮
  #     u₁   u₂   … uₖ
  #   )
  #
  # However this is for the following in the paper
  #  G' <- [uⱼ⁻¹]Ḡₗ + [uⱼ]Ḡᵣ
  #
  # while we have
  #  G' = Ḡₗ + [x⁻¹]Ḡᵣ
  #
  # The vector is
  #   s̄(X) = ∏ᵢ₌₀ᵏ⁻¹ (1 + uₖ₋₁₋ᵢ) X²^ⁱ
  #
  # See https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html#only-compute-basis-changes-at-the-end
  debug: doAssert s.len == 1 shl u.len
  s[0].addr.zeroMem(sizeof(F) * s.len)
  s[0] = multiplier

  # With k = s.len, the domain length,
  # we have log₂(k) iterations
  for j in countdown(u.len-1, 0):
    let L = 1 shl (u.len-1-j)
    # Number of multiplications:
    #   ∑ⱼ₌₀ˡᵒᵍ²⁽ᵏ⁾⁻¹ 2ⁱ⁻¹ = 2ˡᵒᵍ²⁽ᵏ⁾-1 = k-1
    #   using sum of consecutive powers of 2 formula.
    # So we're linear in the domain size
    for i in 0 ..< L:
      s[L+i].prod(s[i], u[j])

func computeChangeOfBasisFactors[F](
      s: MutableView[F],
      u: View[F]) =
  var one {.noInit.}: F
  one.setOne()
  s.computeChangeOfBasisFactors(u, one)

func ipa_verify*[N, logN: static int, EcAff, F](
      crs: PolynomialEval[N, EcAff],
      domain: PolyEvalLinearDomain[N, F],
      transcript: var EthVerkleTranscript,
      commitment: EcAff,
      opening_challenge: F,
      eval_at_challenge: F,
      proof: IpaProof[logN, EcAff, F]): bool =
  # We want to check ∑ᵢ[uᵢ]Lᵢ + C' + ∑ᵢ[uᵢ⁻¹]Rᵢ = a₀G₀ + [a₀.b₀]Q
  # ∑ᵢ[uᵢ]Lᵢ + C' + ∑ᵢ[uᵢ⁻¹]Rᵢ = a₀G₀ + [a₀.b₀]Q
  # with
  #   The modified commitment C' = ⟨ā,Ḡ⟩ + [⟨ā,b̄⟩]Q
  #   Q = [w]G
  # We will use a MSM check with the following terms, in this order:
  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]Rᵢ + [⟨ā,b̄⟩.w]G - [a₀]G₀ - [a₀.b₀.w]G = -⟨ā,Ḡ⟩

  static:
    doAssert N.uint.isPowerOf2_vartime()
    doAssert logN == N.uint.log2_vartime()

  when EcAff is ECP_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  # Allocs
  # -----------------------------------
  let fsBuf = allocHeapAligned(array[2*logN+2+N+1, F], alignment = 64)
  let ecsBuf = allocHeapAligned(array[2*logN+2+N+1, EcAff], alignment = 64)

  let b = allocHeapAligned(array[N, F], alignment = 64)
  domain.getLagrangeBasisPolysAt(b[], opening_challenge)

  # Aliases
  # -----------------------------------
  let fs  = fsBuf.toMutableView()
  let ecs = ecsBuf.toMutableView()

  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]R
  let (xs, xinvs) = fs.chunk(0, 2*logN).splitHalf()
  let (L, R) = ecs.chunk(0, 2*logN).splitHalf()


  # [⟨ā,b̄⟩.w]G
  let fs_abwg = fs.chunk(2*logN, 1)
  let ecs_abwg = ecs.chunk(2*logN, 1)

  # -[a₀]G₀
  let fs_a0g0 = fs.chunk(2*logN+1, N)
  let ecs_a0g0 = ecs.chunk(2*logN+1, N)

  # -[a₀.b₀.w]G
  let fs_a0b0wG = fs.chunk(2*logN+1+N, 1)
  let ecs_a0b0wG = ecs.chunk(2*logN+1+N, 1)

  # Protocol
  # -------------------------------------------------
  transcript.domainSeparator("ipa")

  transcript.absorb("C", commitment)
  transcript.absorb("input point", opening_challenge)
  transcript.absorb("output point", eval_at_challenge)

  # "Random" basis for challenging the inner product proof.
  # Q = [w]G, but we delay Q computation to amortize it in MSM
  var w {.noInit.}: F
  transcript.squeezeChallenge("w", w)

  # Regenerate the challenges uᵢ and uᵢ⁻¹
  # (named xᵢ and xᵢ⁻¹ for Ethereum Verkle Tries spec)
  # to check ∑ᵢ[uᵢ]Lᵢ + C' + ∑ᵢ[uᵢ⁻¹]Rᵢ = [a₀]G₀ + [a₀.b₀]Q
  for i in 0 ..< logN:
    transcript.absorb("L", proof.L[i])
    transcript.absorb("R", proof.R[i])
    transcript.squeezeChallenge("x", xs[i])

  xinvs.asUnchecked().batchInv_vartime(xs.asUnchecked(), logN)

  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]Rᵢ ...
  L.copyFrom(proof.L)
  R.copyFrom(proof.R)

  # ... + [⟨ā,b̄⟩.w]G ...
  fs_abwg[0].prod(eval_at_challenge, w)
  ecs_abwg[0].generator()

  # ... - [a₀]G₀ ...
  # [a₀]G₀ = [a₀]<s̄, Ḡ>
  var neg_a0 {.noInit.}: F
  neg_a0.neg(proof.a0)
  fs_a0g0.computeChangeOfBasisFactors(View[F](xinvs), multiplier = neg_a0)
  ecs_a0g0.copyFrom(crs.evals)

  # ... - [a₀.b₀.w]G ...
  # a₀.b₀.w = a₀.w.<s̄,b̄>
  fs_a0b0wG[0].innerProduct(View[F](fs_a0g0), b.toView())
  fs_a0b0wG[0] *= w
  ecs_a0b0wG[0].generator()

  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]Rᵢ + [⟨ā,b̄⟩.w]G - [a₀]G₀ - [a₀.b₀.w]G
  var t {.noInit.}: EC
  t.multiScalarMul_reference_vartime(fs.toOpenArray(), ecs.toOpenArray())

  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]Rᵢ + [⟨ā,b̄⟩.w]G - [a₀]G₀ - [a₀.b₀.w]G = -⟨ā,Ḡ⟩
  var C {.noInit.}: EC
  C.fromAffine(commitment)
  C.neg()
  result = bool(t == C)

  # Deallocs
  # -----------------------------------
  freeHeapAligned(b)
  freeHeapAligned(ecsBuf)
  freeHeapAligned(fsBuf)
