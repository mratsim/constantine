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
  ./protocol_quotient_check,
  constantine/named/algebras,
  constantine/math/polynomials/polynomials,
  constantine/math/[arithmetic, ec_shortweierstrass, ec_twistededwards],
  constantine/math/elliptic/ec_multi_scalar_mul,
  constantine/math/io/io_fields,
  constantine/platforms/[abstractions, views]

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
#   which is an inner product between evaluations at the evaluation domain
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

{.push raises: [], checks: off.} # No exceptions

type IpaProof*[logN: static int, EcAff, F] = object
  # Notation from https://eprint.iacr.org/2019/1021.pdf
  L*{.align: 64.}: array[logN, EcAff] # arrays of left elements for each of the log₂(N) iterations of ipa_prove
  R*{.align: 64.}: array[logN, EcAff] # arrays of right elements for each of the log₂(N) iterations of ipa_prove
  a0*: F                              # unique a0 coefficient after recursively halving commitments

func innerProduct[F](r: var F, a, b: distinct(View[F] or MutableView[F])) =
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

  # Prologue
  # -----------------------------------

  static:
    doAssert N.uint.isPowerOf2_vartime()
    doAssert logN == N.uint.log2_vartime()

  when EcAff is EC_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  # Allocs
  let aprime = allocHeapAligned(array[N, F], alignment = 64)
  let bprime = allocHeapAligned(array[N, F], alignment = 64)
  let gprime = allocHeapAligned(array[N, EcAff], alignment = 64)
  let gg = allocHeapAligned(array[N div 2, Ec], alignment = 64) # Temp for batchAffine

  # Aliases and unowned views for zero-copy splitting
  var a = aprime[].toMutableView()
  var b = bprime[].toMutableView()
  var G = gprime[].toMutableView()

  a.copyFrom(poly.evals)
  domain.computeLagrangeBasisPolysAt(bprime[], opening_challenge)
  G.copyFrom(crs.evals)

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
  var w {.noInit.}: F.getBigInt()
  var Q {.noInit.}: EC
  Q.setGenerator()
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
    gL.asView().pedersen_commit(lr[0], aR.asView())
    gR.asView().pedersen_commit(lr[1], aL.asView())
    lr[0] ~+= aRbL_Q
    lr[1] ~+= aLbR_Q

    lrAff.batchAffine(lr)
    transcript.absorb("L", lrAff[0])
    transcript.absorb("R", lrAff[1])
    proof.L[i] = lrAff[0]
    proof.R[i] = lrAff[1]

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
      gg[j].fromAffine(gR[j])
      gg[j].scalarMul_vartime(xinvbig)
      gg[j] ~+= gL[j]

    batchAffine(
      gL.asUnchecked(),
      gg[].asUnchecked(),
      gL.len
    )
    G = gL

  proof.a0 = a[0]

  # Epilogue
  # -----------------------------------
  freeHeapAligned(gg)
  freeHeapAligned(gprime)
  freeHeapAligned(bprime)
  freeHeapAligned(aprime)

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
    #   ∑ⱼ₌₀ˡᵒᵍ²⁽ᵏ⁾⁻¹ 2ʲ⁻¹ = 2ˡᵒᵍ²⁽ᵏ⁾-1 = k-1
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

  # Prologue
  # -----------------------------------
  static:
    doAssert N.uint.isPowerOf2_vartime()
    doAssert logN == N.uint.log2_vartime()

  when EcAff is EC_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  # Allocs
  let fsBuf = allocHeapAligned(array[2*logN+1+N+1, F], alignment = 64)
  let ecsBuf = allocHeapAligned(array[2*logN+1+N+1, EcAff], alignment = 64)
  let b = allocHeapAligned(array[N, F], alignment = 64)

  # Aliases
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
  ecs_abwg[0].setGenerator()

  # ... - [a₀]G₀ ...
  # [a₀]G₀ = [a₀]<s̄, Ḡ>
  var neg_a0 {.noInit.}: F
  neg_a0.neg(proof.a0)
  fs_a0g0.computeChangeOfBasisFactors(View[F](xinvs), multiplier = neg_a0)
  ecs_a0g0.copyFrom(crs.evals)

  # ... - [a₀.b₀.w]G ...
  # a₀.b₀.w = a₀.w.<s̄,b̄>
  domain.computeLagrangeBasisPolysAt(b[], opening_challenge)
  fs_a0b0wG[0].innerProduct(View[F](fs_a0g0), b.toView())
  fs_a0b0wG[0] *= w
  ecs_a0b0wG[0].setGenerator()

  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]Rᵢ + [⟨ā,b̄⟩.w]G - [a₀]G₀ - [a₀.b₀.w]G
  var t {.noInit.}: EC
  t.multiScalarMul_vartime(fs.toOpenArray(), ecs.toOpenArray())

  # ∑ᵢ[uᵢ]Lᵢ + ∑ᵢ[uᵢ⁻¹]Rᵢ + [⟨ā,b̄⟩.w]G - [a₀]G₀ - [a₀.b₀.w]G = -⟨ā,Ḡ⟩
  var C {.noInit.}: EC
  C.fromAffine(commitment)
  C.neg()

  # Epilogue
  # -----------------------------------
  freeHeapAligned(b)
  freeHeapAligned(ecsBuf)
  freeHeapAligned(fsBuf)

  return bool(t == C)

## ############################################################
##
##                    IPA Multiproofs
##
## ############################################################
#
# Write-ups:
# - https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
# - https://hackmd.io/7vIMcrgtTOKyvvtziTf0HA
#
# Specs:
# - https://github.com/crate-crypto/verkle-trie-ref/blob/2332ab8/multiproof/multiproof.py
#
# The protocol is applicable to any univariate polynomial commitment scheme (PCS)
# However, for PCS based on pairings like KZG, we can exploit the bilinearity of pairings
# to be significantly more efficient and ergonomic.

type IpaMultiProof*[logN: static int, EcAff, F] = object
  g2_proof*: IpaProof[logN, EcAff, F] # A proof of a commitment to a polynomial g₂(t) constructed from all polynomials
  D*: EcAff                           # A commitment to the combining polynomial g(t) = g₁(t) - g₂(t)

func sorterByChallenge[N: static int](
      challenges_counts: var array[N, uint32],
      sortingKeys: ptr UncheckedArray[tuple[z, idx: uint32]],
      opening_challenges_in_domain: ptr UncheckedArray[SomeInteger],
      num_queries: int): int =
  ## Computes metadata necessary to group polynomials by challenge
  ## - Returns the number of distinct opening challenges
  ## - in-place update the count of individual challenges
  ## - in-place update a list of polynomial indices in original array, sorted by ascending challenges
  ##
  ## This assumes N is small.

  # Computation outline:
  # 1. Getting quotient polynomials in-domain is *very* costly
  #    as (p(x) - p(z)) / (x - z):
  #      { qᵢ = (p(xᵢ) - p(z))/(xᵢ-z), i != z with 1/(xᵢ-z) precomputable
  #      { qz = - ∑ᵢ A'(z)/A'(xᵢ) qᵢ, i == z, with A'(z)/A'(xᵢ) precomputable
  #
  # To solve 1, we can sum polys evaluated at the same opening challenges before hand
  # and only then divide.
  #
  # 2. We want to find the polys evaluated at the same opening challenges while minimizing
  #    - allocations
  #    - data movement, especially polynomials should not be copied as they are big
  #    - passes over the data, ideally O(n)
  #
  # To solve 2, we use counting sort
  #    - with a time complexity O(N+num_queries), N being our domain size.
  #    - with a space complexity of O(N+num_queries)
  # and we modify it to sort polynomial indexes instead of polynomials themselves
  # to save space.

  # Allocs
  # -----------------------------------
  let cdf = allocHeapAligned(array[N, uint32], alignment = 64)

  # Counting sort
  # -----------------------------------
  zeroMem(challenges_counts.addr, sizeof(challenges_counts))
  for q in 0 ..< num_queries:
    let z = opening_challenges_in_domain[q]
    challenges_counts[z] += 1

  # Compute the cumulative distribution of opening challenges
  cdf[0] = challenges_counts[0]
  var distinct_challenges = int(challenges_counts[0] > 0) # We want int (or any integer) without exceptions
  for i in 1 ..< N:
    cdf[i] = challenges_counts[i] + cdf[i-1]
    if challenges_counts[i] > 0:
      distinct_challenges += 1

  # Deduce sorting keys
  for q in countdown(num_queries-1, 0):
    let z = opening_challenges_in_domain[q]
    cdf[z] -= 1
    sortingKeys[cdf[z]].z = uint32 z
    sortingKeys[cdf[z]].idx = uint32 q

  # Deallocs
  # -----------------------------------
  freeHeapAligned(cdf)

  return distinct_challenges

func sumPolysByChallenge[N: static int, F](
      zs: ptr UncheckedArray[uint32],
      fs: ptr UncheckedArray[PolynomialEval[N, F]],
      challenges_counts: array[N, uint32],
      ungrouped_polys: ptr UncheckedArray[PolynomialEval[N, F]],
      sortingKeys: ptr UncheckedArray[tuple[z, idx: uint32]],
      num_queries: int) =
  ## Returns a sparse representation of:
  ## - a vector of polynomials: fᵢ(X)
  ## - a vector of corresponding challenges zⁱ
  ## sorted by ascending zⁱ.
  ##
  ## The original polynomials are
  ## summed if evaluated on the same challenge zⁱ
  ## to form fᵢ(X)
  ##
  ## Those are necessary precompute for:
  ##   g(X) = r⁰(f₀(X)-y₀)/(X-z₀) + r¹(f₁(X)-y₁)/(X-z₁) + ... + rⁿ⁻¹(fₙ₋₁(X)-yₙ₋₁)/(X-zₙ₋₁)
  ##        = ∑rⁱ.(fᵢ(X)-fᵢ(zᵢ)/(X-zᵢ))
  ##   g₁(t) = ∑rⁱ.fᵢ(t)/(t-zᵢ)
  ## for polynomials in evaluation form, evaluated at a linear domain [0, N)
  ##
  ## Outputs zs anbd fs are arrays of length the number of distinct challenges
  ## This is implicit from challenges_counts
  ##
  ## Inputs are arrays of length num_queries

  # TODO: do we need proper SparseVector data structures?

  var q = 0'u32
  var idx = 0
  while q < cast[uint32](num_queries):
    let z = sortingKeys[q].z
    zs[idx] = z
    let count = challenges_counts[z]
    if count == 1:
      fs[idx] = ungrouped_polys[sortingKeys[q].idx]
    else:
      fs[idx].sum(
        ungrouped_polys[sortingKeys[q].idx],
        ungrouped_polys[sortingKeys[q+1].idx])
      for i in 2 ..< count:
        fs[idx] += ungrouped_polys[sortingKeys[i].idx]

    q += count
    idx += 1

func sumCommitmentsAndEvalsByChallenge[N: static int, F, ECaff](
      zs: ptr UncheckedArray[uint32],
      comms_by_challenges: ptr UncheckedArray[ECaff],
      evals_by_challenges: ptr UncheckedArray[F],
      challenges_counts: array[N, uint32],
      ungrouped_comms: ptr UncheckedArray[ECaff],
      ungrouped_evals: ptr UncheckedArray[F],
      sortingKeys: ptr UncheckedArray[tuple[z, idx: uint32]],
      num_queries: int) =
  ## Returns a sparse representation of:
  ## - a vector of evaluations: fᵢ(zᵢ)
  ## - a vector of corresponding challenges zᵢ
  ## sorted by ascending zⁱ.
  ##
  ## The original evaluations are
  ## summed if evaluated on the same challenge zⁱ
  ## to form fᵢ(zᵢ)
  ##
  ## Outputs zs and evals_by_challenges are arrays of length the number of distinct challenges
  ## This is implicit from challenges_counts
  ##
  ## Inputs are arrays of length num_queries

  # TODO: do we need proper SparseVector data structures?

  var affNeeded = 0

  block: # Group evals, and check how much to allocate for batch inversion
    var q = 0'u32
    var eidx = 0
    while q < cast[uint32](num_queries):
      let z = sortingKeys[q].z
      zs[eidx] = z
      let count = challenges_counts[z]
      if count == 1:
        evals_by_challenges[eidx] = ungrouped_evals[sortingKeys[q].idx]
      else:
        affNeeded += 1
        evals_by_challenges[eidx].sum(
          ungrouped_evals[sortingKeys[q].idx],
          ungrouped_evals[sortingKeys[q+1].idx])
        for i in 2 ..< count:
          evals_by_challenges[eidx] += ungrouped_evals[sortingKeys[i].idx]

      q += count
      eidx += 1

  when EcAff is EC_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  # ! affNeeded may be zero, in that case the pointers MUST not be dereferenced.
  let idxmap = allocHeapArrayAligned(uint32, affNeeded, alignment = 64)
  let tmpAff = allocHeapArrayAligned(ECaff, affNeeded, alignment = 64)
  let tmp = allocHeapArrayAligned(EC, affNeeded, alignment = 64)

  block: # Group commitments
    var q = 0'u32
    var cidx = 0'u32
    var tidx = 0'u32
    while q < cast[uint32](num_queries):
      let z = sortingKeys[q].z
      let count = challenges_counts[z]
      if count == 1:
        comms_by_challenges[cidx] = ungrouped_comms[sortingKeys[q].idx]
      else:
        idxmap[tidx] = cidx
        tmp[tidx].fromAffine(ungrouped_comms[sortingKeys[q].idx])
        for i in 1 ..< count:
          tmp[tidx] ~+= ungrouped_comms[sortingKeys[i].idx]
        tidx += 1

      q += count
      cidx += 1

  if affNeeded > 0:
    tmpAff.batchAffine(tmp, affNeeded) # TODO: introduce batchAffine_vartime
    for i in 0 ..< affNeeded:
      comms_by_challenges[idxmap[i]] = tmpAff[i]

  freeHeapAligned(tmp)
  freeHeapAligned(tmpAff)
  freeHeapAligned(idxmap)

func ipa_multi_prove*[N, logN: static int, EcAff, F](
      crs: PolynomialEval[N, EcAff],
      domain: PolyEvalLinearDomain[N, F],
      transcript: var EthVerkleTranscript,
      proof: var IpaMultiProof[logN, EcAff, F],
      polys: openArray[PolynomialEval[N, F]],
      commitments: openArray[EcAff],
      opening_challenges_in_domain: openArray[SomeUnsignedInt]) =
  ## Create a combined proof that
  ## allow verifying the list of triplets
  ##    (polynomial, commitment, opening challenge)
  ## with
  ##    (commitment, opening challenge, eval at challenge)

  # Prologue
  # -----------------------------------

  debug:
    doAssert polys.len == commitments.len, "Polynomials and commitments inputs must be of the same length"
    doAssert polys.len == opening_challenges_in_domain.len, "Polynomials and opening challenges inputs must be of the same length"

  when EcAff is EC_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  let num_queries = polys.len # Number of queries to convince a verifier that we indeed committed to all polynomials

  let challenges_counts = allocHeapAligned(array[N, uint32], alignment = 64)
  let sortingKeys = allocHeapArrayAligned(tuple[z, idx: uint32], num_queries, alignment = 64)

  let num_distinct_challenges =
    sorterByChallenge(
      challenges_counts[],
      sortingKeys,
      opening_challenges_in_domain.asUnchecked(),
      num_queries)

  # Sparse data by distinct challenges
  let sparse_challenges = allocHeapArrayAligned(uint32, num_distinct_challenges, alignment = 64)
  let polys_by_challenges = allocHeapArrayAligned(PolynomialEval[N, F], num_distinct_challenges, alignment = 64)

  # Compute the sparse challenges and the summed polys
  sparse_challenges.sumPolysByChallenge(
    polys_by_challenges,
    challenges_counts[],
    polys.asUnchecked(),
    sortingKeys,
    num_queries)

  # It is stressing the allocator to not free in reverse of allocation
  # But we have many allocations afterwards
  freeHeapAligned(sortingKeys)
  freeHeapAligned(challenges_counts)

  let g2 = allocHeapAligned(PolynomialEval[N, F], alignment = 64)
  let g1 = allocHeapAligned(PolynomialEval[N, F], alignment = 64)
  let g = allocHeapAligned( PolynomialEval[N, F], alignment = 64)
  let invTminusChallenges = allocHeapArrayAligned(F, num_distinct_challenges, alignment = 64)
  let rpowers = allocHeapArrayAligned(F, num_distinct_challenges, alignment = 64)

  # Protocol
  # -------------------------------------------------
  transcript.domain_separator("multiproof")

  for i in 0 ..< num_queries:
    transcript.absorb("C", commitments[i])
    transcript.absorb("z", F.fromUint(opening_challenges_in_domain[i]))
    transcript.absorb("y", polys[i].evals[opening_challenges_in_domain[i]])

  # Random r via Fiat-Shamir that the prover cannot manipulate
  # to compute an IPA proof to
  #   g(X) = r⁰(f₀(X)-y₀)/(X-z₀) + r¹(f₁(X)-y₁)/(X-z₁) + ... + rⁿ⁻¹(fₙ₋₁(X)-yₙ₋₁)/(X-zₙ₋₁)
  # with
  #   fᵢ being polys[i]
  #   zᵢ being the opening challenges, in domain i.e. in [0, N)
  #   yᵢ being the corresponding evaluations, as we are in evaluation form it's polys[i][zᵢ]
  var r {.noInit.} : F
  transcript.squeezeChallenge("r", r)

  # We need linearly independent numbers for batch proof sampling.
  # The Ethereum Verkle protocol mandates powers of r.
  rpowers.computeSparsePowers_vartime(r, sparse_challenges, num_distinct_challenges)

  # Compute rⁱ.fᵢ(X)
  for i in 0 ..< num_distinct_challenges:
    polys_by_challenges[i] *= rpowers[i]
  freeHeapAligned(rpowers)

  # Compute combining polynomial
  #   g(X) = ∑rⁱ.(fᵢ(X)-yᵢ)/(X-zᵢ) = r⁰(f₀(X)-y₀)/(X-z₀) + r¹(f₁(X)-y₁)/(X-z₁) + ... + rⁿ⁻¹(fₙ₋₁(X)-yₙ₋₁)/(X-zₙ₋₁)
  # As yᵢ = fᵢ(zᵢ)
  #   quotient_poly(rⁱfᵢ(X), zᵢ) == rⁱ.quotient_poly(fᵢ(X), zᵢ)
  block:
    domain.getQuotientPolyInDomain(
      g[],
      polys_by_challenges[0],
      sparse_challenges[0])

    let t = g2 # We use g2 as temporary
    t.zeroMem(sizeof(t[]))
    for i in 1 ..< num_distinct_challenges:
      domain.getQuotientPolyInDomain(
        t[],
        polys_by_challenges[i],
        sparse_challenges[i])
      g[] += t[]

  # Commit to the combining polynomial g(X) = ∑rⁱ.(fᵢ(X)-yᵢ)/(X-zᵢ)
  var D {.noInit.}: EC
  crs.pedersen_commit(D, g[])
  proof.D.affine(D)
  transcript.absorb("D", proof.D)

  # Evaluate at random t: g(t) = ∑rⁱ.(fᵢ(t)-yᵢ)/(t-zᵢ)
  var t {.noinit.}: F
  transcript.squeezeChallenge("t", t)

  # And split g(t) = ∑rⁱ.fᵢ(t)/(t-zᵢ) - ∑rⁱ.yᵢ/(t-zᵢ)
  # g(t) = g₁(t) - g₂(t)
  # g₂(t) can be recomputed by the verifier
  # g₁(t) cannot as it depends on the polynomials fᵢ
  # but we will instead send commitments to g(t) and g₁(t)
  # and a proof to a commitment to g₂(t)
  # The verifier can recompute the g₂(t) commitment on their own
  # and verify the proof.

  # Compute 1/(t-zᵢ)
  discard invTminusChallenges.inverseDifferenceArray(
    sparse_challenges, num_distinct_challenges,
    t,
    differenceKind = kMinusArray,
    earlyReturnOnZero = false)

  # Compute g₁ = ∑rⁱ.fᵢ(t)/(t-zᵢ)
  g1[].prod(invTminusChallenges[0], polys_by_challenges[0])
  for i in 1 ..< num_distinct_challenges:
    g1[].multiplyAccumulate(invTminusChallenges[i], polys_by_challenges[i])

  # Reclaim some memory
  freeHeapAligned(invTminusChallenges)
  freeHeapAligned(polys_by_challenges)
  freeHeapAligned(sparse_challenges)

  # Commit to g₁ and update transcript,
  # PCSs are additively homomorphic, verifier can recompute from D - <g₁(t), CRS>
  var E {.noInit.}: EC
  crs.pedersen_commit(E, g1[])
  var Eaff {.noInit.}: ECaff
  Eaff.affine(E)
  transcript.absorb("E", Eaff)

  # Compute g₂(t) and a commitment to it
  g2[].diff(g1[], g[])
  var comm_g2 {.noInit.}: EC
  var comm_g2_aff {.noInit.}: ECaff
  comm_g2.fromAffine(Eaff)
  comm_g2 ~-= proof.D
  comm_g2_aff.affine(comm_g2)

  # Reclaim some memory
  freeHeapAligned(g)
  freeHeapAligned(g1)

  # Compute a proof to g₂(t) commitment
  var eval_at_t {.noInit.}: F
  crs.ipa_prove(
    domain,
    transcript,
    eval_at_t,
    proof.g2_proof,
    g2[],
    comm_g2_aff,
    t)

  freeHeapAligned(g2)

func ipa_multi_verify*[N, logN: static int, EcAff, F](
      crs: PolynomialEval[N, EcAff],
      domain: PolyEvalLinearDomain[N, F],
      transcript: var EthVerkleTranscript,
      commitments: openArray[EcAff],
      opening_challenges_in_domain: openArray[SomeUnsignedInt],
      evals_at_challenges: openArray[F],
      proof: IpaMultiProof[logN, EcAff, F]): bool =
  ## Batch verification of commitments to multiple polynomials
  ## using a single multiproof

  # Prologue
  # -----------------------------------

  debug:
    doAssert commitments.len == opening_challenges.len, "Commitments and opening challenges inputs must be of the same length"
    doAssert commitments.len == evals_at_challenges.len, "Commitments and evaluations at challenges inputs must be of the same length"

  when EcAff is EC_ShortW_Aff:
    type EC = jacobian(EcAff)
  else: # Twisted Edwards
    type EC = projective(EcAff)

  let num_queries = commitments.len

  let challenges_counts = allocHeapAligned(array[N, uint32], alignment = 64)
  let sortingKeys = allocHeapArrayAligned(tuple[z, idx: uint32], num_queries, alignment = 64)

  let num_distinct_challenges =
    sorterByChallenge(
      challenges_counts[],
      sortingKeys,
      opening_challenges_in_domain.asUnchecked(),
      num_queries)

  # Sparse data by distinct challenges
  let comms_by_challenges = allocHeapArrayAligned(EcAff, num_distinct_challenges, alignment = 64)
  let evals_by_challenges = allocHeapArrayAligned(F, num_distinct_challenges, alignment = 64)
  let sparse_challenges = allocHeapArrayAligned(uint32, num_distinct_challenges, alignment = 64)

  # Compute the sparse challenges and the summed poly evaluations
  sparse_challenges.sumCommitmentsAndEvalsByChallenge(
    comms_by_challenges,
    evals_by_challenges,
    challenges_counts[],
    commitments.asUnchecked(),
    evals_at_challenges.asUnchecked(),
    sortingKeys,
    num_queries)

  # It is stressing the allocator to not free in reverse of allocation
  # But we have many allocations afterwards
  freeHeapAligned(sortingKeys)
  freeHeapAligned(challenges_counts)

  let invTminusChallenges = allocHeapArrayAligned(F, num_distinct_challenges, alignment = 64)
  let rpowers = allocHeapArrayAligned(F, num_distinct_challenges, alignment = 64)

  # Protocol
  # -------------------------------------------------
  transcript.domain_separator("multiproof")

  for i in 0 ..< num_queries:
    transcript.absorb("C", commitments[i])
    transcript.absorb("z", F.fromUint(cast[uint](opening_challenges_in_domain[i])))
    transcript.absorb("y", evals_at_challenges[i])

  # Random r via Fiat-Shamir that the prover cannot manipulate
  var r {.noInit.} : F
  transcript.squeezeChallenge("r", r)

  # We need linearly independent numbers for batch proof sampling.
  # The Ethereum Verkle protocol mandates powers of r.
  rpowers.computeSparsePowers_vartime(r, sparse_challenges, num_distinct_challenges)

  # Add the commit to the combining polynomial g(X) to transcript
  transcript.absorb("D", proof.D)

  # Evaluate at random t: g(t) = ∑rⁱ.(fᵢ(t)-yᵢ)/(t-zᵢ)
  var t {.noinit.}: F
  transcript.squeezeChallenge("t", t)

  # And split g(t) = ∑rⁱ.fᵢ(t)/(t-zᵢ) - ∑rⁱ.yᵢ/(t-zᵢ)
  # g(t) = g₁(t) - g₂(t)
  # g₂(t) can be recomputed including the commitment
  # g₁(t) cannot but we can deduce its commitment
  # as we have the commitment D from g and PCSs are homomorphic

  # Compute 1/(t-zᵢ)
  discard invTminusChallenges.inverseDifferenceArray(
    sparse_challenges, num_distinct_challenges,
    t,
    differenceKind = kMinusArray,
    earlyReturnOnZero = false)
  freeHeapAligned(sparse_challenges)

  # Compute rⁱ/(t-zᵢ)
  for i in 0 ..< num_distinct_challenges:
    invTminusChallenges[i] *= rpowers[i]
  freeHeapAligned(rpowers)

  # Compute g₂(t) = ∑rⁱ.yᵢ/(t-zᵢ)
  var g2t {.noInit.}: F
  g2t.setZero()

  for i in 0 ..< num_distinct_challenges:
    var tmp {.noInit.}: Fr[Banderwagon]
    tmp.prod(evals_by_challenges[i], invTminusChallenges[i])
    g2t += tmp
  freeHeapAligned(evals_by_challenges)

  # Compute E, a commitment to g₁ = ∑rⁱ.fᵢ(t)/(t-zᵢ)
  # E = ∑rⁱ.Cᵢ/(t-zᵢ)
  var E {.noInit.}: EC
  var Eaff {.noInit.}: EcAff
  E.multiScalarMul_vartime(invTminusChallenges, comms_by_challenges, num_distinct_challenges)
  Eaff.affine(E)
  transcript.absorb("E", Eaff)
  freeHeapAligned(invTminusChallenges)
  freeHeapAligned(comms_by_challenges)

  # Deduce the commitment to g₂ from the homomorphic commitment property
  var comm_g2 {.noInit.}: EC
  var comm_g2_aff {.noInit.}: ECaff
  comm_g2.fromAffine(Eaff)
  comm_g2 ~-= proof.D
  comm_g2_aff.affine(comm_g2)

  # Verify the commitment to g₂ which verifies commitment to g
  # and so all combined polynomials
  return crs.ipa_verify(
    domain, transcript,
    comm_g2_aff, t,
    g2t, proof.g2_proof)
