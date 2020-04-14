# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#    Fp: Finite Field arithmetic with prime field modulus P
#
# ############################################################

# Constraints:
# - We assume that p is known at compile-time
# - We assume that p is not even:
#   - Operations are done in the Montgomery domain
#   - The Montgomery domain introduce a Montgomery constant that must be coprime
#     with the field modulus.
#   - The constant is chosen a power of 2
#   => to be coprime with a power of 2, p must be odd
# - We assume that p is a prime
#   - Modular inversion uses the Fermat's little theorem
#     which requires a prime

import
  ../primitives,
  ../config/[common, curves],
  ./bigints, ./limbs_montgomery

type
  Fp*[C: static Curve] = object
    ## All operations on a field are modulo P
    ## P being the prime modulus of the Curve C
    ## Internally, data is stored in Montgomery n-residue form
    ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
    mres*: matchingBigInt(C)

debug:
  func `$`*[C: static Curve](a: Fp[C]): string =
    result = "Fp[" & $C
    result.add "]("
    result.add $a.mres
    result.add ')'

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#                        Conversion
#
# ############################################################

func fromBig*[C: static Curve](T: type Fp[C], src: BigInt): Fp[C] {.noInit.} =
  ## Convert a BigInt to its Montgomery form
  result.mres.montyResidue(src, C.Mod, C.getR2modP(), C.getNegInvModWord(), C.canUseNoCarryMontyMul())

func fromBig*[C: static Curve](dst: var Fp[C], src: BigInt) {.noInit.} =
  ## Convert a BigInt to its Montgomery form
  dst.mres.montyResidue(src, C.Mod, C.getR2modP(), C.getNegInvModWord(), C.canUseNoCarryMontyMul())

func toBig*(src: Fp): auto {.noInit.} =
  ## Convert a finite-field element to a BigInt in natural representation
  var r {.noInit.}: typeof(src.mres)
  r.redc(src.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontyMul())
  return r

# Copy
# ------------------------------------------------------------

func ccopy*(a: var Fp, b: Fp, ctl: CTBool[Word]) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  ccopy(a.mres, b.mres, ctl)

func cswap*(a, b: var Fp, ctl: CTBool) =
  ## Swap ``a`` and ``b`` if ``ctl`` is true
  ##
  ## Constant-time:
  ## Whether ``ctl`` is true or not, the same
  ## memory accesses are done (unless the compiler tries to be clever)
  cswap(a.mres, b.mres, ctl)

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################
#
# Note: the library currently implements generic routine for odd field modulus.
#       Routines for special field modulus form:
#       - Mersenne Prime (2^k - 1),
#       - Generalized Mersenne Prime (NIST Prime P256: 2^256 - 2^224 + 2^192 + 2^96 - 1)
#       - Pseudo-Mersenne Prime (2^m - k for example Curve25519: 2^255 - 19)
#       - Golden Primes (φ^2 - φ - 1 with φ = 2^k for example Ed448-Goldilocks: 2^448 - 2^224 - 1)
#       exist and can be implemented with compile-time specialization.

# Note: for `+=`, double, sum
#       not(a.mres < Fp.C.Mod) is unnecessary if the prime has the form
#       (2^64)^w - 1 (if using uint64 words).
# In practice I'm not aware of such prime being using in elliptic curves.
# 2^127 - 1 and 2^521 - 1 are used but 127 and 521 are not multiple of 32/64

func `==`*(a, b: Fp): CTBool[Word] =
  ## Constant-time equality check
  a.mres == b.mres

func isZero*(a: Fp): CTBool[Word] =
  ## Constant-time check if zero
  a.mres.isZero()

func isOne*(a: Fp): CTBool[Word] =
  ## Constant-time check if one
  a.mres == Fp.C.getMontyOne()

func setZero*(a: var Fp) =
  ## Set ``a`` to zero
  a.mres.setZero()

func setOne*(a: var Fp) =
  ## Set ``a`` to one
  # Note: we need 1 in Montgomery residue form
  # TODO: Nim codegen is not optimal it uses a temporary
  #       Check if the compiler optimizes it away
  a.mres = Fp.C.getMontyOne()

func `+=`*(a: var Fp, b: Fp) =
  ## In-place addition modulo p
  var overflowed = add(a.mres, b.mres)
  overflowed = overflowed or not(a.mres < Fp.C.Mod)
  discard csub(a.mres, Fp.C.Mod, overflowed)

func `-=`*(a: var Fp, b: Fp) =
  ## In-place substraction modulo p
  let underflowed = sub(a.mres, b.mres)
  discard cadd(a.mres, Fp.C.Mod, underflowed)

func double*(a: var Fp) =
  ## Double ``a`` modulo p
  var overflowed = double(a.mres)
  overflowed = overflowed or not(a.mres < Fp.C.Mod)
  discard csub(a.mres, Fp.C.Mod, overflowed)

func sum*(r: var Fp, a, b: Fp) =
  ## Sum ``a`` and ``b`` into ``r`` module p
  ## r is initialized/overwritten
  var overflowed = r.mres.sum(a.mres, b.mres)
  overflowed = overflowed or not(r.mres < Fp.C.Mod)
  discard csub(r.mres, Fp.C.Mod, overflowed)

func diff*(r: var Fp, a, b: Fp) =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  var underflowed = r.mres.diff(a.mres, b.mres)
  discard cadd(r.mres, Fp.C.Mod, underflowed)

func double*(r: var Fp, a: Fp) =
  ## Double ``a`` into ``r``
  ## `r` is initialized/overwritten
  var overflowed = r.mres.double(a.mres)
  overflowed = overflowed or not(r.mres < Fp.C.Mod)
  discard csub(r.mres, Fp.C.Mod, overflowed)

func prod*(r: var Fp, a, b: Fp) =
  ## Store the product of ``a`` by ``b`` modulo p into ``r``
  ## ``r`` is initialized / overwritten
  r.mres.montyMul(a.mres, b.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontyMul())

func square*(r: var Fp, a: Fp) =
  ## Squaring modulo p
  r.mres.montySquare(a.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontySquare())

func neg*(r: var Fp, a: Fp) =
  ## Negate modulo p
  discard r.mres.diff(Fp.C.Mod, a.mres)

# ############################################################
#
#         Field arithmetic exponentiation and inversion
#
# ############################################################
#
# Internally those procedures will allocate extra scratchspace on the stack

func pow*(a: var Fp, exponent: BigInt) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPow(
    exponent,
    Fp.C.Mod, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize,
    Fp.C.canUseNoCarryMontyMul(),
    Fp.C.canUseNoCarryMontySquare()
  )

func powUnsafeExponent*(a: var Fp, exponent: BigInt) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPowUnsafeExponent(
    exponent,
    Fp.C.Mod, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize,
    Fp.C.canUseNoCarryMontyMul(),
    Fp.C.canUseNoCarryMontySquare()
  )

func powUnsafeExponent*(a: var Fp, exponent: openarray[byte]) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPowUnsafeExponent(
    exponent,
    Fp.C.Mod, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize,
    Fp.C.canUseNoCarryMontyMul(),
    Fp.C.canUseNoCarryMontySquare()
  )

# ############################################################
#
#                Field arithmetic square roots
#
# ############################################################

func isSquare*[C](a: Fp[C]): CTBool[Word] =
  ## Returns true if ``a`` is a square (quadratic residue) in 𝔽p
  ##
  ## Assumes that the prime modulus ``p`` is public.
  # Implementation: we use exponentiation by (p-1)/2 (Euler(s criterion)
  #                 as it can reuse the exponentiation implementation
  #                 Note that we don't care about leaking the bits of p
  #                 as we assume that
  var xi {.noInit.} = a # TODO: is noInit necessary? see https://github.com/mratsim/constantine/issues/21
  xi.powUnsafeExponent(C.getPrimeMinus1div2_BE())
  result = xi.isOne()
  # 0 is also a square
  result = result or xi.isZero()

func sqrt_p3mod4*[C](a: var Fp[C]) =
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
  static: doAssert C.Mod.limbs[0].BaseType mod 4 == 3
  a.powUnsafeExponent(C.getPrimePlus1div4_BE())

func sqrt_if_square_p3mod4*[C](a: var Fp[C]): CTBool[Word] =
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
  static: doAssert C.Mod.limbs[0].BaseType mod 4 == 3

  var a1 {.noInit.} = a
  a1.powUnsafeExponent(C.getPrimeMinus3div4_BE())

  var a1a {.noInit.}: Fp[C]
  a1a.prod(a1, a)

  var a0 {.noInit.}: Fp[C]
  a0.prod(a1a, a1)

  result = not(a0.mres == C.getMontyPrimeMinus1())
  a.ccopy(a1a, result)

# ############################################################
#
#            Field arithmetic ergonomic primitives
#
# ############################################################
#
# This implements extra primitives for ergonomics.
# The in-place ones should be preferred as they avoid copies on assignment
# Two kinds:
# - Those that return a field element
# - Those that internally allocate a temporary field element

func `+`*(a, b: Fp): Fp {.noInit.} =
  ## Addition modulo p
  result.sum(a, b)

func `-`*(a, b: Fp): Fp {.noInit.} =
  ## Substraction modulo p
  result.diff(a, b)

func `*`*(a, b: Fp): Fp {.noInit.} =
  ## Multiplication modulo p
  ##
  ## It is recommended to assign with {.noInit.}
  ## as Fp elements are usually large and this
  ## routine will zero init internally the result.
  result.prod(a, b)

func `*=`*(a: var Fp, b: Fp) =
  ## Multiplication modulo p
  a.prod(a, b)

func square*(a: var Fp) =
  ## Squaring modulo p
  a.mres.montySquare(a.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontySquare())

func `*=`*(a: var Fp, b: static int) {.inline.} =
  ## Multiplication by a small integer known at compile-time
  # Implementation:
  # We don't want to go convert the integer to the Montgomery domain (O(n²))
  # and then multiply by ``b`` (another O(n²)
  #
  # So we hardcode addition chains for small integer
  #
  # In terms of cost a doubling/addition is 3 passes over the data:
  # - addition + check if > prime + conditional substraction
  # A full multiplication, assuming b is projected to Montgomery domain beforehand is:
  # - n² passes over the data, each of 5~6 elementary addition/multiplication
  # - a conditional substraction
  #
  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    a.neg(a)
  when b == 0:
    a.setZero()
  elif b == 1:
    return
  elif b == 2:
    a.double()
  elif b == 3:
    let t1 = a
    a.double()
    a += t1
  elif b == 4:
    a.double()
    a.double()
  elif b == 5:
    let t1 = a
    a.double()
    a.double()
    a += t1
  elif b == 6:
    a.double()
    let t2 = a
    a.double() # 4
    a += t2
  elif b == 7:
    let t1 = a
    a.double()
    let t2 = a
    a.double() # 4
    a += t2
    a += t1
  elif b == 8:
    a.double()
    a.double()
    a.double()
  elif b == 9:
    let t1 = a
    a.double()
    a.double()
    a.double() # 8
    a += t1
  elif b == 10:
    a.double()
    let t2 = a
    a.double()
    a.double() # 8
    a += t2
  elif b == 11:
    let t1 = a
    a.double()
    let t2 = a
    a.double()
    a.double() # 8
    a += t2
    a += t1
  elif b == 12:
    a.double()
    a.double() # 4
    let t4 = a
    a.double() # 8
    a += t4
  else:
    {.error: "Multiplication by this small int not implemented".}

func `*`*(b: static int, a: Fp): Fp {.noinit, inline.} =
  ## Multiplication by a small integer known at compile-time
  result = a
  result *= b
