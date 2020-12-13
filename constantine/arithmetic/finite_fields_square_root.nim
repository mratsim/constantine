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
  ../curves/zoo_square_roots,
  ./bigints, ./finite_fields

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
  result = not(xi.isMinusOne())
  # xi can be:
  # -  1  if a square
  # -  0  if 0
  # - -1  if a quadratic non-residue
  debug:
    doAssert: bool(
      xi.isZero or
      xi.isOne or
      xi.isMinusOne()
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
  var test {.noInit.}: Fp[C]
  test.square(sqrt)
  result = test == a

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

# Tonelli Shanks for any prime
# ------------------------------------------------------------

func precompute_tonelli_shanks[C](
       a_pre_exp: var Fp[C],
       a: Fp[C]) =
  a_pre_exp = a
  a_pre_exp.powUnsafeExponent(C.tonelliShanks(exponent))

func isSquare_tonelli_shanks[C](
       a, a_pre_exp: Fp[C]): SecretBool =
  ## Returns if `a` is a quadratic residue
  ## This uses common precomputation for
  ## Tonelli-Shanks based square root and inverse square root
  ##
  ## a^((p-1-2^e)/(2*2^e))
  const e = C.tonelliShanks(twoAdicity)
  var r {.noInit.}: Fp[C]
  r.square(a_pre_exp) # a^(2(q-1-2^e)/(2*2^e)) = a^((q-1)/2^e - 1)
  r *= a              # a^((q-1)/2^e)
  for _ in 0 ..< e-1:
    r.square()        # a^((q-1)/2)

  result = not(r.isMinusOne())
  # r can be:
  # -  1  if a square
  # -  0  if 0
  # - -1  if a quadratic non-residue
  debug:
    doAssert: bool(
      r.isZero or
      r.isOne or
      r.isMinusOne()
    )

func sqrt_invsqrt_tonelli_shanks[C](
       sqrt, invsqrt: var Fp[C],
       a, a_pre_exp: Fp[C]) =
  ## Compute the square_root and inverse_square_root
  ## of `a` via constant-time Tonelli-Shanks
  ##
  ## a_pre_exp is a precomputation a^((p-1-2^e)/(2*2^e))
  ## ThItat is shared with the simultaneous isSquare routine
  template z: untyped = a_pre_exp
  template r: untyped = invsqrt
  var t {.noInit.}: Fp[C]
  const e = C.tonelliShanks(twoAdicity)

  t.square(z)
  t *= a
  r = z
  var b = t
  var root = C.tonelliShanks(root_of_unity)

  var buf {.noInit.}: Fp[C]

  for i in countdown(e, 2, 1):
    for j in 1 .. i-2:
      b.square()

    let bNotOne = not b.isOne()
    buf.prod(r, root)
    r.ccopy(buf, bNotOne)
    root.square()
    buf.prod(t, root)
    t.ccopy(buf, bNotOne)
    b = t

  sqrt.prod(invsqrt, a)

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
  ## This procedure is constant-time
  when (BaseType(C.Mod.limbs[0]) and 3) == 3:
    sqrt_p3mod4(a)
  else:
    var a_pre_exp{.noInit.}, sqrt{.noInit.}, invsqrt{.noInit.}: Fp[C]
    a_pre_exp.precompute_tonelli_shanks(a)
    sqrt_invsqrt_tonelli_shanks(sqrt, invsqrt, a, a_pre_exp)
    a = sqrt

func sqrt_if_square*[C](a: var Fp[C]): SecretBool {.inline.} =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  when (BaseType(C.Mod.limbs[0]) and 3) == 3:
    result = sqrt_if_square_p3mod4(a)
  else:
    var a_pre_exp{.noInit.}, sqrt{.noInit.}, invsqrt{.noInit.}: Fp[C]
    a_pre_exp.precompute_tonelli_shanks(a)
    result = isSquare_tonelli_shanks(a, a_pre_exp)
    sqrt_invsqrt_tonelli_shanks(sqrt, invsqrt, a, a_pre_exp)
    a = sqrt

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
  when (BaseType(C.Mod.limbs[0]) and 3) == 3:
    sqrt_invsqrt_p3mod4(sqrt, invsqrt, a)
  else:
    var a_pre_exp{.noInit.}: Fp[C]
    a_pre_exp.precompute_tonelli_shanks(a)
    sqrt_invsqrt_tonelli_shanks(sqrt, invsqrt, a, a_pre_exp)

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
  when (BaseType(C.Mod.limbs[0]) and 3) == 3:
    result = sqrt_invsqrt_if_square_p3mod4(sqrt, invsqrt, a)
  else:
    var a_pre_exp{.noInit.}: Fp[C]
    a_pre_exp.precompute_tonelli_shanks(a)
    result = isSquare_tonelli_shanks(a, a_pre_exp)
    sqrt_invsqrt_tonelli_shanks(sqrt, invsqrt, a, a_pre_exp)
    a = sqrt
