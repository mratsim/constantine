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
  ../config/[common, type_fp, type_fr, curves],
  ./bigints, ./limbs_montgomery

when UseASM_X86_64:
  import ./assembly/limbs_asm_modular_x86

when nimvm:
  from ../config/precompute import montyResidue_precompute
else:
  discard

export Fp, Fr

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                        Conversion
#
# ############################################################

func fromBig*[C: static Curve](dst: var Fp[C], src: BigInt) {.inline.}=
  ## Convert a BigInt to its Montgomery form
  when nimvm:
    dst.mres.montyResidue_precompute(src, C.Mod, C.getR2modP(), C.getNegInvModWord())
  else:
    dst.mres.montyResidue(src, C.Mod, C.getR2modP(), C.getNegInvModWord(), C.canUseNoCarryMontyMul())

func fromBig*[C: static Curve](T: type Fp[C], src: BigInt): Fp[C] {.noInit, inline.} =
  ## Convert a BigInt to its Montgomery form
  result.fromBig(src)

func toBig*(src: Fp): auto {.noInit, inline.} =
  ## Convert a finite-field element to a BigInt in natural representation
  var r {.noInit.}: typeof(src.mres)
  r.redc(src.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontyMul())
  return r

# Copy
# ------------------------------------------------------------

func ccopy*(a: var Fp, b: Fp, ctl: SecretBool) {.inline.} =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  ccopy(a.mres, b.mres, ctl)

func cswap*(a, b: var Fp, ctl: CTBool) {.inline.} =
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

func `==`*(a, b: Fp): SecretBool {.inline.} =
  ## Constant-time equality check
  a.mres == b.mres

func isZero*(a: Fp): SecretBool {.inline.} =
  ## Constant-time check if zero
  a.mres.isZero()

func isOne*(a: Fp): SecretBool {.inline.} =
  ## Constant-time check if one
  a.mres == Fp.C.getMontyOne()

func isMinusOne*(a: Fp): SecretBool {.inline.} =
  ## Constant-time check if -1 (mod p)
  a.mres == Fp.C.getMontyPrimeMinus1()

func setZero*(a: var Fp) {.inline.} =
  ## Set ``a`` to zero
  a.mres.setZero()

func setOne*(a: var Fp) {.inline.} =
  ## Set ``a`` to one
  # Note: we need 1 in Montgomery residue form
  # TODO: Nim codegen is not optimal it uses a temporary
  #       Check if the compiler optimizes it away
  a.mres = Fp.C.getMontyOne()

func `+=`*(a: var Fp, b: Fp) {.inline.} =
  ## In-place addition modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    addmod_asm(a.mres.limbs, b.mres.limbs, Fp.C.Mod.limbs)
  else:
    var overflowed = add(a.mres, b.mres)
    overflowed = overflowed or not(a.mres < Fp.C.Mod)
    discard csub(a.mres, Fp.C.Mod, overflowed)

func `-=`*(a: var Fp, b: Fp) {.inline.} =
  ## In-place substraction modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    submod_asm(a.mres.limbs, b.mres.limbs, Fp.C.Mod.limbs)
  else:
    let underflowed = sub(a.mres, b.mres)
    discard cadd(a.mres, Fp.C.Mod, underflowed)

func double*(a: var Fp) {.inline.} =
  ## Double ``a`` modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    addmod_asm(a.mres.limbs, a.mres.limbs, Fp.C.Mod.limbs)
  else:
    var overflowed = double(a.mres)
    overflowed = overflowed or not(a.mres < Fp.C.Mod)
    discard csub(a.mres, Fp.C.Mod, overflowed)

func sum*(r: var Fp, a, b: Fp) {.inline.} =
  ## Sum ``a`` and ``b`` into ``r`` modulo p
  ## r is initialized/overwritten
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    r = a
    addmod_asm(r.mres.limbs, b.mres.limbs, Fp.C.Mod.limbs)
  else:
    var overflowed = r.mres.sum(a.mres, b.mres)
    overflowed = overflowed or not(r.mres < Fp.C.Mod)
    discard csub(r.mres, Fp.C.Mod, overflowed)

func sumNoReduce*(r: var Fp, a, b: Fp) {.inline.} =
  ## Sum ``a`` and ``b`` into ``r`` without reduction
  discard r.mres.sum(a.mres, b.mres)

func diff*(r: var Fp, a, b: Fp) {.inline.} =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  ## Requires r != b
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    r = a
    submod_asm(r.mres.limbs, b.mres.limbs, Fp.C.Mod.limbs)
  else:
    var underflowed = r.mres.diff(a.mres, b.mres)
    discard cadd(r.mres, Fp.C.Mod, underflowed)

func diffAlias*(r: var Fp, a, b: Fp) {.inline.} =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  ## Handles r == b
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    var t = a
    submod_asm(t.mres.limbs, b.mres.limbs, Fp.C.Mod.limbs)
    r = t
  else:
    var underflowed = r.mres.diff(a.mres, b.mres)
    discard cadd(r.mres, Fp.C.Mod, underflowed)

func diffNoReduce*(r: var Fp, a, b: Fp) {.inline.} =
  ## Substract `b` from `a` and store the result into `r`
  ## without reduction
  discard r.mres.diff(a.mres, b.mres)

func double*(r: var Fp, a: Fp) {.inline.} =
  ## Double ``a`` into ``r``
  ## `r` is initialized/overwritten
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    r = a
    addmod_asm(r.mres.limbs, a.mres.limbs, Fp.C.Mod.limbs)
  else:
    var overflowed = r.mres.double(a.mres)
    overflowed = overflowed or not(r.mres < Fp.C.Mod)
    discard csub(r.mres, Fp.C.Mod, overflowed)

func prod*(r: var Fp, a, b: Fp) {.inline.} =
  ## Store the product of ``a`` by ``b`` modulo p into ``r``
  ## ``r`` is initialized / overwritten
  r.mres.montyMul(a.mres, b.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontyMul())

func square*(r: var Fp, a: Fp) {.inline.} =
  ## Squaring modulo p
  r.mres.montySquare(a.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontySquare())

func neg*(r: var Fp, a: Fp) {.inline.} =
  ## Negate modulo p
  when UseASM_X86_64 and defined(gcc):
    # Clang and every compiler besides GCC
    # can cleanly optimized this
    # especially on Fp2
    negmod_asm(r.mres.limbs, a.mres.limbs, Fp.C.Mod.limbs)
  else:
    discard r.mres.diff(Fp.C.Mod, a.mres)

func neg*(a: var Fp) {.inline.} =
  ## Negate modulo p
  a.neg(a)

func div2*(a: var Fp) {.inline.} =
  ## Modular division by 2
  a.mres.div2_modular(Fp.C.getPrimePlus1div2())

# ############################################################
#
#                Field arithmetic conditional
#
# ############################################################

func cneg*(r: var Fp, a: Fp, ctl: SecretBool) =
  ## Constant-time in-place conditional negation
  ## The negation is only performed if ctl is "true"
  r.neg(a)
  r.ccopy(a, not ctl)

func cneg*(a: var Fp, ctl: SecretBool) =
  ## Constant-time in-place conditional negation
  ## The negation is only performed if ctl is "true"
  var t = a
  a.cneg(t, ctl)

func cadd*(a: var Fp, b: Fp, ctl: SecretBool) =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  var t = a
  t += b
  a.ccopy(t, ctl)

func csub*(a: var Fp, b: Fp, ctl: SecretBool) =
  ## Constant-time in-place conditional substraction
  ## The substraction is only performed if ctl is "true"
  var t = a
  t -= b
  a.ccopy(t, ctl)

# ############################################################
#
#               Field arithmetic exponentiation
#
# ############################################################
#
# Internally those procedures will allocate extra scratchspace on the stack

func pow*(a: var Fp, exponent: BigInt) {.inline.} =
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

func pow*(a: var Fp, exponent: openarray[byte]) {.inline.} =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer in canonical big endian representation
  const windowSize = 5 # TODO: find best window size for each curves
  a.mres.montyPow(
    exponent,
    Fp.C.Mod, Fp.C.getMontyOne(),
    Fp.C.getNegInvModWord(), windowSize,
    Fp.C.canUseNoCarryMontyMul(),
    Fp.C.canUseNoCarryMontySquare()
  )

func powUnsafeExponent*(a: var Fp, exponent: BigInt) {.inline.} =
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

func powUnsafeExponent*(a: var Fp, exponent: openarray[byte]) {.inline.} =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer a big integer in canonical big endian representation
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
#            Field arithmetic ergonomic primitives
#
# ############################################################
#
# This implements extra primitives for ergonomics.
# The in-place ones should be preferred as they avoid copies on assignment
# Two kinds:
# - Those that return a field element
# - Those that internally allocate a temporary field element

func `+`*(a, b: Fp): Fp {.noInit, inline.} =
  ## Addition modulo p
  result.sum(a, b)

func `-`*(a, b: Fp): Fp {.noInit, inline.} =
  ## Substraction modulo p
  result.diff(a, b)

func `*`*(a, b: Fp): Fp {.noInit, inline.} =
  ## Multiplication modulo p
  ##
  ## It is recommended to assign with {.noInit.}
  ## as Fp elements are usually large and this
  ## routine will zero init internally the result.
  result.prod(a, b)

func `*=`*(a: var Fp, b: Fp) {.inline.} =
  ## Multiplication modulo p
  a.prod(a, b)

func square*(a: var Fp) {.inline.} =
  ## Squaring modulo p
  a.mres.montySquare(a.mres, Fp.C.Mod, Fp.C.getNegInvModWord(), Fp.C.canUseNoCarryMontySquare())

func square_repeated*(r: var Fp, num: int) {.inline.} =
  ## Repeated squarings
  for _ in 0 ..< num:
    r.square()

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
