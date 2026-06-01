# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  ./towers,
  constantine/math/arithmetic,
  constantine/named/algebras,
  constantine/named/zoo_square_roots_fp2

# Square root
# -----------------------------------------------------------

func isSquare*(a: Fp2): SecretBool =
  ## Returns true if ``a`` is a square (quadratic residue) in 𝔽p2
  ##
  ## Assumes that the prime modulus ``p`` is public.
  # Implementation:
  #
  # (a0, a1) = a in F(p^2)
  # is_square(a) = is_square(|a|) over F(p)
  # where |a| = a0^2 + a1^2
  #
  # This can be done recursively in an extension tower
  #
  # https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-08#appendix-G.5
  # https://eprint.iacr.org/2012/685
  var tv1{.noInit.}, tv2{.noInit.}: typeof(a.c0)

  tv1.square(a.c0) #     a0²
  tv2.square(a.c1) # - β a1² with β = 𝑖² in a complex extension field
  when a.fromComplexExtension():
    tv1 += tv2     # a0 - (-1) a1²
  else:
    tv2 *= NonResidue
    tv1 -= tv2

  result = tv1.isSquare()

func sqrt_rotate_extension*(
       out_sqrt: var Fp2,
       candidate_sqrt: Fp2,
       a: Fp2
     ): SecretBool =
  ## From a field element `a` and a candidate Fp2 square root
  ## Search the actual square root by rotating candidate solution
  ## in the extension field by 90°
  ##
  ## if there is one, update out_sqrt with it and return true
  ## return false otherwise, out_sqrt is undefined in this case
  ##
  ## This avoids expensive trial "isSquare" checks
  ## This requires the sqrt of sqrt of the quadratic non-residue
  ## to be in Fp2
  var coeff{.noInit.}, cand2{.noInit.}, t{.noInit.}: Fp2
  const Curve = typeof(a.c0).Name

  # We name µ² the quadratic non-residue
  # if p ≡ 3 (mod 4), we have µ = 𝑖 = √-1 and µ² = -1
  # However for BLS12-377 we have µ = √-5

  # sqrt(cand)² = (a0 + µ a1)² = (a0²-a1²) + (2 a0a1) µ
  cand2.square(candidate_sqrt)

  block: # Test 1: (a0²-a1²) + (2 a0a1) µ == cand ? candidate is correct
    t.diff(cand2, a)
    result = t.isZero()
    coeff.setOne()

  block: # Test 2: -((a0²-a1²) + (2 a0a1) µ) == candidate ? candidate must be rotated by 90°
    t.sum(cand2, a)
    let isSol = t.isZero()
    coeff.ccopy(Curve.sqrt_fp2(QNR), isSol)
    result = result or isSol

  block: # Test 3: µ((a0²-a1²) + (2 a0a1) µ) == candidate ? candidate must be rotated by 135°
    t.c0.diff(cand2.c0, a.c1)
    t.c1.sum( cand2.c1, a.c0)
    let isSol = t.isZero()
    coeff.ccopy(Curve.sqrt_fp2(sqrt_QNR), isSol)
    result = result or isSol

  block: # Test 4: -µ((a0²-a1²) + (2 a0a1) µ) == candidate ? candidate must be rotated by 45°
    t.c0.sum( cand2.c0, a.c1)
    t.c1.diff(cand2.c1, a.c0)
    let isSol = t.isZero()
    coeff.ccopy(Curve.sqrt_fp2(minus_sqrt_QNR), isSol)
    result = result or isSol

  # Rotate the candidate
  out_sqrt.prod(candidate_sqrt, coeff)
  # result is set

func sqrt_if_square_opt(a: var Fp2): SecretBool =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ##
  ## This is an optimized version which is
  ## requires the sqrt of sqrt of the quadratic non-residue
  ## to be in Fp2
  #
  # Implementation via the complex method
  # Gora Adj, Francisco Rodríguez-Henríquez, 2012, https://eprint.iacr.org/2012/685
  # Made constant-time and optimized to fuse sqrt and inverse sqrt
  # and avoid unfused isSquare tests.
  # See discussion and optimization with Andy Polyakov
  # https://github.com/supranational/blst/issues/2#issuecomment-686656784
  var t1{.noInit.}, t2{.noInit.}: typeof(a.c0)
  var cand{.noInit.}: typeof(a)

  t1.square(a.c0) #     a0²
  t2.square(a.c1) # - β a1² with β = 𝑖² in a complex extension field
  when a.fromComplexExtension():
    t1 += t2      # a0² - (-1) a1²
  else:
    t2 *= NonResidue
    t1 -= t2

  # t1 being an actual sqrt will be tested in sqrt_rotate_extension
  t1.sqrt()                           # sqrt(a0² - β a1²)

  t2.diff(a.c0, t1)
  t1 += a.c0
  t1.ccopy(t2, t1.isZero())
  t1.div2()                           # (a0 ± sqrt(a0² - β a1²))/2

  # t1 being an actual sqrt will be tested in sqrt_rotate_extension
  cand.c0.invsqrt(t1)                 # 1/sqrt((a0 ± sqrt(a0² - β b²))/2)

  cand.c1 = a.c1
  cand.c1.div2()
  cand.c1 *= cand.c0                  # a1/(2*sqrt((a0 ± sqrt(a0² - β a1²))/2))
  cand.c0 *= t1                       # sqrt((a0 ± sqrt(a0² - β a1²))/2)

  # Now rotate to check if an actual sqrt exists.
  return sqrt_rotate_extension(a, cand, a)

func sqrt_if_square_generic(a: var Fp2): SecretBool =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ##
  ## This is a generic version
  # Implementation via the complex method
  # Gora Adj, Francisco Rodríguez-Henríquez, 2012,
  # https://eprint.iacr.org/2012/685
  # Made constant-time and optimized to fuse sqrt and inverse sqrt
  #
  # Note on the purely-real-input edge case:
  # Adj-Rodríguez Algorithm 8 (and Scott §6.3) has an unstated precondition
  # that a.c1 ≠ 0. For input (a0, 0) with a0 a non-residue in Fp, the
  # algorithm silently picks t2 = 0 below, sqrt_invsqrt(0) = (0, 0), and the
  # function reports `result = true` with `a` rewritten to (0, 0). But
  # (a0, 0) is *always* a square in Fp² (a0^((p²−1)/2) = (a0^(p−1))^((p+1)/2)
  # = 1), and the correct sqrt is (0, sqrt(a0 / β)) where β = u² is the
  # quadratic non-residue defining Fp². We compute that fallback
  # unconditionally in constant time and ccopy it in iff a.c1 was zero.
  var t1{.noInit.}, t2{.noInit.}, t3{.noInit.}: typeof(a.c0)

  # Save what we need for the purely-real-input fallback before mutating a.
  let a0_orig = a.c0
  let a1_isZero = a.c1.isZero()

  t1.square(a.c0) #     a0²
  t2.square(a.c1) # - β a1² with β = 𝑖² in a complex extension field
  when a.fromComplexExtension():
    t1 += t2    # a0 - (-1) a1²
  else:
    t2 *= NonResidue
    t1 -= t2

  result = t1.sqrt_if_square()

  t2.sum(a.c0, t1)
  t2.div2()

  t3.diff(a.c0, t1)
  t3.div2()

  let quadResidTest = t2.isSquare()
  t2.ccopy(t3, not quadResidTest)

  sqrt_invsqrt(sqrt = t1, invsqrt = t3, t2)
  a.c0.ccopy(t1, result)

  t3.div2()
  t3 *= a.c1
  a.c1.ccopy(t3, result)

  # Purely-real-input fallback (see the comment at the top of this function).
  # Compute the two candidate purely-real roots of (a0_orig, 0):
  #   - candidateA = (sqrt_fp(a0), 0)            valid iff a0 is a QR in Fp
  #   - candidateB = (0, sqrt_fp(a0 / β))        valid iff a0/β is a QR in Fp
  # For any nonzero a0 in Fp, at least one of {a0, a0/β} is a QR (since β
  # itself is a non-residue: QR × non-QR = non-QR, non-QR × non-QR = QR).
  # We always run both candidate computations for constant time, then
  # constant-time-select.
  var fbC0{.noInit.}, fbC1{.noInit.}: typeof(a.c0)
  fbC0.setZero()
  fbC1.setZero()

  var candA = a0_orig
  let candAOk = candA.sqrt_if_square()       # candA = sqrt(a0) iff a0 ∈ QR(Fp)
  fbC0.ccopy(candA, candAOk)

  var candB{.noInit.}: typeof(a.c0)
  var candBOk{.noInit.}: SecretBool
  when a.fromComplexExtension():
    # β = −1, so a0/β = −a0. Compute candidateB = (0, sqrt(−a0)).
    candB = a0_orig
    candB.neg()
    candBOk = candB.sqrt_if_square()
  else:
    # General case: use sqrt_ratio_if_square to compute √(a0/β) without an
    # explicit field inversion of β (the fused routine handles the ratio
    # via a single invsqrt, saving ~70-100 Fp muls per call).
    var beta{.noInit.}: typeof(a.c0)
    beta.setOne()
    beta *= NonResidue                        # beta = β
    candBOk = candB.sqrt_ratio_if_square(a0_orig, beta)
  # Use candidateB iff candidateA was not a QR but candidateB is.
  fbC1.ccopy(candB, (not candAOk) and candBOk)

  # Override the output with the fallback iff the input was purely-real and
  # is a square. The `and result` guard upholds the "a unmodified on failure"
  # contract; for (a0, 0) with a0 ≠ 0 the norm a0² is a square in Fp so
  # `result` is always true here, but the guard makes that explicit.
  let useFallback = a1_isZero and result
  a.c0.ccopy(fbC0, useFallback)
  a.c1.ccopy(fbC1, useFallback)

func sqrt_if_square*(a: var Fp2): SecretBool =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  when Fp2.Name == BLS12_377:
    # For BLS12_377,
    # the solution µ to x² - µ = 0 being a quadratic non-residue
    # is also a quadratic non-residue in Fp2, which means
    # we can't use the optimized version which saves an `isSquare`
    # which is about 33% of processing time
    # as isSquare, sqrt and invsqrt
    # all requires over 450 Fp multiplications.
    result = a.sqrt_if_square_generic()
  else:
    result = a.sqrt_if_square_opt()

func sqrt*(a: var Fp2) =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is undefined.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  discard a.sqrt_if_square()
