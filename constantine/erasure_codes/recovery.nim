# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/options,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/polynomials/[polynomials, fft],
  constantine/platforms/[allocs, bithacks, views],
  ./zero_polynomial

## ############################################################
##
##          Polynomial Reconstruction (Erasure Code Recovery)
##
## ############################################################
##
## Overview
## ========
## This module implements polynomial reconstruction from partial
## samples using Reed-Solomon erasure coding.
##
## Given at least 50% of samples, we can recover the original
## polynomial. This is based on the Reed-Solomon coding property
## that a degree-(n-1) polynomial is uniquely determined by n points.
##
## Mathematical Background
## =======================
## Let P(x) be the original polynomial of degree < n that we want
## to recover. We have evaluations at N = n·r points (redundancy r),
## but some evaluations are missing (erasures).
##
## The recovery algorithm works as follows:
##
## 1. Extended Evaluation
##    Build E(x) where E[i] = sample[i] if available, 0 if missing
##
## 2. Vanishing Polynomial
##    Compute Z(x) = ∏_{i∈missing} (x - ω^i)
##    Z(x) vanishes exactly at the missing positions
##
## 3. Product Polynomial
##    Compute (E·Z)(x) = E(x) · Z(x) in evaluation form
##    At non-missing positions: (E·Z)(i) = P(i) · Z(i)
##    At missing positions: (E·Z)(i) = 0
##
## 4. Interpolation
##    IFFT to get (E·Z)(x) coefficients
##
## 5. Coset Shift
##    Transform to coset domain to avoid division by zero:
##    - Compute (E·Z)(k·x) coefficients (scale by k^(-i))
##    - Compute Z(k·x) coefficients
##
## 6. Coset Evaluation
##    FFT both polynomials to coset evaluation form
##
## 7. Division
##    Compute P(k·x) = (E·Z)(k·x) / Z(k·x) pointwise
##    Safe because Z(k·x) ≠ 0 on the coset
##
## 8. Recovery
##    - Coset IFFT to get P(k·x) coefficients
##    - Unscale to get P(x) coefficients
##    - FFT to get final evaluations
##
## Why Cosets?
## ===========
## Direct division (E·Z)(x) / Z(x) fails because Z(x) has roots
## at the missing positions. By evaluating on a coset g·D where
## g ∉ D, we ensure Z(g·x) ≠ 0 for all x ∈ D, making division safe.
##
## The coset shift uses SCALE_FACTOR = 5 (from c-kzg), which is a
## primitive element that generates a valid coset.
##
## Capacity Limits
## ===============
## For random erasures: Can tolerate up to N - n = n(r - 1) erasures
## For PeerDAS (r = 2): Must have at least 50% of cells available
##
## Memory Management
## =================
## Uses aligned heap allocation for temporary buffers to ensure
## proper cache alignment. All allocations are freed before return.
##
## References
## ==========
## - rust-eth-kzg/papers/erasure_codes.md - Mathematical background
## - c-kzg/src/recover.c - recover_poly_from_samples
## - c-kzg-4844/src/eip7594/recovery.c - recover_cells
## - rust-kzg/blst/src/recovery.rs - PolyRecover implementation
## - go-kzg/legacy_recovery.go - ErasureCodeRecover
## - consensus-specs/specs/fulu/polynomial-commitments-sampling.md
## - Ethereum Research: "Reed-Solomon erasure recovery via FFTs"
## - Vitalik Buterin: "Reed-Solomon erasure code recovery in N log² N time"

{.push raises:[].}

# NOTE: This module contains a GENERIC recovery implementation.
# For PeerDAS-specific recovery, see constantine/data_availability_sampling/eth_peerdas.nim
# These two implementations are similar but not identical - planned for consolidation.

type
  RecoveryStatus* = enum
    Recovery_Success = 0,
    Recovery_TooFewSamples,
    Recovery_TooManyMissing,
    Recovery_InvalidDomainSize,
    Recovery_DivisionByZero,
    Recovery_FFT_Failure

func scalePolyWithShift*[F](p: var openArray[F], shift: F) =
  ## Scale polynomial: p[i] *= shift^(-i)
  ##
  ## Transforms P(x) to P(shift·x) in coefficient form.
  ## Used for coset FFT to avoid division by zero.
  ##
  ## Parameters
  ## ==========
  ## - p: INOUT polynomial coefficients (modified in place)
  ## - shift: Coset shift factor (SCALE_FACTOR = 5)

  var factorPower {.noInit.}: F
  factorPower.setOne()
  var invShift {.noInit.}: F
  invShift.inv_vartime(shift)

  for i in 1 ..< p.len:
    factorPower.prod(factorPower, invShift)
    p[i].prod(p[i], factorPower)

func unscalePolyWithShift*[F](p: var openArray[F], shift: F) =
  ## Unscale polynomial: p[i] *= shift^i
  ##
  ## Transforms P(shift·x) back to P(x) in coefficient form.
  ## Inverse operation of scalePolyWithShift.
  ##
  ## Parameters
  ## ==========
  ## - p: INOUT polynomial coefficients (modified in place)
  ## - shift: Coset shift factor (SCALE_FACTOR = 5)

  var factorPower {.noInit.}: F
  factorPower.setOne()

  for i in 1 ..< p.len:
    factorPower.prod(factorPower, shift)
    p[i].prod(p[i], factorPower)

func recoverPolyFromSamples*[
        N: static int, F; Ord: static PolyOrdering,
        Domain: PolyEvalRootsDomain[N, F, Ord]](
          domain: Domain,
          dst: var PolynomialCoef[N, F],
          samples: openArray[Option[F]]): RecoveryStatus =
  ## Recover polynomial from samples.
  ##
  ## Given at least 50% of samples, reconstruct the original polynomial.
  ##
  ## Parameters
  ## ==========
  ## - dst: OUT parameter for recovered polynomial in coefficient form
  ## - samples: Array of samples, None for missing (IN)
  ## - domain: FFT domain (roots of unity) (IN)
  ##
  ## Requirements
  ## ============
  ## - N must be a power of 2
  ## - At least 50% of samples must be available
  ## - samples.len must equal N
  ##
  ## Returns
  ## =======
  ## - Recovery_Success on success
  ## - Recovery_TooFewSamples if < 50% available
  ## - Recovery_InvalidDomainSize if N is not power of 2
  ##
  ## Algorithm
  ## =========
  ## Implements the Reed-Solomon erasure recovery algorithm using
  ## vanishing polynomials and coset FFTs. See module documentation
  ## for detailed mathematical background.
  ##
  ## Memory Management
  ## =================
  ## Uses aligned heap allocation for temporary buffers. All memory
  ## is freed before return.
  ##
  ## Reference
  ## =========
  ## c-kzg-4844: recover_cells
  ## c-kzg: recover_poly_from_samples

  if N != samples.len:
    return Recovery_TooManyMissing
  if (N and (N - 1)) != 0:
    return Recovery_InvalidDomainSize

  # Pre-check: ensure domain roots are valid
  var one: F
  one.setOne()
  if not bool(domain.rootsOfUnity[0] == one):
    return Recovery_InvalidDomainSize

  # Count missing samples
  var missing_count = 0
  for i in 0 ..< N:
    if samples[i].isNone():
      inc(missing_count)

  if missing_count > N div 2:
    return Recovery_TooFewSamples

  # Edge case: no samples missing - just IFFT
  if missing_count == 0:
    var all_samples: array[N, F]
    for i in 0 ..< N:
      all_samples[i] = samples[i].get()

    let fft_desc = FrFFT_Descriptor[F].new(
      order = N,
      generatorRootOfUnity = domain.rootsOfUnity[1]
    )

    var coeffs: array[N, F]
    let ifft_status = ifft_rn(fft_desc, coeffs, all_samples)
    if ifft_status != FFT_Success:
      return Recovery_FFT_Failure

    for i in 0 ..< N:
      dst.coefs[i] = coeffs[i]


    return Recovery_Success

  # Build list of missing indices
  var missing_indices: array[256, uint64] # TODO: very suspicious
  if missing_count >= 256:
    return Recovery_TooManyMissing

  # Validate missing indices are in range
  for i in 0 ..< N:
    if samples[i].isNone():
      if uint64(i) >= uint64(N):
        return Recovery_InvalidDomainSize

  var missing_idx = 0
  for i in 0 ..< N:
    if samples[i].isNone():
      missing_indices[missing_idx] = uint64(i)
      inc(missing_idx)

  # Build extended evaluation array (0 for missing)
  var extended_evaluation: array[N, F]
  for i in 0 ..< N:
    if samples[i].isSome():
      extended_evaluation[i] = samples[i].get()
    else:
      extended_evaluation[i].setZero()

  # Compute vanishing polynomial Z(x) for missing indices
  var zero_poly: PolynomialCoef[N, F]
  domain.vanishingPolynomialForIndicesRT(zero_poly, missing_indices.toOpenArray(0, missing_count - 1))

  let fft_desc = FrFFT_Descriptor[F].new(
    order = N,
    generatorRootOfUnity = domain.rootsOfUnity[1]
  )

  # Evaluate Z(x) over the domain
  var zero_poly_eval = allocHeapArrayAligned(F, N, alignment = 64)
  let fft_status = fft_nr(
    fft_desc,
    zero_poly_eval.toOpenArray(N),
    zero_poly.coefs.toOpenArray(0, N-1)
  )
  if fft_status != FFT_Success:
    freeHeapAligned(zero_poly_eval)
    return Recovery_FFT_Failure

  # Compute (E·Z)(x) in evaluation form
  var poly_evaluations_with_zero = allocHeapArrayAligned(F, N, alignment = 64)
  for i in 0 ..< N:
    poly_evaluations_with_zero[i].prod(extended_evaluation[i], zero_poly_eval[i])

  # IFFT to get (E·Z)(x) coefficients
  var poly_with_zero = allocHeapArrayAligned(F, N, alignment = 64)
  let ifft_status = ifft_rn(
    fft_desc,
    poly_with_zero.toOpenArray(N),
    poly_evaluations_with_zero.toOpenArray(N)
  )
  freeHeapAligned(poly_evaluations_with_zero)
  if ifft_status != FFT_Success:
    freeHeapAligned(poly_with_zero)

    return Recovery_FFT_Failure

  # Coset shift: use 5 (SCALE_FACTOR from c-kzg)
  var coset_shift: F
  coset_shift.fromUint(5)

  # Scale (E·Z)(x) to (E·Z)(k·x)
  var scaled_poly_with_zero = allocHeapArrayAligned(F, N, alignment = 64)
  for i in 0 ..< N:
    scaled_poly_with_zero[i] = poly_with_zero[i]
  scalePolyWithShift(scaled_poly_with_zero.toOpenArray(N), coset_shift)

  # Scale Z(x) to Z(k·x)
  var scaled_zero_poly = allocHeapArrayAligned(F, N, alignment = 64)
  for i in 0 ..< N:
    scaled_zero_poly[i] = zero_poly.coefs[i]
  scalePolyWithShift(scaled_zero_poly.toOpenArray(N), coset_shift)
  freeHeapAligned(poly_with_zero)

  # FFT to get (E·Z)(k·x) evaluations
  var eval_scaled_poly_with_zero = allocHeapArrayAligned(F, N, alignment = 64)
  let fft_status2 = fft_nr(
    fft_desc,
    eval_scaled_poly_with_zero.toOpenArray(N),
    scaled_poly_with_zero.toOpenArray(N)
  )
  freeHeapAligned(scaled_poly_with_zero)
  if fft_status2 != FFT_Success:
    freeHeapAligned(eval_scaled_poly_with_zero)

    return Recovery_FFT_Failure

  # FFT to get Z(k·x) evaluations
  var eval_scaled_zero_poly = allocHeapArrayAligned(F, N, alignment = 64)
  let fft_status3 = fft_nr(
    fft_desc,
    eval_scaled_zero_poly.toOpenArray(N),
    scaled_zero_poly.toOpenArray(N)
  )
  freeHeapAligned(scaled_zero_poly)
  if fft_status3 != FFT_Success:
    freeHeapAligned(eval_scaled_zero_poly)

    return Recovery_FFT_Failure

  # Divide: P(k·x) = (E·Z)(k·x) / Z(k·x)
  var eval_scaled_reconstructed_poly = allocHeapArrayAligned(F, N, alignment = 64)
  for i in 0 ..< N:
    # Check for division by zero using bool conversion
    var zero: F
    zero.setZero()
    let is_zero = bool(eval_scaled_zero_poly[i] == zero)
    if is_zero:
      freeHeapAligned(eval_scaled_poly_with_zero)
      freeHeapAligned(eval_scaled_zero_poly)
      freeHeapAligned(eval_scaled_reconstructed_poly)
      return Recovery_DivisionByZero
    var inv {.noInit.}: F
    inv.inv_vartime(eval_scaled_zero_poly[i])
    eval_scaled_reconstructed_poly[i].prod(eval_scaled_poly_with_zero[i], inv)
  freeHeapAligned(eval_scaled_poly_with_zero)
  freeHeapAligned(eval_scaled_zero_poly)

  # IFFT to get P(k·x) coefficients
  var scaled_reconstructed_poly = allocHeapArrayAligned(F, N, alignment = 64)
  let ifft_status2 = ifft_rn(
    fft_desc,
    scaled_reconstructed_poly.toOpenArray(N),
    eval_scaled_reconstructed_poly.toOpenArray(N)
  )
  freeHeapAligned(eval_scaled_reconstructed_poly)
  if ifft_status2 != FFT_Success:
    freeHeapAligned(scaled_reconstructed_poly)

    return Recovery_FFT_Failure

  # Unscale to get P(x) coefficients
  unscalePolyWithShift(scaled_reconstructed_poly.toOpenArray(N), coset_shift)

  # Copy result
  for i in 0 ..< N:
    dst.coefs[i] = scaled_reconstructed_poly[i]

  freeHeapAligned(scaled_reconstructed_poly)

  return Recovery_Success

func recoverEvalsFromSamples*[
      N: static int, F; Ord: static PolyOrdering,
      Domain: PolyEvalRootsDomain[N, F, Ord]](
        domain: Domain,
        dst: var PolynomialEval[N, F, Ord],
        samples: openArray[Option[F]]): RecoveryStatus =
  ## Recover polynomial evaluations from samples.
  ##
  ## Wrapper around recoverPolyFromSamples that returns evaluations
  ## instead of coefficients.
  ##
  ## Parameters
  ## ==========
  ## - dst: OUT parameter for recovered evaluations
  ## - samples: Array of samples, None for missing (IN)
  ## - domain: FFT domain (roots of unity) (IN)
  ##
  ## Returns
  ## =======
  ## - Recovery_Success on success
  ## - RecoveryStatus error code on failure
  var poly_coeff: PolynomialCoef[N, F]
  let recover_status = domain.recoverPolyFromSamples(poly_coeff, samples)
  if recover_status != Recovery_Success:
    return recover_status

  let fft_desc = FrFFT_Descriptor[F].new(
    order = N,
    generatorRootOfUnity = domain.rootsOfUnity[1]
  )

  var coeffs_copy = allocHeapArrayAligned(F, N, alignment = 64)
  for i in 0 ..< N:
    coeffs_copy[i] = poly_coeff.coefs[i]

  let fft_status = fft_nr(fft_desc, dst.evals, coeffs_copy.toOpenArray(N))
  freeHeapAligned(coeffs_copy)


  if fft_status != FFT_Success:
    return Recovery_FFT_Failure

  return Recovery_Success