# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, type_ff, curves],
  ../curves/zoo_square_roots,
  ./bigints, ./finite_fields

# ############################################################
#
#                Field arithmetic square roots
#
# ############################################################

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# Legendre symbol / Euler's Criterion / Kronecker's symbol
# ------------------------------------------------------------

func isSquare*(a: Fp): SecretBool =
  ## Returns true if ``a`` is a square (quadratic residue) in 𝔽p
  ##
  ## Assumes that the prime modulus ``p`` is public.
  # Implementation: we use exponentiation by (p-1)/2 (Euler's criterion)
  #                 as it can reuse the exponentiation implementation
  #                 Note that we don't care about leaking the bits of p
  #                 as we assume that
  var xi {.noInit.} = a # TODO: is noInit necessary? see https://github.com/mratsim/constantine/issues/21
  xi.powUnsafeExponent(Fp.getPrimeMinus1div2_BE())
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

func hasP3mod4_primeModulus(C: static Curve): static bool =
  ## Returns true iff p ≡ 3 (mod 4)
  (BaseType(C.Mod.limbs[0]) and 3) == 3

func invsqrt_p3mod4*(r: var Fp, a: Fp) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ## and the prime field modulus ``p``: p ≡ 3 (mod 4)
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  # TODO: deterministic sign
  #
  # Algorithm
  #
  #
  # From Euler's criterion:   a^((p-1)/2)) ≡ 1 (mod p) if square
  # a^((p-1)/2)) * a^-1 ≡ 1/a  (mod p)
  # a^((p-3)/2))        ≡ 1/a  (mod p)
  # a^((p-3)/4))        ≡ 1/√a (mod p)      # Requires p ≡ 3 (mod 4)
  static: doAssert BaseType(Fp.C.Mod.limbs[0]) mod 4 == 3
  r = a
  r.powUnsafeExponent(Fp.getPrimeMinus3div4_BE())

# Specialized routines for addchain-based square roots
# ------------------------------------------------------------

{.pop.} # inline

# Tonelli Shanks for any prime
# ------------------------------------------------------------

func precompute_tonelli_shanks(
       a_pre_exp: var Fp,
       a: Fp, useAddChain: static bool) =
  a_pre_exp = a
  when useAddChain:
    a_pre_exp.precompute_tonelli_shanks_addchain(a)
  else:
    a_pre_exp.powUnsafeExponent(Fp.C.tonelliShanks(exponent))

func isSquare_tonelli_shanks(
       a, a_pre_exp: Fp): SecretBool {.used.} =
  ## Returns if `a` is a quadratic residue
  ## This uses common precomputation for
  ## Tonelli-Shanks based square root and inverse square root
  ##
  ## a^((p-1-2^e)/(2*2^e))
  ##
  ## Note: if we need to compute a candidate square root anyway
  ##       it's faster to square it to check if we get ``a``
  const e = Fp.C.tonelliShanks(twoAdicity)
  var r {.noInit.}: Fp
  r.square(a_pre_exp)    # a^(2(q-1-2^e)/(2*2^e)) = a^((q-1)/2^e - 1)
  r *= a                 # a^((q-1)/2^e)
  r.square_repeated(e-1) # a^((q-1)/2)

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

func invsqrt_tonelli_shanks_pre(
       invsqrt: var Fp,
       a, a_pre_exp: Fp) =
  ## Compute the inverse_square_root
  ## of `a` via constant-time Tonelli-Shanks
  ##
  ## a_pre_exp is a precomputation a^((p-1-2^e)/(2*2^e))
  ## That is shared with the simultaneous isSquare routine
  template z: untyped = a_pre_exp
  template r: untyped = invsqrt
  var t {.noInit.}: Fp
  const e = Fp.C.tonelliShanks(twoAdicity)

  t.square(z)
  t *= a
  r = z
  var b = t
  var root = Fp.C.tonelliShanks(root_of_unity)

  var buf {.noInit.}: Fp

  for i in countdown(e, 2, 1):
    b.square_repeated(i-2)

    let bNotOne = not b.isOne()
    buf.prod(r, root)
    r.ccopy(buf, bNotOne)
    root.square()
    buf.prod(t, root)
    t.ccopy(buf, bNotOne)
    b = t

func invsqrt_tonelli_shanks*(r: var Fp, a: Fp, useAddChain: static bool) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var a_pre_exp{.noInit.}: Fp
  a_pre_exp.precompute_tonelli_shanks(a, useAddChain)
  invsqrt_tonelli_shanks_pre(r, a, a_pre_exp)

# Public routines
# ------------------------------------------------------------
# Note: we export the inner sqrt_invsqrt_IMPL
#       for benchmarking purposes.

{.push inline.}

func invsqrt*[C](r: var Fp[C], a: Fp[C]) =
  ## Compute the inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  when C.hasSqrtAddchain():
    r.invsqrt_addchain(a)
  elif C.hasP3mod4_primeModulus():
    r.invsqrt_p3mod4(a)
  else:
    r.invsqrt_tonelli_shanks(a, useAddChain = C.hasTonelliShanksAddchain())

func sqrt*[C](a: var Fp[C]) =
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
  var t {.noInit.}: Fp[C]
  t.invsqrt(a)
  a *= t

func sqrt_invsqrt*[C](sqrt, invsqrt: var Fp[C], a: Fp[C]) =
  ## Compute the square root and inverse square root of ``a``
  ##
  ## This requires ``a`` to be a square
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  invsqrt.invsqrt(a)
  sqrt.prod(invsqrt, a)

func sqrt_invsqrt_if_square*[C](sqrt, invsqrt: var Fp[C], a: Fp[C]): SecretBool  =
  ## Compute the square root and ivnerse square root of ``a``
  ##
  ## This returns true if ``a`` is square and sqrt/invsqrt contains the square root/inverse square root
  ##
  ## The result is undefined otherwise
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  sqrt_invsqrt(sqrt, invsqrt, a)
  var test {.noInit.}: Fp[C]
  test.square(sqrt)
  result = test == a

func sqrt_if_square*[C](a: var Fp[C]): SecretBool =
  ## If ``a`` is a square, compute the square root of ``a``
  ## if not, ``a`` is undefined.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var sqrt{.noInit.}, invsqrt{.noInit.}: Fp[C]
  result = sqrt_invsqrt_if_square(sqrt, invsqrt, a)
  a = sqrt

func invsqrt_if_square*[C](r: var Fp[C], a: Fp[C]): SecretBool =
  ## If ``a`` is a square, compute the inverse square root of ``a``
  ## if not, ``a`` is undefined.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ## This procedure is constant-time
  var sqrt{.noInit.}: Fp[C]
  result = sqrt_invsqrt_if_square(sqrt, r, a)

{.pop.} # inline
{.pop.} # raises no exceptions
