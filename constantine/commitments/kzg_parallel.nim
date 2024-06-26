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
  ../math/elliptic/[ec_multi_scalar_mul_parallel, ec_shortweierstrass_batch_ops],
  ../math/pairings/pairings_generic,
  ../named/zoo_generators,
  ../math/polynomials/polynomials,
  ../platforms/[abstractions, views],
  ../threadpool/threadpool,
  ./protocol_quotient_check_parallel

import ./kzg {.all.}
export kzg

## ############################################################
##
##                 KZG Polynomial Commitments
##                      Parallel Edition
##
## ############################################################

# KZG - Prover - Lagrange basis
# ------------------------------------------------------------

proc kzg_commit_parallel*[N, bits: static int, Name: static Algebra](
       tp: Threadpool,
       powers_of_tau: PolynomialEval[N, EC_ShortW_Aff[Fp[Name], G1]],
       commitment: var EC_ShortW_Aff[Fp[Name], G1],
       poly: PolynomialEval[N, BigInt[bits]],
) =
  ## KZG Commit to a polynomial in Lagrange / Evaluation form
  ## Parallelism: This only returns when computation is fully done
  var commitmentJac {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
  tp.multiScalarMul_vartime_parallel(commitmentJac, poly.evals, powers_of_tau.evals)
  commitment.affine(commitmentJac)

proc kzg_prove_parallel*[N: static int, Name: static Algebra](
       tp: Threadpool,
       powers_of_tau: PolynomialEval[N, EC_ShortW_Aff[Fp[Name], G1]],
       domain: PolyEvalRootsDomain[N, Fr[Name]],
       eval_at_challenge: var Fr[Name],
       proof: var EC_ShortW_Aff[Fp[Name], G1],
       poly: PolynomialEval[N, Fr[Name]],
       opening_challenge: Fr[Name]) =
  ## KZG prove commitment to a polynomial in Lagrange / Evaluation form
  ##
  ## Outputs:
  ##   - proof
  ##   - eval_at_challenge
  ##
  ## Parallelism: This only returns when computation is fully done
  # Note:
  #   The order of inputs in
  #  `kzg_prove`, `evalPolyOffDomainAt`, `getQuotientPolyOffDomain`, `getQuotientPolyInDomain`
  #  minimizes register changes when parameter passing.
  #
  # z = opening_challenge in the following code

  let quotientPoly = allocHeapAligned(PolynomialEval[N, Fr[Name]], alignment = 64)
  tp.getQuotientPoly_parallel(
    domain,
    quotientPoly[], eval_at_challenge,
    poly, opening_challenge
  )

  var proofJac {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
  tp.multiScalarMul_vartime_parallel(proofJac, quotientPoly.evals, powers_of_tau.evals)
  proof.affine(proofJac)

  freeHeapAligned(quotientPoly)

proc kzg_verify_batch_parallel*[bits: static int, F2; Name: static Algebra](
       tp: Threadpool,
       commitments: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       opening_challenges: ptr UncheckedArray[Fr[Name]],
       evals_at_challenges: ptr UncheckedArray[BigInt[bits]],
       proofs: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       linearIndepRandNumbers: ptr UncheckedArray[Fr[Name]],
       n: int,
       tauG2: EC_ShortW_Aff[F2, G2]): bool =
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
  ## - `opening_challenges`: `n` opening_challenges zᵢ
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

  static: doAssert BigInt[bits] is Fr[Name].getBigInt()

  var sums_jac {.noInit.}: array[2, EC_ShortW_Jac[Fp[Name], G1]]
  template sum_rand_proofs: untyped = sums_jac[0]
  template sum_commit_minus_evals_G1: untyped = sums_jac[1]
  var sum_rand_challenge_proofs {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]

  # ∑ [rᵢ][proofᵢ]₁
  # ---------------
  let coefs = allocHeapArrayAligned(Fr[Name].getBigInt(), n, alignment = 64)

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
                                           sum_commit_minus_evals_G1: ptr EC_ShortW_Jac[Fp[Name], G1],
                                           commitments: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
                                           evals_at_challenges: ptr UncheckedArray[BigInt[bits]],
                                           coefs: ptr UncheckedArray[BigInt[bits]],
                                           n: int) {.nimcall.} =
    let commits_min_evals = allocHeapArrayAligned(EC_ShortW_Aff[Fp[Name], G1], n, alignment = 64)
    let commits_min_evals_jac = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], n, alignment = 64)

    syncScope:
      tp.parallelFor i in 0 ..< n:
        captures: {commits_min_evals_jac, commitments, evals_at_challenges}

        commits_min_evals_jac[i].fromAffine(commitments[i])
        var boxed_eval {.noInit.}: EC_ShortW_Jac[Fp[Name], G1]
        boxed_eval.setGenerator()
        boxed_eval.scalarMul_vartime(evals_at_challenges[i])
        commits_min_evals_jac[i].diff_vartime(commits_min_evals_jac[i], boxed_eval)

    commits_min_evals.batchAffine(commits_min_evals_jac, n)
    freeHeapAligned(commits_min_evals_jac)
    tp.multiScalarMul_vartime_parallel(sum_commit_minus_evals_G1, coefs, commits_min_evals, n)
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
                                         sum_rand_challenge_proofs: ptr EC_ShortW_Jac[Fp[Name], G1],
                                         linearIndepRandNumbers: ptr UncheckedArray[Fr[Name]],
                                         opening_challenges: ptr UncheckedArray[Fr[Name]],
                                         proofs: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
                                         n: int) {.nimcall.} =

    let rand_coefs = allocHeapArrayAligned(Fr[Name].getBigInt(), n, alignment = 64)
    let rand_coefs_fr = allocHeapArrayAligned(Fr[Name], n, alignment = 64)

    syncScope:
      tp.parallelFor i in 0 ..< n:
        captures: {rand_coefs, rand_coefs_fr, linearIndepRandNumbers, opening_challenges}
        rand_coefs_fr[i].prod(linearIndepRandNumbers[i], opening_challenges[i])
        rand_coefs[i].fromField(rand_coefs_fr[i])

    tp.multiScalarMul_vartime_parallel(sum_rand_challenge_proofs, rand_coefs, proofs, n)

    freeHeapAligned(rand_coefs_fr)
    freeHeapAligned(rand_coefs)

  let sum_rand_challenge_proofs_fv = tp.spawnAwaitable tp.compute_sum_rand_challenge_proofs(
                                                   sum_rand_challenge_proofs.addr,
                                                   linearIndepRandNumbers,
                                                   opening_challenges,
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

  var sums {.noInit.}: array[2, EC_ShortW_Aff[Fp[Name], G1]]
  sums.batchAffine(sums_jac)

  var negG2 {.noInit.}: EC_ShortW_Aff[F2, G2]
  negG2.neg(Name.getGenerator("G2"))

  var gt {.noInit.}: Name.getGT()
  gt.pairing(sums, [tauG2, negG2])

  return gt.isOne().bool()
