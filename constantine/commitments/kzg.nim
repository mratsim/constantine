# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  ../math/[ec_shortweierstrass, arithmetic, extension_fields],
  ../math/elliptic/[ec_multi_scalar_mul, ec_shortweierstrass_batch_ops],
  ../math/pairings/pairings_generic,
  ../named/zoo_generators,
  ../math/polynomials/polynomials,
  ../platforms/abstractions,
  ./protocol_quotient_check

## ############################################################
##
##                 KZG Polynomial Commitments
##
## ############################################################
##
## This module implements KZG-inspired Polynomial commitments (Kate, Zaverucha, Goldberg)
##
## - KZG Paper:
##   Constant-Size Commitments to Polynomials and Their Applications
##   Kate, Zaverucha, Goldberg, 2010
##   https://www.iacr.org/archive/asiacrypt2010/6477178/6477178.pdf
##   https://cacr.uwaterloo.ca/techreports/2010/cacr2010-10.pdf
##
##
## KZG-inspired protocol
## ------------------------------------------------------------
##
## Quick algebra refresher for developers
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##
## - A group is a set of elements:
##   - with a binary operation to combine them called the group law
##   - with a neutral element
##   - with an inverse, applying the group law on an element and its inverse results in the neutral element.
##
##   - the group order or cardinality is the number of elements in the set
##   - the group can use the additive or multiplicative notation.
##   - the group can be cyclic. i.e. all elements of the group can be generated
##     by repeatedly applying the group law.
##
##   The additive/multiplicative notation is chosen by social consensus,
##   hence confusion of scalar multiplication [a]P or exponentiation Pᵃ for elliptic curves.
##
## - A field is a set of elements
##   - with two group laws, addition and multiplication
##   - and the corresponding group properties (additive/multiplicative inverse and neutral elements)
##
##   - A field can be finite (modular arithmetic modulo a prime) or infinite (the real numbers)
##
## Sigil refreshers for developers
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##
## - ∃: there exists
## - ∀: for all
## - ∈: element of
##
## Notation
## ~~~~~~~~
##
##   - 𝔽r is a finite-field of prime order r
##   - 𝔾1 is an additive group of prime order r
##   - 𝔾2 is an additive group of prime order r
##   - 𝔾t is a multiplicative group of prime order r
##
##   In practice:
##     - ∀(x, y) such that y² = x³ + b has a cyclic group of r solutions, the group 𝔾1 (of the elliptic curve E1)
##     - ∀(x', y') such that y'² = x'³ + b' has a cyclic group of r solutions, the group 𝔾2 (of the elliptic curve E2)
##     - 𝔾t is also a cyclic subgroup of order r
##     - r is the (large prime) number of elements in all those subgroups.
##
## - Implementation details (for the very curious)
##     - For 𝔾1, (x, y) ∈ (𝔽p, 𝔽p)
##     - For 𝔾2, (x', y') ∈ (𝔽pⁿ, 𝔽pⁿ) with n = 2 usually (BN and BLS12 curves), but it can be 1 (BW6 curves), 4 (BLS24 curves) or ...
##     - 𝔾t is the cyclotomic subgroup over 𝔽pᵏ, k being the curve embedding degree, with k = 12 usually (BN and BLS12 curves) but it can be 6 (BW6 curves), 24 (BLS24 curves) or ...
##     - p is completely unused in the protocol so don't use mental space to keep these details.
##
##   We use the notation:
##     [a]P to represent P+P+ .... + P
##     Applying the group law `a` times, i.e. the scalar multiplication.
##
##   There exist a pairing function (bilinear map)
##     e: 𝔾1 x 𝔾2 -> 𝔾t
##   That map is bilinear
##   ∀a ∈ 𝔽r, ∀b ∈ 𝔽r, ∀P ∈ 𝔾1, ∀Q ∈ 𝔾2,
##   e([a]P, [b]Q) = e(P, Q)ᵃᵇ
##
##   We use the notation:
##     G₁ for the protocol-chosen generator of 𝔾1
##     G₂ for the protocol-chosen generator of 𝔾2
##     [a]₁ for the scalar multiplication of the 𝔾1 generator by a, a ∈ 𝔽r
##     [b]₂ for the scalar multiplication of the 𝔾2 generator by b, b ∈ 𝔽r
##
## Polynomial Commitment Scheme
## ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##
## We have 2 parties, a Prover and a Verifier.
##
## They share a public Structured Reference String (SRS), also called trusted setup:
##   srs_g1: [[1]₁, [τ]₁, [τ²]₁, ... [τⁿ⁻¹]₁] also called powers of tau, with a bounded degree n-1
##   srs_g2: [[1]₂, [τ]₂]
##
## τ and its powers are secrets that no one knows, we only work with [τⁱ]₁ and [τ]₂
## not with τ directly. (τ cannot be deduced due to the elliptic curve discrete logarithm problem)
##
## Info
##   τ and its powers are created through a secure multi-party computation (MPC) ceremony
##   called powers of tau. Each participant contributes randomness.
##   Only one honest participant (who ensures that the randomness created cannot be recreated)
##   is necessary for the success of the ceremony.
##
## Protocol
##
## 0. A data blob is interpreted as up to n 𝔽r elements
##    corresponding to a polynomial p(x) = blob₀ + blob₁ x + blob₂ x² + ... + blobₙ₋₁ xⁿ⁻¹
##                                  p(x) = ∑₀ⁿ⁻¹ blobᵢ xⁱ
##
##    So we can commit/prove up to n*log₂(r) bits of data
##    For Ethereum, n = 4096 and log₂(r) = 255 bits
##    so 130.560kB of transaction data committed per 48B proof stored in the blockchain
##
## 1. commit(srs_g1, blob) -> commitment C = ∑ blobᵢ.srs_g1ᵢ = ∑ [blobᵢ.τⁱ]₁ = [p(τ)]₁
##
## 2. The verifier chooses a random opening_challenge `z` in 𝔽r that the prover does not control.
##    To make the protocol non-interactive, z may be computed via the Fiat-Shamir heuristic.
##
## 3. compute_proof(blob, [commitment]₁, opening_challenge) -> (eval_at_challenge, [proof]₁)
##      blob: p(x)
##      [commitment]₁: [p(τ)]₁
##      opening_challenge: z
##      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##      -> The prover needs to provide a proof that it knows a polynomial p(x)
##         such that p(z) = y. With the proof, the verifier doesn't need access to the polynomial to verify the claim.
##      -> Compute a witness polynomial w(x, z) = (p(x) - p(z)) / (x-z)
##         We can evaluate it at τ from the public SRS and opening_challenge point `z` chosen by the verifier (indifferentiable from random).
##         We don't know τ, but we know [τ]₁ so we transport the problem from 𝔽r to 𝔾1
##      => The proof is the evaluation of the witness polynomial for a opening_challenge `z` of the verifier choosing.
##         w(τ, z) = proof
##         We output [proof]₁ = [proof]G₁
##
## 4. verify_commitment([commitment]₁, opening_challenge, eval_at_challenge, [proof]₁) -> bool
##      [commitment]₁: [p(τ)]₁
##      opening_challenge: z
##      eval_at_challenge: p(z) = y
##      [proof]₁: [(p(τ) - p(z)) / (τ-z)]₁
##      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##      -> proof = w(τ, z) = (p(τ) - p(z)) / (τ-z) = (p(τ) - y) / (τ-z)
##         hence proof.(τ-z) = p(τ) - y
##
##      => using a bilinear pairing function e(𝔾1, 𝔾2)->𝔾t we can rewrite this equality to
##         e([proof]₁, [τ]₂ - [z]₂) = e(C - [y]₁, [1]₂)
##
##      According to the Schwartz-zippel Lemma it is cryptographically unlikely
##      that this equation holds unless what the prover provided for [commitment]₁ = [p(τ)]₁
##
## Variants
## - srs_g1 and blob may be either polynomial in monomial basis
##   p(x) = blob₀ + blob₁ x + blob₂ x² + ... + blobₙ₋₁ xⁿ⁻¹
## - or polynomial in Lagrange basis, defined over tuples
##   [(ω⁰, p(ω⁰)), (ω¹, p(ω¹)), (ω², p(ω²)), ..., (ωⁿ⁻¹, p(ωⁿ⁻¹))]
##   with ω ∈ 𝔽r a root of unity of order n, i.e. ωⁿ = 1

# KZG - Prover - Lagrange basis
# ------------------------------------------------------------
#
# For now we assume that the input polynomial always has the same degree
# as the powers of τ

func kzg_commit*[N, bits: static int, Name: static Algebra, Ord](
       powers_of_tau: PolynomialEval[N, EC_ShortW_Aff[Fp[Name], G1], Ord],
       commitment: var EC_ShortW_Aff[Fp[Name], G1],
       poly: PolynomialEval[N, BigInt[bits], Ord]) {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Compute KZG commitment to a polynomial in evaluation form (Lagrange basis).
  ##
  ## This is the standard Ethereum KZG commitment used in EIP-4844 blobs.
  ## The polynomial is in evaluation form over the canonical domain.
  var commitmentJac {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
  commitmentJac.multiScalarMul_vartime(poly.evals, powers_of_tau.evals)
  commitment.affine(commitmentJac)

func kzg_commit*[N, bits: static int, Name: static Algebra](
       powers_of_tau: PolynomialCoef[N, EC_ShortW_Aff[Fp[Name], G1]],
       commitment: var EC_ShortW_Aff[Fp[Name], G1],
       poly: PolynomialCoef[N, BigInt[bits]]) {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Compute KZG commitment to a polynomial in coefficient form (monomial basis).
  ##
  ## The SRS (powers_of_tau) is in coefficient form [G, τG, τ²G, ...].
  ## This is used for FK20 tests and other scenarios with coefficient form.
  ##
  ## IMPORTANT: Ethereum KZG protocol (EIP-4844) uses evaluation form (Lagrange basis)
  ## for blobs with evaluation-form SRS.
  var commitmentJac {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
  commitmentJac.multiScalarMul_vartime(poly.coefs, powers_of_tau.coefs)
  commitment.affine(commitmentJac)

func kzg_prove*[N: static int, Name: static Algebra, Ord](
       powers_of_tau: PolynomialEval[N, EC_ShortW_Aff[Fp[Name], G1], Ord],
       domain: PolyEvalRootsDomain[N, Fr[Name], Ord],
       eval_at_challenge: var Fr[Name],
       proof: var EC_ShortW_Aff[Fp[Name], G1],
       poly: PolynomialEval[N, Fr[Name], Ord],
       opening_challenge: Fr[Name]) {.tags:[Alloca, HeapAlloc, Vartime].} =

  let quotientPoly = allocHeapAligned(PolynomialEval[N, Fr[Name], Ord], alignment = 64)

  domain.getQuotientPoly(
    quotientPoly[], eval_at_challenge,
    poly, opening_challenge
  )

  var proofJac {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
  proofJac.multiScalarMul_vartime(quotientPoly.evals, powers_of_tau.evals)
  proof.affine(proofJac)

  freeHeapAligned(quotientPoly)

# KZG - Verifier
# ------------------------------------------------------------

func kzg_verify*[F2; Name: static Algebra](
       commitment: EC_ShortW_Aff[Fp[Name], G1],
       opening_challenge: BigInt, # Fr[Name].getBigInt(),
       eval_at_challenge: BigInt, # Fr[Name].getBigInt(),
       proof: EC_ShortW_Aff[Fp[Name], G1],
       tauG2: EC_ShortW_Aff[F2, G2]): bool {.tags:[Alloca, Vartime].} =
  ## Verify a short KZG proof that ``p(opening_challenge) = eval_at_challenge``
  ## without doing the whole p(opening_challenge) computation
  #
  # Scalar inputs
  #   opening_challenge
  #   eval_at_challenge = p(opening_challenge)
  #
  # Group inputs
  #   [commitment]₁ = [p(τ)]G
  #   [proof]₁ = [proof]G
  #   [τ]₂ = [τ]H in the trusted setup
  #
  # With z = opening_challenge, we want to verify
  #   proof.(τ - z) = p(τ)-p(z)
  #
  # However τ is a secret from the trusted setup that cannot be used raw.
  # We transport the equation in the pairing group 𝔾T with bilinear pairings e
  #
  # e([proof]₁, [τ]₂ - [z]₂) = e([p(τ)]₁ - [p(z)]₁, [1]₂)
  # e([proof]₁, [τ]₂ - [z]₂) . e([p(τ)]₁ - [p(z)]₁, [-1]₂) = 1
  #
  # Finally
  #   e([proof]₁, [τ]₂ - [opening_challenge]₂) . e([commitment]₁ - [eval_at_challenge]₁, [-1]₂) = 1
  var
    tau_minus_challenge_G2 {.noInit.}: EC_ShortW_Jac[F2, G2]
    commitment_minus_eval_at_challenge_G1 {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
    negG2 {.noInit.}: EC_ShortW_Aff[F2, G2]

    tauG2Jac {.noInit.}: EC_ShortW_Jac[F2, G2]
    commitmentJac {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]

  tau_minus_challenge_G2.setGenerator()
  commitment_minus_eval_at_challenge_G1.setGenerator()
  negG2.neg(Name.getGenerator("G2"))
  tauG2Jac.fromAffine(tauG2)
  commitmentJac.fromAffine(commitment)

  tau_minus_challenge_G2.scalarMul_vartime(opening_challenge)
  tau_minus_challenge_G2.diff(tauG2Jac, tau_minus_challenge_G2)

  commitment_minus_eval_at_challenge_G1.scalarMul_vartime(eval_at_challenge)
  commitment_minus_eval_at_challenge_G1.diff(commitmentJac, commitment_minus_eval_at_challenge_G1)

  # e([proof]₁, [τ]₂ - [opening_challenge]₂) * e([commitment]₁ - [eval_at_challenge]₁, [-1]₂)
  return pairing_check(
    proof, tau_minus_challenge_G2,
    commitment_minus_eval_at_challenge_G1, negG2)

func kzg_verify_batch*[bits: static int, F2; Name: static Algebra](
       commitments: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       challenges: ptr UncheckedArray[Fr[Name]],
       evals_at_challenges: ptr UncheckedArray[BigInt[bits]],
       proofs: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       linearIndepRandNumbers: ptr UncheckedArray[Fr[Name]],
       n: int,
       tauG2: EC_ShortW_Aff[F2, G2]): bool {.tags:[HeapAlloc, Alloca, Vartime].} =
  ## Verify multiple KZG proofs efficiently
  ##
  ## Parameters
  ##
  ## `n` verification sets
  ## A verification set i (commitmentᵢ, challengeᵢ, eval_at_challengeᵢ, proofᵢ)
  ## is passed in a "struct-of-arrays" fashion.
  ##
  ## Notation:
  ##   i ∈ [0, n), a verification set with ID i
  ##   [a]₁ corresponds to the scalar multiplication [a]G by the generator G of the group 𝔾1
  ##
  ## - `commitments`: `n` commitments [commitmentᵢ]₁
  ## - `challenges`: `n` challenges zᵢ
  ## - `evals_at_challenges`: `n` evaluation yᵢ = pᵢ(zᵢ)
  ## - `proofs`: `n` [proof]₁
  ## - `linearIndepRandNumbers`: `n` linearly independant numbers that are not in control
  ##                               of a prover (potentially malicious).
  ## - `n`: the number of verification sets
  ##
  ## For all (commitmentᵢ, challengeᵢ, eval_at_challengeᵢ, proofᵢ),
  ## we verify the relation
  ##   proofᵢ.(τ - zᵢ) = pᵢ(τ)-pᵢ(zᵢ)
  ##
  ## As τ is the secret from the trusted setup, boxed in [τ]₁ and [τ]₂,
  ## we rewrite the equality check using pairings
  ##
  ##   e([proofᵢ]₁, [τ]₂ - [challengeᵢ]₂) . e([commitmentᵢ]₁ - [eval_at_challengeᵢ]₁, [-1]₂) = 1
  ##
  ## Or batched using Feist-Khovratovich method
  ##
  ##  e(∑ [rᵢ][proofᵢ]₁, [τ]₂) . e(∑[rᵢ]([commitmentᵢ]₁ - [eval_at_challengeᵢ]₁) + ∑[rᵢ][zᵢ][proofᵢ]₁, [-1]₂) = 1
  #
  # Described in:
  # - https://github.com/ethereum/consensus-specs/blob/v1.4.0-beta.1/specs/deneb/polynomial-commitments.md#verify_kzg_proof_batch
  # - https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html]\
  # - Fast amortized KZG proofs
  #   Feist, Khovratovich
  #   https://eprint.iacr.org/2023/033
  # - https://alinush.github.io/2021/06/17/Feist-Khovratovich-technique-for-computing-KZG-proofs-fast.html

  static: doAssert BigInt[bits] is Fr[Name].getBigInt()

  var sums_jac {.noInit.}: array[2, EC_ShortW_Jac[Fp[Name], G1]]
  template sum_rand_proofs: untyped = sums_jac[0]
  template sum_commit_minus_evals_G1: untyped = sums_jac[1]
  var sum_rand_challenge_proofs {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]

  # ∑ [rᵢ][proofᵢ]₁
  # ---------------
  let coefs = allocHeapArrayAligned(Fr[Name].getBigInt(), n, alignment = 64)
  coefs.batchFromField(linearIndepRandNumbers, n)
  sum_rand_proofs.multiScalarMul_vartime(coefs, proofs, n)

  # ∑[rᵢ]([commitmentᵢ]₁ - [eval_at_challengeᵢ]₁)
  # ---------------------------------------------
  #
  # We interleave allocation and deallocation, which hurts cache reuse
  # i.e. when alloc is being done, it's better to do all allocs as the metadata will already be in cache
  #
  # but it's more important to minimize memory usage especially if we want to commit with 2^26+ points
  #
  # We dealloc in reverse alloc order, to avoid leaving holes in the allocator pages.
  let commits_min_evals = allocHeapArrayAligned(EC_ShortW_Aff[Fp[Name], G1], n, alignment = 64)
  let commits_min_evals_jac = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], n, alignment = 64)

  for i in 0 ..< n:
    commits_min_evals_jac[i].fromAffine(commitments[i])
    var boxed_eval {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
    boxed_eval.setGenerator()
    boxed_eval.scalarMul_vartime(evals_at_challenges[i])
    commits_min_evals_jac[i].diff_vartime(commits_min_evals_jac[i], boxed_eval)

  commits_min_evals.batchAffine(commits_min_evals_jac, n)
  freeHeapAligned(commits_min_evals_jac)
  sum_commit_minus_evals_G1.multiScalarMul_vartime(coefs, commits_min_evals, n)
  freeHeapAligned(commits_min_evals)

  # ∑[rᵢ][zᵢ][proofᵢ]₁
  # ------------------
  var tmp {.noInit.}: Fr[Name]
  for i in 0 ..< n:
    tmp.prod(linearIndepRandNumbers[i], challenges[i])
    coefs[i].fromField(tmp)

  sum_rand_challenge_proofs.multiScalarMul_vartime(coefs, proofs, n)
  freeHeapAligned(coefs)

  # e(∑ [rᵢ][proofᵢ]₁, [τ]₂) . e(∑[rᵢ]([commitmentᵢ]₁ - [eval_at_challengeᵢ]₁) + ∑[rᵢ][zᵢ][proofᵢ]₁, [-1]₂) = 1
  # -----------------------------------------------------------------------------------------------------------
  template sum_of_sums: untyped = sums_jac[1]

  sum_of_sums.sum_vartime(sum_commit_minus_evals_G1, sum_rand_challenge_proofs)

  var sums {.noInit.}: array[2, EC_ShortW_Aff[Fp[Name], G1]]
  sums.batchAffine(sums_jac)

  var negG2 {.noInit.}: EC_ShortW_Aff[F2, G2]
  negG2.neg(Name.getGenerator("G2"))

  var gt {.noInit.}: Name.getGT()
  gt.pairing(sums, [tauG2, negG2])

  return gt.isOne().bool()
