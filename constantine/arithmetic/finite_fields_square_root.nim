# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, type_fp, curves],
  ./bigints, ./finite_fields, ./limbs_montgomery

# ############################################################
#
#                Field arithmetic square roots
#
# ############################################################

# Legendre symbol / Euler's Criterion / Kronecker's symbol
# ------------------------------------------------------------

func isSquare*[C](a: Fp[C]): SecretBool {.inline.} =
  ## Returns true if ``a`` is a square (quadratic residue) in 𝔽p
  ##
  ## Assumes that the prime modulus ``p`` is public.
  # Implementation: we use exponentiation by (p-1)/2 (Euler's criterion)
  #                 as it can reuse the exponentiation implementation
  #                 Note that we don't care about leaking the bits of p
  #                 as we assume that
  var xi {.noInit.} = a # TODO: is noInit necessary? see https://github.com/mratsim/constantine/issues/21
  xi.powUnsafeExponent(C.getPrimeMinus1div2_BE())
  result = not(xi.mres == C.getMontyPrimeMinus1())
  # xi can be:
  # -  1  if a square
  # -  0  if 0
  # - -1  if a quadratic non-residue
  debug:
    doAssert: bool(
      xi.isZero or
      xi.isOne or
      xi.mres == C.getMontyPrimeMinus1()
    )

# Specialized routine for p ≡ 3 (mod 4)
# ------------------------------------------------------------

func sqrt_p3mod4[C](a: var Fp[C]) {.inline.} =
  ## Compute the square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ## and the prime field modulus ``p``: p ≡ 3 (mod 4)
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  static: doAssert BaseType(C.Mod.limbs[0]) mod 4 == 3
  a.powUnsafeExponent(C.getPrimePlus1div4_BE())

func sqrt_invsqrt_p3mod4[C](sqrt, invsqrt: var Fp[C], a: Fp[C]) {.inline.} =
  ## If ``a`` is a square, compute the square root of ``a`` in sqrt
  ## and the inverse square root of a in invsqrt
  ##
  ## This assumes that the prime field modulus ``p``: p ≡ 3 (mod 4)
  # TODO: deterministic sign
  #
  # Algorithm
  #
  #
  # From Euler's criterion:   a^((p-1)/2)) ≡ 1 (mod p) if square
  # a^((p-1)/2)) * a^-1 ≡ 1/a  (mod p)
  # a^((p-3)/2))        ≡ 1/a  (mod p)
  # a^((p-3)/4))        ≡ 1/√a (mod p)      # Requires p ≡ 3 (mod 4)
  static: doAssert BaseType(C.Mod.limbs[0]) mod 4 == 3

  invsqrt = a
  invsqrt.powUnsafeExponent(C.getPrimeMinus3div4_BE())
  # √a ≡ a * 1/√a ≡ a^((p+1)/4) (mod p)
  sqrt.prod(invsqrt, a)

func sqrt_invsqrt_if_square_p3mod4[C](sqrt, invsqrt: var Fp[C], a: Fp[C]): SecretBool {.inline.} =
  ## If ``a`` is a square, compute the square root of ``a`` in sqrt
  ## and the inverse square root of a in invsqrt
  ##
  ## If a is not square, sqrt and invsqrt are undefined
  ##
  ## This assumes that the prime field modulus ``p``: p ≡ 3 (mod 4)
  sqrt_invsqrt_p3mod4(sqrt, invsqrt, a)
  var euler {.noInit.}: Fp[C]
  euler.prod(sqrt, invsqrt)
  result = not(euler.mres == C.getMontyPrimeMinus1())

func sqrt_if_square_p3mod4[C](a: var Fp[C]): SecretBool {.inline.} =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## This assumes that the prime field modulus ``p``: p ≡ 3 (mod 4)
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  var sqrt {.noInit.}, invsqrt {.noInit.}: Fp[C]
  result = sqrt_invsqrt_if_square_p3mod4(sqrt, invsqrt, a)
  a.ccopy(sqrt, result)

# Public routines
# ------------------------------------------------------------

func sqrt*[C](a: var Fp[C]) {.inline.} =
  ## Compute the square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  when BaseType(C.Mod.limbs[0]) mod 4 == 3:
    sqrt_p3mod4(a)
  else:
    {.error: "Square root is only implemented for p ≡ 3 (mod 4)".}

func sqrt_if_square*[C](a: var Fp[C]): SecretBool {.inline.} =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  when BaseType(C.Mod.limbs[0]) mod 4 == 3:
    result = sqrt_if_square_p3mod4(a)
  else:
    {.error: "Square root is only implemented for p ≡ 3 (mod 4)".}

func sqrt_invsqrt*[C](sqrt, invsqrt: var Fp[C], a: Fp[C]) {.inline.} =
  ## Compute the square root and inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  when BaseType(C.Mod.limbs[0]) mod 4 == 3:
    sqrt_invsqrt_p3mod4(sqrt, invsqrt, a)
  else:
    {.error: "Square root is only implemented for p ≡ 3 (mod 4)".}

func sqrt_invsqrt_if_square*[C](sqrt, invsqrt: var Fp[C], a: Fp[C]): SecretBool  {.inline.} =
  ## Compute the square root and ivnerse square root of ``a``
  ##
  ## This returns true if ``a`` is square and sqrt/invsqrt contains the square root/inverse square root
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  when BaseType(C.Mod.limbs[0]) mod 4 == 3:
    result = sqrt_invsqrt_if_square_p3mod4(sqrt, invsqrt, a)
  else:
    {.error: "Square root is only implemented for p ≡ 3 (mod 4)".}
