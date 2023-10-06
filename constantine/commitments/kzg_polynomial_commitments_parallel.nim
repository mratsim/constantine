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
  ../math/elliptic/[ec_multi_scalar_mul_parallel, ec_shortweierstrass_batch_ops],
  ../math/pairings/pairings_generic,
  ../math/constants/zoo_generators,
  ../math/polynomials/polynomials,
  ../platforms/[abstractions, views],
  ../threadpool/threadpool

import ./kzg_polynomial_commitments {.all.}
export kzg_polynomial_commitments

## ############################################################
##
##                 KZG Polynomial Commitments
##                      Parallel Edition
##
## ############################################################

# KZG - Prover - Lagrange basis
# ------------------------------------------------------------

proc kzg_commit_parallel*[N: static int, C: static Curve](
       tp: Threadpool,
       commitment: var ECP_ShortW_Aff[Fp[C], G1],
       poly_evals: array[N, BigInt],
       powers_of_tau: PolynomialEval[N, G1aff[C]]) =
  ## KZG Commit to a polynomial in Lagrange / Evaluation form
  ## Parallelism: This only returns when computation is fully done
  var commitmentJac {.noInit.}: ECP_ShortW_Jac[Fp[C], G1]
  tp.multiScalarMul_vartime_parallel(commitmentJac, poly_evals, powers_of_tau.evals)
  commitment.affine(commitmentJac)

proc kzg_prove_parallel*[N: static int, C: static Curve](
       tp: Threadpool,
       proof: var ECP_ShortW_Aff[Fp[C], G1],
       eval_at_challenge: var Fr[C],
       poly: ptr PolynomialEval[N, Fr[C]],
       domain: ptr PolyDomainEval[N, Fr[C]],
       challenge: ptr Fr[C],
       powers_of_tau: PolynomialEval[N, G1aff[C]],
       isBitReversedDomain: static bool) =
  ## KZG prove commitment to a polynomial in Lagrange / Evaluation form
  ##
  ## Outputs:
  ##   - proof
  ##   - eval_at_challenge
  ##
  ## Parallelism: This only returns when computation is fully done
  # Note:
  #   The order of inputs in
  #  `kzg_prove`, `evalPolyAt`, `differenceQuotientEvalOffDomain`, `differenceQuotientEvalInDomain`
  #  minimizes register changes when parameter passing.
  #
  # z = challenge in the following code

  let diffQuotientPolyFr = allocHeapAligned(PolynomialEval[N, Fr[C]], alignment = 64)
  let invRootsMinusZ = allocHeapAligned(array[N, Fr[C]], alignment = 64)

  # Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
  # zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
  let zIndex = invRootsMinusZ[].inverseRootsMinusZ_vartime(
                                  domain[], challenge[],
                                  earlyReturnOnZero = false)

  if zIndex == -1:
    # p(z)
    tp.evalPolyAt_parallel(
      eval_at_challenge,
      poly, challenge,
      invRootsMinusZ,
      domain)

    # q(x) = (p(x) - p(z)) / (x - z)
    tp.differenceQuotientEvalOffDomain_parallel(
      diffQuotientPolyFr,
      poly, eval_at_challenge.addr, invRootsMinusZ)
  else:
    # p(z)
    # But the challenge z is equal to one of the roots of unity (how likely is that?)
    eval_at_challenge = poly.evals[zIndex]

    # q(x) = (p(x) - p(z)) / (x - z)
    tp.differenceQuotientEvalInDomain_parallel(
      diffQuotientPolyFr,
      poly, uint32 zIndex, invRootsMinusZ, domain, isBitReversedDomain)

  freeHeapAligned(invRootsMinusZ)

  const orderBits = C.getCurveOrderBitwidth()
  let diffQuotientPolyBigInt = allocHeapAligned(array[N, BigInt[orderBits]], alignment = 64)

  syncScope:
    tp.parallelFor i in 0 ..< N:
      captures: {diffQuotientPolyBigInt, diffQuotientPolyFr}
      diffQuotientPolyBigInt[i].fromField(diffQuotientPolyFr.evals[i])

  freeHeapAligned(diffQuotientPolyFr)

  var proofJac {.noInit.}: ECP_ShortW_Jac[Fp[C], G1]
  tp.multiScalarMul_vartime_parallel(proofJac, diffQuotientPolyBigInt[], powers_of_tau.evals)
  proof.affine(proofJac)

  freeHeapAligned(diffQuotientPolyBigInt)

proc kzg_verify_batch_parallel*[bits: static int, F2; C: static Curve](
       tp: Threadpool,
       commitments: ptr UncheckedArray[ECP_ShortW_Aff[Fp[C], G1]],
       challenges: ptr UncheckedArray[Fr[C]],
       evals_at_challenges: ptr UncheckedArray[BigInt[bits]],
       proofs: ptr UncheckedArray[ECP_ShortW_Aff[Fp[C], G1]],
       linearIndepRandNumbers: ptr UncheckedArray[Fr[C]],
       n: int,
       tauG2: ECP_ShortW_Aff[F2, G2]): bool {.tags:[HeapAlloc, Alloca, Vartime].} =
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
  ##
  ## Parallelism: This only returns when computation is fully done

  static: doAssert BigInt[bits] is matchingOrderBigInt(C)

  var sums_jac {.noInit.}: array[2, ECP_ShortW_Jac[Fp[C], G1]]
  template sum_rand_proofs: untyped = sums_jac[0]
  template sum_commit_minus_evals_G1: untyped = sums_jac[1]
  var sum_rand_challenge_proofs {.noInit.}: ECP_ShortW_Jac[Fp[C], G1]

  # ∑ [rᵢ][proofᵢ]₁
  # ---------------
  let coefs = allocHeapArrayAligned(matchingOrderBigInt(C), n, alignment = 64)

  syncScope:
    tp.parallelFor i in 0 ..< n:
      captures: {coefs, linearIndepRandNumbers}
      coefs[i].fromField(linearIndepRandNumbers[i])

  let sum_rand_proofs_fv = tp.spawnAwaitable tp.multiScalarMul_vartime_parallel(sum_rand_proofs.addr, coefs, proofs, n)

  # ∑[rᵢ]([commitmentᵢ]₁ - [eval_at_challengeᵢ]₁)
  # ---------------------------------------------
  #
  # We interleave allocation and deallocation, which hurts cache reuse
  # i.e. when alloc is being done, it's better to do all allocs as the metadata will already be in cache
  #
  # but it's more important to minimize memory usage especially if we want to commit with 2^26+ points
  #
  # We dealloc in reverse alloc order, to avoid leaving holes in the allocator pages.
  proc compute_sum_commitments_minus_evals(tp: Threadpool,
                                           sum_commit_minus_evals_G1: ptr ECP_ShortW_Jac[Fp[C], G1],
                                           commitments: ptr UncheckedArray[ECP_ShortW_Aff[Fp[C], G1]],
                                           evals_at_challenges: ptr UncheckedArray[BigInt[bits]],
                                           coefs: ptr UncheckedArray[BigInt[bits]],
                                           n: int) {.nimcall.} =
    let commits_min_evals = allocHeapArrayAligned(ECP_ShortW_Aff[Fp[C], G1], n, alignment = 64)
    let commits_min_evals_jac = allocHeapArrayAligned(ECP_ShortW_Jac[Fp[C], G1], n, alignment = 64)

    syncScope:
      tp.parallelFor i in 0 ..< n:
        captures: {commits_min_evals_jac, commitments, evals_at_challenges}

        commits_min_evals_jac[i].fromAffine(commitments[i])
        var boxed_eval {.noInit.}: ECP_ShortW_Jac[Fp[C], G1]
        boxed_eval.fromAffine(C.getGenerator("G1"))
        boxed_eval.scalarMul_vartime(evals_at_challenges[i])
        commits_min_evals_jac[i].diff_vartime(commits_min_evals_jac[i], boxed_eval)

    commits_min_evals.batchAffine(commits_min_evals_jac, n)
    freeHeapAligned(commits_min_evals_jac)
    tp.multiScalarMul_vartime(sum_commit_minus_evals_G1, coefs, commits_min_evals, n)
    freeHeapAligned(commits_min_evals)

  let sum_commit_minus_evals_G1_fv = tp.spawnAwaitable tp.compute_sum_commitments_minus_evals(
                                                            sum_commit_minus_evals_G1.addr,
                                                            commitments,
                                                            evals_at_challenges,
                                                            coefs,
                                                            n)

  # ∑[rᵢ][zᵢ][proofᵢ]₁
  # ------------------
  proc compute_sum_rand_challenge_proofs(tp: Threadpool,
                                         sum_rand_challenge_proofs: ptr ECP_ShortW_Jac[Fp[C], G1],
                                         linearIndepRandNumbers: ptr UncheckedArray[Fr[C]],
                                         challenges: ptr UncheckedArray[Fr[C]],
                                         proofs: ptr UncheckedArray[ECP_ShortW_Aff[Fp[C], G1]],
                                         n: int) {.nimcall.} =

    let rand_coefs = allocHeapArrayAligned(matchingOrderBigInt(C), n, alignment = 64)
    let rand_coefs_fr = allocHeapArrayAligned(Fr[C], n, alignment = 64)

    syncScope:
      tp.parallelFor i in 0 ..< n:
        rand_coefs_fr[i].prod(linearIndepRandNumbers[i], challenges[i])
        rand_coefs[i].fromField(rand_coefs_fr[i])

    tp.multiScalarMul_vartime(sum_rand_challenge_proofs, rand_coefs, proofs, n)

    freeHeapAligned(rand_coefs_fr)
    freeHeapAligned(rand_coefs)

  let sum_rand_challenge_proofs_fv = tp.spawnAwaitable tp.compute_sum_rand_challenge_proofs(
                                                   sum_rand_challenge_proofs,
                                                   linearIndepRandNumbers,
                                                   challenges,
                                                   proofs,
                                                   n)

  # e(∑ [rᵢ][proofᵢ]₁, [τ]₂) . e(∑[rᵢ]([commitmentᵢ]₁ - [eval_at_challengeᵢ]₁) + ∑[rᵢ][zᵢ][proofᵢ]₁, [-1]₂) = 1
  # -----------------------------------------------------------------------------------------------------------
  template sum_of_sums: untyped = sums_jac[1]

  discard sync sum_commit_minus_evals_G1_fv
  discard sync sum_rand_challenge_proofs_fv

  sum_of_sums.sum_vartime(sum_commit_minus_evals_G1, sum_rand_challenge_proofs)

  discard sync sum_rand_proofs_fv
  freeHeapAligned(coefs)

  var sums {.noInit.}: array[2, ECP_ShortW_Aff[Fp[C], G1]]
  sums.batchAffine(sums_jac)

  var negG2 {.noInit.}: ECP_ShortW_Aff[F2, G2]
  negG2.neg(C.getGenerator("G2"))

  var gt {.noInit.}: C.getGT()
  gt.pairing(sums, [tauG2, negG2])

  return gt.isOne().bool()