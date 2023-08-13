# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../math/config/curves,
  ../math/[ec_shortweierstrass, arithmetic, extension_fields],
  ../math/elliptic/[ec_scalar_mul, ec_multi_scalar_mul],
  ../math/pairings/pairings_generic,
  ../math/constants/zoo_generators,
  ../math/polynomials/polynomials,
  ../platforms/[abstractions, views]

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
##   srs_g1: [[1]₁, [τ]₁, [τ²]₁, ... [τⁿ]₁] also called powers of tau, with a bounded degree n
##   srs_g2: [[1]₂, [τ]₂]
##
## τ and its powers are secrets that no one know, we only work with [τⁱ]₁ and [τ]₂
## not with τ directly. (τ cannot be deduced due to the elliptic curve discrete logarithm problem)
##
## Info
##   τ and its powers are created through a secure multi-party computation (MPC) ceremony
##   called powers of tau. Each participant contribute randomness.
##   Only one honest participant (who ensures that the randomness created cannot be recreated)
##   is necessary for the ceremony success.
##
## Protocol
##
## 0. A data blob is interpreted as up to n 𝔽r elements
##    corresponding to a polynomial p(x) = blob₀ + blob₁ x + blob₂ x² + ... + blobₙ₋₁ xⁿ⁻¹
##                                  p(x) = ∑ blobᵢ xⁱ
##
##    So we can commit/prove up to 4096*log₂(r) bits of data
##    For Ethereum, n = 4096 and log₂(r) = 255 bits
##    so 130.560kB of transaction data committed per 48B proof stored in the blockchain
##
## 1. commit(srs_g1, blob) -> commitment C = ∑ blobᵢ.srs_g1ᵢ = ∑ [blobᵢ.τⁱ]₁ = [p(τ)]₁
##
## 2. The verifier chooses a random challenge `z` in 𝔽r that the prover does not control.
##    To make the protocol non-interactive, z may be computed via the Fiat-Shamir heuristic.
##
## 3. compute_proof(blob, [commitment]₁, challenge) -> (eval_at_challenge, [proof]₁)
##      blob: p(x)
##      [commitment]₁: [p(τ)]₁
##      challenge: z
##      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
##      -> The prover needs to provide a proof that it knows a polynomial p(x)
##         such that p(z) = y. With the proof, the verifier doesn't need access to the polynomial to verify the claim.
##      -> Compute a witness polynomial w(x, z) = (p(x) - p(z)) / (x-z)
##         We can evaluate it at τ from the public SRS and challenge point `z` chosen by the verifier (indifferentiable from random).
##         We don't know τ, but we know [τ]₁ so we transport the problem from 𝔽r to 𝔾1
##      => The proof is the evaluation of the witness polynomial for a challenge `z` of the verifier choosing.
##         w(τ, z) = proof
##         We output [proof]₁ = [proof]G₁
##
## 4. verify_commitment([commitment]₁, challenge, eval_at_challenge, [proof]₁) -> bool
##      [commitment]₁: [p(τ)]₁
##      challenge: z
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

type
  PowersOfTauCoef[D: static int, F; G: static Subgroup] = object
    coefs: array[D, ECP_ShortW_Aff[F, G]]

  PowersOfTauEval[D: static int, F; G: static Subgroup] = object
    evals: array[D, ECP_ShortW_Aff[F, G]]

  G1aff[C: static Curve] = ECP_ShortW_Aff[Fp[C], G1]
  G1jac[C: static Curve] = ECP_ShortW_Jac[Fp[C], G1]

# Helper functions
# ------------------------------------------------------------

func g1_lincomb[C: static Curve](r: var G1jac[C],
                points: ptr UncheckedArray[G1aff[C]],
                scalars: ptr UncheckedArray[matchingOrderBigInt(C)],
                len: int) =
  ## Multi-scalar-multiplication / linear combination
  r.raw.multiScalarMul_vartime(
    scalars,
    cast[ptr UncheckedArray[typeof points[0].raw]](points),
    len)

func g1_lincomb[C: static Curve](r: var G1jac[C],
                points: ptr UncheckedArray[G1aff[C]],
                scalars: ptr UncheckedArray[Fr[C]],
                len: int) =
  ## Multi-scalar-multiplication / linear combination
  let scalars2 = allocHeapArray(matchingOrderBigInt(C), len)

  for i in 0 ..< len:
    scalars2[i].fromField(scalars[i])

  r.g1_lincomb(points, scalars2, len)

  scalars2.freeHeap()

# KZG - Prover - Lagrange basis
# ------------------------------------------------------------
#
# For now we assume that the input polynomial always has the same degree
# as the powers of τ

func kzg_commit*[N: static int, C: static Curve](
       commitment: var ECP_ShortW_Jac[Fp[C], G1],
       poly_evals: array[N, matchingOrderBigInt(C)],
       powers_of_tau: PowersOfTauEval[N, Fp[C], G1]) =
  commitment.g1_lincomb(powers_of_tau.evals.asUnchecked(), poly_evals.asUnchecked(), N)

func kzg_prove*[N: static int, C: static Curve](
       proof: var ECP_ShortW_Jac[Fp[C], G1],
       eval_at_challenge: var Fr[C],
       poly: PolynomialEval[N, Fr[C]],
       domain: PolyDomainEval[N, Fr[C]],
       challenge: Fr[C],
       powers_of_tau: PowersOfTauEval[N, Fp[C], G1]) =

  # Note:
  #   The order of inputs in
  #  `kzg_prove`, `evalPolyAt_vartime`, `differenceQuotientEvalOffDomain`, `differenceQuotientEvalInDomain`
  #  minimizes register changes when parameter passing.

  # z = challenge

  let invRootsMinusZ = allocHeap(array[N, Fr[C]])
  let diffQuotientPoly = allocHeap(PolynomialEval[N, Fr[C]])

  let zIndex = invRootsMinusZ.inverseRootsMinusZ_vartime(domain, challenge)

  if zIndex == -1:
    # p(z)
    eval_at_challenge.evalPolyAt_vartime(
      invRootsMinusZ,
      poly, domain,
      challenge)

    # q(x) = (p(x) - p(z)) / (x - z)
    diffQuotientPoly.differenceQuotientEvalOffDomain(
      invRootsMinusZ, poly, eval_at_challenge)
  else:
    # p(z)
    # But the challenge z is equal to one of the roots of unity (how likely is that?)
    eval_at_challenge = poly[zIndex]

    # q(x) = (p(x) - p(z)) / (x - z)
    diffQuotientPoly.differenceQuotientEvalInDomain(
      invRootsMinusZ, poly, domain, zIndex)

  proof.g1_lincomb(powers_of_tau.evals.asUnchecked(), diffQuotientPoly.asUnchecked(), N)

  freeHeap(diffQuotientPoly)
  freeHeap(invRootsMinusZ)

# KZG - Verifier
# ------------------------------------------------------------

func kzg_verify*[F2; C: static Curve](
       commitment: ECP_ShortW_Aff[Fp[C], G1],
       challenge: BigInt, # matchingOrderBigInt(C),
       eval_at_challenge: BigInt, # matchingOrderBigInt(C),
       proof: ECP_ShortW_Aff[Fp[C], G1],
       tauG2: ECP_ShortW_Aff[F2, G2]): bool =
  ## Verify a short KZG proof that ``p(challenge) = eval_at_challenge``
  ## without doing the whole p(challenge) computation
  #
  # Scalar inputs
  #   challenge
  #   eval_at_challenge = p(challenge)
  #
  # Group inputs
  #   [commitment]₁ = [p(τ)]G
  #   [proof]₁ = [proof]G
  #   [τ]₂ = [τ]H in the trusted setup
  #
  # With z = challenge, we want to verify
  #   proof.(τ - z) = p(τ)-p(z)
  #
  # However τ is a secret from the trusted setup that cannot be used raw.
  # We transport the equation in the pairing group 𝔾T with bilinear pairings e
  #
  # e([proof]₁, [τ]₂ - [z]₂) = e([p(τ)]₁ - [p(z)]₁, [1]₂)
  # e([proof]₁, [τ]₂ - [z]₂) . e([p(τ)]₁ - [p(z)]₁, [-1]₂) = 1
  #
  # Finally
  #   e([proof]₁, [τ]₂ - [challenge]₂) . e([commitment]₁ - [eval_at_challenge]₁, [-1]₂) = 1
  var
    tau_minus_challenge_G2 {.noInit.}: ECP_ShortW_Jac[F2, G2]
    commitment_minus_eval_at_challenge_G1 {.noInit.}: ECP_ShortW_Jac[Fp[C], G1]
    negG2 {.noInit.}: ECP_ShortW_Aff[F2, G2]

    tauG2Jac {.noInit.}: ECP_ShortW_Jac[F2, G2]
    commitmentJac {.noInit.}: ECP_ShortW_Jac[Fp[C], G1]

  tau_minus_challenge_G2.fromAffine(C.getGenerator("G2"))
  commitment_minus_eval_at_challenge_G1.fromAffine(C.getGenerator("G1"))
  negG2.neg(C.getGenerator("G2"))
  tauG2Jac.fromAffine(tauG2)
  commitmentJac.fromAffine(commitment)

  tau_minus_challenge_G2.scalarMul(challenge)
  tau_minus_challenge_G2.diff(tauG2Jac, tau_minus_challenge_G2)

  commitment_minus_eval_at_challenge_G1.scalarMul(eval_at_challenge)
  commitment_minus_eval_at_challenge_G1.diff(commitmentJac, commitment_minus_eval_at_challenge_G1)

  var tmzG2 {.noInit.}: ECP_ShortW_Aff[F2, G2]
  var cmyG1 {.noInit.}: ECP_ShortW_Aff[Fp[C], G1]
  tmzG2.affine(tau_minus_challenge_G2)
  cmyG1.affine(commitment_minus_eval_at_challenge_G1)

  # e([proof]₁, [τ]₂ - [challenge]₂) * e([commitment]₁ - [eval_at_challenge]₁, [-1]₂)
  var gt {.noInit.}: C.getGT()
  gt.pairing([proof, cmyG1], [tmzG2, negG2])

  return gt.isOne().bool()