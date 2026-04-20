# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/options,
  constantine/math/arithmetic,
  constantine/math/polynomials/[polynomials, fft]

## ############################################################
##
##          Vanishing Polynomial Computation
##
## ############################################################
##
## Overview
## ========
## This module implements the computation of vanishing polynomials
## for Reed-Solomon erasure code recovery.
##
## A vanishing polynomial Z(x) for a set of indices S is defined as:
##   Z(x) = ∏_{i∈S} (x - ω^i)
##
## where ω is a primitive root of unity of sufficient order.
## The polynomial evaluates to zero at all domain points corresponding
## to the missing indices in S.
##
## Mathematical Background
## =======================
## In Reed-Solomon erasure recovery, we use the vanishing polynomial
## to "mask out" missing evaluations. Given received samples E(x) where
## missing positions are set to zero, we compute:
##
##   (E · Z)(x) = E(x) · Z(x)
##
## This product polynomial agrees with (P · Z)(x) at all non-missing
## positions, where P(x) is the original polynomial we want to recover.
##
## By computing (E · Z)(x) and then dividing by Z(x) in the coset domain
## (where Z(x) has no roots), we recover P(x).
##
## Algorithm
## =========
## The vanishing polynomial is constructed iteratively using synthetic
## multiplication:
##
##   Z(x) = 1
##   for each missing index i:
##     root = ω^i
##     Z(x) = Z(x) · (x - root)
##
## This results in O(m²) construction where m is the number of missing
## indices. For the PeerDAS setting (up to 64 missing out of 128 cells),
## this is efficient enough.
##
## For larger numbers of missing indices, the "zero_polynomial_via_multiplication"
## method can be used which achieves O(m log² m) using FFT-based polynomial
## multiplication (see c-kzg/src/recover.c).
##
## Memory Management
## =================
## This module uses stack allocation where possible and heap allocation
## only when necessary. All heap allocations use the aligned allocators
## from constantine/platforms/allocs.nim to ensure proper cache alignment.
##
## References
## ==========
## - rust-eth-kzg/papers/erasure_codes.md - Mathematical background
## - c-kzg/src/recover.c - zero_polynomial_via_multiplication
## - c-kzg-4844/src/eip7594/recovery.c - vanishing_polynomial_for_missing_cells
## - rust-kzg/blst/src/recovery.rs - Vanishing polynomial computation
## - consensus-specs/specs/fulu/polynomial-commitments-sampling.md
## - Ethereum Research: "Reed-Solomon erasure recovery via FFTs"

{.push raises:[].}

func vanishingPolynomial*[
      N: static int, F; Ord: static PolyOrdering,
      Domain: PolyEvalRootsDomain[N, F, Ord]](
        domain: Domain,
        dst: var PolynomialCoef[N, F],
        roots: openArray[F]) =
  ## Construct the vanishing polynomial for a set of roots.
  ##
  ## Z(x) = ∏ (x - root_i)
  ##
  ## Parameters
  ## ==========
  ## - dst: OUT parameter for vanishing polynomial in coefficient form
  ## - roots: Array of domain roots where polynomial should vanish
  ## - domain: FFT domain (roots of unity)
  ##
  ## Algorithm
  ## =========
  ## Uses synthetic multiplication to build Z(x) iteratively:
  ## - Start with Z(x) = -root_0
  ## - For each additional root, multiply Z(x) by (x - root_i)
  ##
  ## Complexity: O(m²) where m = roots.len
  ##
  ## Reference
  ## =========
  ## c-kzg-4844: compute_vanishing_polynomial_from_roots

  doAssert roots.len > 0, "At least one root must be provided"
  doAssert roots.len < N, "Cannot have all points vanish"

  # Initialize result to zero
  for i in 0 ..< N:
    dst.coefs[i].setZero()

  # Start with Z(x) = -root_0
  dst.coefs[0].neg(roots[0])

  # Iteratively multiply by (x - root_i)
  for i in 1 ..< roots.len:
    var neg_root {.noInit.}: F
    neg_root.neg(roots[i])

    # Update coefficients using synthetic multiplication
    # New coefficient at position i is neg_root
    dst.coefs[i] = neg_root
    dst.coefs[i] += dst.coefs[i-1]

    # Update middle coefficients
    for j in countdown(i - 1, 1):
      dst.coefs[j] *= neg_root
      dst.coefs[j] += dst.coefs[j-1]

    # Update constant term
    dst.coefs[0] *= neg_root

  # Set leading coefficient to 1
  dst.coefs[roots.len].setOne()

func vanishingPolynomialForIndices*[
      N, numIndices: static int, F; Ord: static PolyOrdering,
      Domain: PolyEvalRootsDomain[N, F, Ord]](
        domain: Domain,
        dst: var PolynomialCoef[N, F],
        indices: array[numIndices, uint64]) =
  ## Construct the vanishing polynomial for a set of indices.
  ##
  ## The polynomial evaluates to 0 at domain points corresponding
  ## to the specified indices.
  ##
  ## Parameters
  ## ==========
  ## - dst: OUT parameter for vanishing polynomial in coefficient form
  ## - indices: Array of indices where polynomial should vanish
  ## - domain: FFT domain (roots of unity)
  ##
  ## Note
  ## ====
  ## This is the static version where numIndices is known at compile time.
  ## Use vanishingPolynomialForIndicesRT for runtime-determined indices.

  var roots {.noInit.}: array[numIndices, F]

  for i in 0 ..< numIndices:
    roots[i] = domain.rootsOfUnity[int(indices[i])]

  domain.vanishingPolynomial(dst, roots.toOpenArray(0, indices.len - 1))

func vanishingPolynomialForIndicesRT*[
      N: static int, F; Ord: static PolyOrdering,
      Domain: PolyEvalRootsDomain[N, F, Ord]](
        domain: Domain,
        dst: var PolynomialCoef[N, F],
        indices: openArray[uint64]) =
  ## Construct the vanishing polynomial for a set of indices (runtime version).
  ##
  ## Parameters
  ## ==========
  ## - dst: OUT parameter for vanishing polynomial in coefficient form
  ## - indices: Array of indices where polynomial should vanish
  ## - domain: FFT domain (roots of unity)
  ##
  ## Memory Management
  ## =================
  ## Uses stack allocation for up to 256 indices. For larger numbers,
  ## heap allocation is used.
  ##
  ## Note
  ## ====
  ## This is the runtime version where the number of indices is not
  ## known at compile time. Prefer vanishingPolynomialForIndices when
  ## the count is static.

  doAssert indices.len > 0, "At least one index must be provided"
  doAssert indices.len < N, "Cannot have all points vanish"
  doAssert indices.len <= 256, "Too many missing indices"

  # Use stack allocation for efficiency
  var roots {.noInit.}: array[256, F]

  for i in 0 ..< indices.len:
    roots[i] = domain.rootsOfUnity[int(indices[i])]

  domain.vanishingPolynomial(dst, roots.toOpenArray(0, indices.len - 1))

func evalVanishingPolynomial*[
      N: static int, F; Ord: static PolyOrdering,
      Domain: PolyEvalRootsDomain[N, F, Ord]](
        domain: Domain,
        output: var openArray[F],
        indices: openArray[uint64]) =
  ## Evaluate the vanishing polynomial at all domain points.
  ##
  ## Parameters
  ## ==========
  ## - output: OUT parameter for evaluations (must have length N)
  ## - indices: Indices where polynomial should vanish
  ## - domain: FFT domain
  ##
  ## Algorithm
  ## =========
  ## 1. Compute Z(x) coefficients
  ## 2. Apply FFT to get evaluations over the domain

  var indices_arr: array[256, uint64] # TODO: untested and very suspicious
  doAssert indices.len <= 256
  for i in 0 ..< indices.len:
    indices_arr[i] = indices[i]

  var poly: PolynomialCoef[N, F]
  vanishingPolynomialForIndices(poly, indices_arr, domain)

  let fft_desc = FrFFT_Descriptor[F].new(
    order = N,
    generatorRootOfUnity = domain.rootsOfUnity[1]
  )

  for i in 0 ..< N:
    output[i] = poly.coefs[i]

  let status = ec_fft_nr(fft_desc, output, output)
  doAssert status == FFT_Success
