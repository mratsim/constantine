# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                FF: Finite Field arithmetic
#              Fp: with prime field modulus P
#           Fr: with prime curve subgroup order r
#
# ############################################################

# Constraints:
# - We assume that p and r are known at compile-time
# - We assume that p and r are not even:
#   - Operations are done in the Montgomery domain
#   - The Montgomery domain introduce a Montgomery constant that must be coprime
#     with the field modulus.
#   - The constant is chosen a power of 2
#   => to be coprime with a power of 2, p and r must be odd
# - We assume that p and r are a prime
#   - Modular inversion may use the Fermat's little theorem
#     which requires a prime

import
  constantine/platforms/abstractions,
  constantine/serialization/endians,
  constantine/named/properties_fields,
  ./bigints, ./bigints_montgomery,
  ./limbs_crandall, ./limbs_extmul

when UseASM_X86_64:
  import ./assembly/limbs_asm_modular_x86

when nimvm:
  from constantine/named/deriv/precompute import montyResidue_precompute
else:
  discard

export Fp, Fr, FF

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#                        Conversion
#
# ############################################################

func fromBig*(dst: var FF, src: BigInt) =
  ## Convert a BigInt to its Montgomery form
  when FF.isCrandallPrimeField():
    dst.mres = src
  else:
    when nimvm:
      dst.mres.montyResidue_precompute(src, FF.getModulus(), FF.getR2modP(), FF.getNegInvModWord())
    else:
      dst.mres.getMont(src, FF.getModulus(), FF.getR2modP(), FF.getNegInvModWord(), FF.getSpareBits())

func fromBig*[Name: static Algebra](T: type FF[Name], src: BigInt): FF[Name] {.noInit.} =
  ## Convert a BigInt to its Montgomery form
  result.fromBig(src)

func fromField*(dst: var BigInt, src: FF) {.inline.} =
  ## Convert a finite-field element to a BigInt in natural representation
  when FF.isCrandallPrimeField():
    dst = src.mres
  else:
    dst.fromMont(src.mres, FF.getModulus(), FF.getNegInvModWord(), FF.getSpareBits())

func toBig*(src: FF): auto {.noInit, inline.} =
  ## Convert a finite-field element to a BigInt in natural representation
  var r {.noInit.}: typeof(src.mres)
  r.fromField(src)
  return r

# Copy
# ------------------------------------------------------------

func ccopy*(a: var FF, b: FF, ctl: SecretBool) {.meter.} =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  ccopy(a.mres, b.mres, ctl)

func cswap*(a, b: var FF, ctl: SecretBool) {.meter.} =
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
#       - Mersenne Prime (2ᵏ - 1),
#       - Generalized Mersenne Prime (NIST Prime P256: 2^256 - 2^224 + 2^192 + 2^96 - 1)
#       - Pseudo-Mersenne Prime (2^m - k for example Edwards25519: 2^255 - 19)
#       - Golden Primes (φ^2 - φ - 1 with φ = 2ᵏ for example Ed448-Goldilocks: 2^448 - 2^224 - 1)
#       exist and can be implemented with compile-time specialization.

# Note: for `+=`, double, sum
#       not(a.mres < FF.getModulus()) is unnecessary if the prime has the form
#       (2^64)ʷ - 1 (if using uint64 words).
# In practice I'm not aware of such prime being using in elliptic curves.
# 2^127 - 1 and 2^521 - 1 are used but 127 and 521 are not multiple of 32/64

func `==`*(a, b: FF): SecretBool =
  ## Constant-time equality check
  a.mres == b.mres

func isZero*(a: FF): SecretBool =
  ## Constant-time check if zero
  a.mres.isZero()

func isOne*(a: FF): SecretBool =
  ## Constant-time check if one
  when FF.isCrandallPrimeField():
    a.mres.isOne()
  else:
    a.mres == FF.getMontyOne()

func isMinusOne*(a: FF): SecretBool =
  ## Constant-time check if -1 (mod p)
  when FF.isCrandallPrimeField:
    {.error: "Not implemented".}
  else:
    a.mres == FF.getMontyPrimeMinus1()

func isOdd*(a: FF): SecretBool {.
  error: "Do you need the actual value to be odd\n" &
         "or what it represents (so once converted out of the Montgomery internal representation)?"
  .}

func setZero*(a: var FF) =
  ## Set ``a`` to zero
  a.mres.setZero()

func setOne*(a: var FF) =
  ## Set ``a`` to one
  # Note: we need 1 in Montgomery residue form
  # TODO: Nim codegen is not optimal it uses a temporary
  #       Check if the compiler optimizes it away
  when FF.isCrandallPrimeField():
    a.mres.setOne()
  else:
    a.mres = FF.getMontyOne()

func setMinusOne*(a: var FF) =
  ## Set ``a`` to -1 (mod p)
  # Note: we need -1 in Montgomery residue form
  # TODO: Nim codegen is not optimal it uses a temporary
  #       Check if the compiler optimizes it away
  when FF.isCrandallPrimeField():
    {.error: "Not implemented".}
  else:
    a.mres = FF.getMontyPrimeMinus1()

func neg*(r: var FF, a: FF) {.meter.} =
  ## Negate modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    negmod_asm(r.mres.limbs, a.mres.limbs, FF.getModulus().limbs)
  else:
    # If a = 0 we need r = 0 and not r = M
    # as comparison operator assume unicity
    # of the modular representation.
    # Also make sure to handle aliasing where r.addr = a.addr
    var t {.noInit.}: FF
    let isZero = a.isZero()
    discard t.mres.diff(FF.getModulus(), a.mres)
    t.mres.csetZero(isZero)
    r = t

func neg*(a: var FF) {.meter.} =
  ## Negate modulo p
  a.neg(a)

func `+=`*(a: var FF, b: FF) {.meter.} =
  ## In-place addition modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    addmod_asm(a.mres.limbs, a.mres.limbs, b.mres.limbs, FF.getModulus().limbs, FF.getSpareBits())
  else:
    var overflowed = add(a.mres, b.mres)
    overflowed = overflowed or not(a.mres < FF.getModulus())
    discard csub(a.mres, FF.getModulus(), overflowed)

func `-=`*(a: var FF, b: FF) {.meter.} =
  ## In-place substraction modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    submod_asm(a.mres.limbs, a.mres.limbs, b.mres.limbs, FF.getModulus().limbs)
  else:
    let underflowed = sub(a.mres, b.mres)
    discard cadd(a.mres, FF.getModulus(), underflowed)

func double*(a: var FF) {.meter.} =
  ## Double ``a`` modulo p
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    addmod_asm(a.mres.limbs, a.mres.limbs, a.mres.limbs, FF.getModulus().limbs, FF.getSpareBits())
  else:
    var overflowed = double(a.mres)
    overflowed = overflowed or not(a.mres < FF.getModulus())
    discard csub(a.mres, FF.getModulus(), overflowed)

func sum*(r: var FF, a, b: FF) {.meter.} =
  ## Sum ``a`` and ``b`` into ``r`` modulo p
  ## r is initialized/overwritten
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    addmod_asm(r.mres.limbs, a.mres.limbs, b.mres.limbs, FF.getModulus().limbs, FF.getSpareBits())
  else:
    var overflowed = r.mres.sum(a.mres, b.mres)
    overflowed = overflowed or not(r.mres < FF.getModulus())
    discard csub(r.mres, FF.getModulus(), overflowed)

func sumUnr*(r: var FF, a, b: FF) {.meter.} =
  ## Sum ``a`` and ``b`` into ``r`` without reduction
  discard r.mres.sum(a.mres, b.mres)

func diff*(r: var FF, a, b: FF) {.meter.} =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  ## Requires r != b
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    submod_asm(r.mres.limbs, a.mres.limbs, b.mres.limbs, FF.getModulus().limbs)
  else:
    var underflowed = r.mres.diff(a.mres, b.mres)
    discard cadd(r.mres, FF.getModulus(), underflowed)

func diffUnr*(r: var FF, a, b: FF) {.meter.} =
  ## Substract `b` from `a` and store the result into `r`
  ## without reduction
  discard r.mres.diff(a.mres, b.mres)

func double*(r: var FF, a: FF) {.meter.} =
  ## Double ``a`` into ``r``
  ## `r` is initialized/overwritten
  when UseASM_X86_64 and a.mres.limbs.len <= 6: # TODO: handle spilling
    addmod_asm(r.mres.limbs, a.mres.limbs, a.mres.limbs, FF.getModulus().limbs, FF.getSpareBits())
  else:
    var overflowed = r.mres.double(a.mres)
    overflowed = overflowed or not(r.mres < FF.getModulus())
    discard csub(r.mres, FF.getModulus(), overflowed)

func prod*(r: var FF, a, b: FF, skipFinalSub: static bool = false) {.meter.} =
  ## Store the product of ``a`` by ``b`` modulo p into ``r``
  ## ``r`` is initialized / overwritten
  when FF.isCrandallPrimeField():
    var r2 {.noInit.}: FF.Name.getLimbs2x()
    r2.prod(a.mres.limbs, b.mres.limbs)
    r.mres.limbs.reduce_crandall_partial(r2, FF.bits(), FF.getCrandallPrimeSubterm())
    when not skipFinalSub:
      r.mres.limbs.reduce_crandall_final(FF.bits(), FF.getCrandallPrimeSubterm())
  else:
    r.mres.mulMont(a.mres, b.mres, FF.getModulus(), FF.getNegInvModWord(), FF.getSpareBits(), skipFinalSub)

func square*(r: var FF, a: FF, skipFinalSub: static bool = false) {.meter.} =
  ## Squaring modulo p
  when FF.isCrandallPrimeField():
    var r2 {.noInit.}: FF.Name.getLimbs2x()
    r2.square(a.mres.limbs)
    r.mres.limbs.reduce_crandall_partial(r2, FF.bits(), FF.getCrandallPrimeSubterm())
    when not skipFinalSub:
      r.mres.limbs.reduce_crandall_final(FF.bits(), FF.getCrandallPrimeSubterm())
  else:
    r.mres.squareMont(a.mres, FF.getModulus(), FF.getNegInvModWord(), FF.getSpareBits(), skipFinalSub)

func sumprod*[N: static int](r: var FF, a, b: array[N, FF], skipFinalSub: static bool = false) {.meter.} =
  ## Compute r <- ⅀aᵢ.bᵢ (mod M) (sum of products)
  # We rely on FF and Bigints having the same repr to avoid array copies
  when FF.isCrandallPrimeField():
    {.error: "Not implemented".}
  else:
    r.mres.sumprodMont(
      cast[ptr array[N, typeof(a[0].mres)]](a.unsafeAddr)[],
      cast[ptr array[N, typeof(b[0].mres)]](b.unsafeAddr)[],
      FF.getModulus(), FF.getNegInvModWord(), FF.getSpareBits(), skipFinalSub)

# ############################################################
#
#                Field arithmetic conditional
#
# ############################################################

func csetZero*(a: var FF, ctl: SecretBool) =
  ## Set ``a`` to 0 if ``ctl`` is true
  a.mres.csetZero(ctl)

func csetOne*(a: var FF, ctl: SecretBool) =
  ## Set ``a`` to 1 if ``ctl`` is true
  a.mres.ccopy(FF.getMontyOne(), ctl)

func cneg*(r: var FF, a: FF, ctl: SecretBool) {.meter.} =
  ## Constant-time out-of-place conditional negation
  ## The negation is only performed if ctl is "true"
  r.neg(a)
  r.ccopy(a, not ctl)

func cneg*(a: var FF, ctl: SecretBool) {.meter.} =
  ## Constant-time in-place conditional negation
  ## The negation is only performed if ctl is "true"
  var t {.noInit.} = a
  a.cneg(t, ctl)

func cadd*(a: var FF, b: FF, ctl: SecretBool) {.meter.} =
  ## Constant-time out-place conditional addition
  ## The addition is only performed if ctl is "true"
  var t {.noInit.} = a
  t += b
  a.ccopy(t, ctl)

func csub*(a: var FF, b: FF, ctl: SecretBool) {.meter.} =
  ## Constant-time out-place conditional substraction
  ## The substraction is only performed if ctl is "true"
  var t {.noInit.} = a
  t -= b
  a.ccopy(t, ctl)

# ############################################################
#
#           Field arithmetic division and inversion
#
# ############################################################

func div2*(a: var FF) {.meter.} =
  ## Modular division by 2
  ## `a` will be divided in-place
  #
  # Normally if `a` is odd we add the modulus before dividing by 2
  # but this may overflow and we might lose a bit before shifting.
  # Instead we shift first and then add half the modulus rounded up
  #
  # Assuming M is odd, `mp1div2` can be precomputed without
  # overflowing the "Limbs" by dividing by 2 first
  # and add 1
  # Otherwise `mp1div2` should be M/2

  # if a.isOdd:
  #   a += M
  # a = a shr 1
  let wasOdd = a.mres.isOdd()
  a.mres.shiftRight(1)
  let carry {.used.} = a.mres.cadd(FF.getPrimePlus1div2(), wasOdd)

  # a < M -> a/2 <= M/2:
  #   a/2 + M/2 < M if a is odd
  #   a/2       < M if a is even
  debug: doAssert not carry.bool

func inv*(r: var FF, a: FF) =
  ## Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  when FF.isCrandallPrimeField():
    r.mres.invmod(a.mres, FF.getModulus())
  else:
    r.mres.invmod(a.mres, FF.getR2modP(), FF.getModulus())

func inv*(a: var FF) =
  ## Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.inv(a)

func inv_vartime*(r: var FF, a: FF) {.tags: [VarTime].} =
  ## Variable-time Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  when FF.isCrandallPrimeField():
    r.mres.invmod_vartime(a.mres, FF.getModulus())
  else:
    r.mres.invmod_vartime(a.mres, FF.getR2modP(), FF.getModulus())

func inv_vartime*(a: var FF) {.tags: [VarTime].} =
  ## Variable-time Inversion modulo p
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  a.inv_vartime(a)

# ############################################################
#
#            Field arithmetic ergonomic primitives
#
# ############################################################
#
# This implements extra primitives for ergonomics.

func `*=`*(a: var FF, b: FF) {.meter.} =
  ## Multiplication modulo p
  a.prod(a, b)

func square*(a: var FF, skipFinalSub: static bool = false) {.meter.} =
  ## Squaring modulo p
  a.square(a, skipFinalSub)

func square_repeated*(a: var FF, num: int, skipFinalSub: static bool = false) {.meter.} =
  ## Repeated squarings
  ## Assumes at least 1 squaring
  for _ in 0 ..< num-1:
    a.square(skipFinalSub = true)
  a.square(skipFinalSub)

func square_repeated*(r: var FF, a: FF, num: int, skipFinalSub: static bool = false) {.meter.} =
  ## Repeated squarings
  r.square(a, skipFinalSub = true)
  for _ in 1 ..< num-1:
    r.square(skipFinalSub = true)
  r.square(skipFinalSub)

func `*=`*(a: var FF, b: static int) =
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
    var t {.noInit.}: typeof(a)
    t.double(a)
    a += t
  elif b == 4:
    a.double()
    a.double()
  elif b == 5:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t.double()
    a += t
  elif b == 6:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t += a # 3
    a.double(t)
  elif b == 7:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t.double()
    t.double()
    a.diff(t, a)
  elif b == 8:
    a.double()
    a.double()
    a.double()
  elif b == 9:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t.double()
    t.double()
    a.sum(t, a)
  elif b == 10:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t.double()
    a += t     # 5
    a.double()
  elif b == 11:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t += a       # 3
    t.double()   # 6
    t.double()   # 12
    a.diff(t, a) # 11
  elif b == 12:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t += a       # 3
    t.double()   # 6
    a.double(t)   # 12
  elif b == 15:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t += a       # 3
    a.double(t)  # 6
    a.double()   # 12
    a += t       # 15
  elif b == 21:
    var t {.noInit.}: typeof(a)
    t.double(a)
    t.double()   # 4
    t += a       # 5
    t.double()   # 10
    t.double()   # 20
    a += t       # 21

  else:
    {.error: "Multiplication by this small int not implemented".}

func prod*(r: var FF, a: FF, b: static int) =
  ## Multiplication by a small integer known at compile-time
  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    r.neg(a)
  else:
    r = a
  r *= b

template mulCheckSparse*(a: var Fp, b: Fp) =
  ## Multiplication with optimization for sparse inputs
  when isOne(b).bool:
    discard
  elif isZero(b).bool:
    a.setZero()
  elif isMinusOne(b).bool:
    a.neg()
  else:
    a *= b

# ############################################################
#
#               Field arithmetic exponentiation
#
# ############################################################
#
# Internally those procedures will allocate extra scratchspace on the stack

func pow*(a: var FF, exponent: BigInt) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer
  when FF.isCrandallPrimeField():
    {.error: "Not implemented".}
  else:
    const windowSize = 5 # TODO: find best window size for each curves
    a.mres.powMont(
      exponent,
      FF.getModulus(), FF.getMontyOne(),
      FF.getNegInvModWord(), windowSize,
      FF.getSpareBits()
    )

func pow*(a: var FF, exponent: openarray[byte]) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a big integer in canonical big endian representation
  when FF.isCrandallPrimeField():
    {.error: "Not implemented".}
  else:
    const windowSize = 5 # TODO: find best window size for each curves
    a.mres.powMont(
      exponent,
      FF.getModulus(), FF.getMontyOne(),
      FF.getNegInvModWord(), windowSize,
      FF.getSpareBits()
    )

func pow*(a: var FF, exponent: FF) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a finite field element
  const windowSize = 5 # TODO: find best window size for each curves
  a.pow(exponent.toBig())

func pow*(r: var FF, a: FF, exponent: BigInt or openArray[byte] or FF) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a finite field element or big integer
  r = a
  a.pow(exponent)

# Vartime exponentiation
# -------------------------------------------------------------------

func pow_vartime*(a: var FF, exponent: BigInt) =
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

  when FF.isCrandallPrimeField():
    {.error: "Not implemented".}
  else:
    const windowSize = 5 # TODO: find best window size for each curves
    a.mres.powMont_vartime(
      exponent,
      FF.getModulus(), FF.getMontyOne(),
      FF.getNegInvModWord(), windowSize,
      FF.getSpareBits()
    )

func pow_vartime*(a: var FF, exponent: openarray[byte]) =
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

  when FF.isCrandallPrimeField():
    {.error: "Not implemented".}
  else:
    const windowSize = 5 # TODO: find best window size for each curves
    a.mres.powMont_vartime(
      exponent,
      FF.getModulus(), FF.getMontyOne(),
      FF.getNegInvModWord(), windowSize,
      FF.getSpareBits()
    )

func pow_vartime*(a: var FF, exponent: FF) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a finite field element
  const windowSize = 5 # TODO: find best window size for each curves
  a.pow_vartime(exponent.toBig())

func pow_vartime*(r: var FF, a: FF, exponent: BigInt or openArray[byte] or FF) =
  ## Exponentiation modulo p
  ## ``a``: a field element to be exponentiated
  ## ``exponent``: a finite field element or big integer
  r = a
  a.pow_vartime(exponent)

# Small vartime exponentiation
# -------------------------------------------------------------------

func pow_squareMultiply_vartime(a: var FF, exponent: SomeUnsignedInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation
  ##
  ##   a <- aᵉ (mod p)
  ##
  ## This uses the square-and-multiply algorithm
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.

  if exponent == 0:
    a.setOne()
    return
  if exponent == 1:
    return

  let aa {.noInit.} = a # Original a

  # We use the fact that we can skip the final substraction
  # because montgomery squaring and multiple
  # can accept inputs in [0, 2p) and outputs in [0, 2p).

  let eBytes = exponent.toBytes(bigEndian)
  for e in 0 ..< eBytes.len-1:
    let e = eBytes[e]
    for i in countdown(7, 0):
      a.square(skipFinalSub = true)
      let bit = bool((e shr i) and 1)
      if bit:
        a.prod(a, aa, skipFinalSub = true)

  let e = eBytes[eBytes.len-1]
  block: # Epilogue, byte-level
    for i in countdown(7, 1):
          a.square(skipFinalSub = true)
          let bit = bool((e shr i) and 1)
          if bit:
            a.prod(a, aa, skipFinalSub = true)

  block: # Epilogue, bit-level
    # for the very last bit we can't skip final substraction
    let bit = bool(e and 1)
    if bit:
      a.square(skipFinalSub = true)
      a.prod(a, aa, skipFinalSub = false)
    else:
      a.square(skipFinalSub = false)

func pow_addchain_4bit_vartime(a: var FF, exponent: SomeUnsignedInt) {.tags:[VarTime], meter.} =
  ## **Variable-time** Exponentiation
  ## This can only handle for small scalars up to 2⁴ = 16 included
  case exponent
  of 0:
    a.setOne()
  of 1:
    discard
  of 2:
    a.square()
  of 3:
    var t {.noInit.}: typeof(a)
    t.square(a, skipFinalSub = true)
    a *= t
  of 4:
    a.square_repeated(2)
  of 5:
    var t {.noInit.}: typeof(a)
    t.square_repeated(a, 2, skipFinalSub = true)
    a *= t
  of 6:
    var t {.noInit.}: typeof(a)
    t.square(a, skipFinalSub = true)
    t.prod(t, a, skipFinalSub = true) # 3
    a.square(t)
  of 7:
    var t {.noInit.}: typeof(a)
    t.square(a, skipFinalSub = true)
    a.prod(a, t, skipFinalSub = true) # 3
    t.square(skipFinalSub = true)  # 4
    a *= t
  of 8:
    a.square_repeated(3)
  of 9:
    var t {.noInit.}: typeof(a)
    t.square_repeated(a, 3, skipFinalSub = true)
    a *= t
  of 10:
    var t {.noInit.}: typeof(a)
    t.square_repeated(a, 2, skipFinalSub = true)  # 4
    a.prod(a, t, skipFinalSub = true)             # 5
    a.square()
  of 11:
    var t {.noInit.}: typeof(a)
    t.square_repeated(a, 2, skipFinalSub = true)  # 4
    t.prod(t, a, skipFinalSub = true)             # 5
    t.square(skipFinalSub = true)                 # 10
    a *= t
  of 12:
    var t {.noInit.}: typeof(a)
    t.square(a, skipFinalSub = true)
    t.prod(t, a, skipFinalSub = true)  # 3
    t.square(skipFinalSub = true)      # 6
    a.square(t)                        # 12
  of 13:
    var t1 {.noInit.}, t2 {.noInit.}: typeof(a)
    t1.square_repeated(a, 2, skipFinalSub = true) # 4
    t2.square(t1, skipFinalSub = true)            # 8
    t1.prod(t1, t2, skipFinalSub = true)          # 12
    a *= t1                                       # 13
  of 14:
    var t {.noInit.}: typeof(a)
    t.square(a, skipFinalSub = true)   # 2
    a *= t                             # 3
    t.square_repeated(2, skipFinalSub = true) # 8
    a.square(skipFinalSub = true)      # 6
    a *= t                             # 14
  of 15:
    var t {.noInit.}: typeof(a)
    t.square(a, skipFinalSub = true)
    t.prod(t, a, skipFinalSub = true)            # 3
    a.square_repeated(t, 2, skipFinalSub = true) # 12
    a *= t                                       # 15
  of 16:
    a.square_repeated(4, skipFinalSub = true)
  else:
    doAssert false, "exponentiation by this small int '" & $exponent & "' is not implemented"

func pow_vartime(a: var FF, exponent: SomeUnsignedInt) {.tags:[VarTime], meter.} =
  if exponent <= 16:
    a.pow_addchain_4bit_vartime(exponent)
  else:
    a.pow_squareMultiply_vartime(exponent)

func computeSparsePowers_vartime*[Name](
      dst: ptr UncheckedArray[FF[Name]],
      base: FF[Name],
      sparsePowers: ptr UncheckedArray[SomeUnsignedInt],
      len: int) =
  ## Compute sparse powers of base
  ## sparsePowers MUST be ordered in ascending powers.
  ## Both `dst` and sparsePowers are of length `len`
  if len >= 1:
    dst[0].pow_vartime(sparsePowers[0])
  for i in 1 ..< len:
    dst[i] = dst[i-1]
    dst[i].pow_vartime(sparsePowers[i]-sparsePowers[i-1])

func computePowers*[Name](dst: ptr UncheckedArray[FF[Name]], base: FF[Name], len: int) =
  ## We need linearly independent random numbers
  ## for batch proof sampling.
  ## Powers are linearly independent.
  ## It's also likely faster than calling a fast RNG + modular reduction
  ## to be in 0 < number < curve_order
  ## since modular reduction needs modular multiplication or a division anyway.
  let N = len
  if N >= 1:
    dst[0].setOne()
  if N >= 2:
    dst[1] = base
  for i in 2 ..< N:
    dst[i].prod(dst[i-1], base)

# ############################################################
#
#            Field arithmetic ergonomic macros
#
# ############################################################

import std/macros

macro addchain*(fn: untyped): untyped =
  ## Modify all prod, `*=`, square, square_repeated calls
  ## to skipFinalSub except the very last call.
  ## This assumes straight-line code.
  fn.expectKind(nnkFuncDef)

  result = fn
  var body = newStmtList()

  for i, statement in fn[^1]:
    statement.expectKind({nnkCommentStmt, nnkLetSection, nnkVarSection, nnkCall, nnkInfix})

    var s = statement.copyNimTree()
    if i + 1 != result[^1].len:
      # Modify all but the last
      if s.kind == nnkCall:
        doAssert s[0].kind == nnkDotExpr, "Only method call syntax or infix syntax is supported in addition chains"
        doAssert s[0][1].eqIdent"prod" or s[0][1].eqIdent"square" or s[0][1].eqIdent"square_repeated"
        s.add newLit(true)
      elif s.kind == nnkInfix:
        doAssert s[0].eqIdent"*="
        # a *= b   ->  prod(a, a, b, true)
        s = newCall(
          bindSym"prod",
          s[1],
          s[1],
          s[2],
          newLit(true)
        )

    body.add s

  result[^1] = body

# ############################################################
#
#                   Batch operations
#
# ############################################################

func batchFromField*[N, Name](
      dst: ptr UncheckedArray[BigInt[N]],
      src: ptr UncheckedArray[FF[Name]],
      len: int) {.inline.} =
  for i in 0 ..< len:
    dst[i].fromField(src[i])

func batchInv*[F](
        dst: ptr UncheckedArray[F],
        elements: ptr UncheckedArray[F],
        N: int) {.noInline.} =
  ## Batch inversion
  ## If an element is 0, the inverse stored will be 0.
  var zeros = allocStackArray(SecretBool, N)
  zeroMem(zeros, N)

  var acc: F
  acc.setOne()

  for i in 0 ..< N:
    # Skip zeros
    zeros[i] = elements[i].isZero()
    var z = elements[i]
    z.csetOne(zeros[i])

    dst[i] = acc
    if i != N-1:
      acc.prod(acc, z, skipFinalSub = true)
    else:
      acc.prod(acc, z, skipFinalSub = false)

  acc.inv()

  for i in countdown(N-1, 0):
    # Extract 1/elemᵢ
    dst[i] *= acc
    dst[i].csetZero(zeros[i])

    # next iteration
    var eli = elements[i]
    eli.csetOne(zeros[i])
    acc.prod(acc, eli, skipFinalSub = true)

func batchInv_vartime*[F](
        dst: ptr UncheckedArray[F],
        elements: ptr UncheckedArray[F],
        N: int) {.noInline.} =
  ## Batch inversion
  ## If an element is 0, the inverse stored will be 0.

  if N == 0:
    return
  if N == 1:
    dst[0].inv_vartime(elements[0])
    return

  var zeros = allocStackArray(bool, N)
  zeroMem(zeros, N)

  var acc: F
  acc.setOne()

  for i in 0 ..< N:
    if elements[i].isZero().bool():
      zeros[i] = true
      dst[i].setZero()
      continue

    dst[i] = acc
    if i != N-1:
      acc.prod(acc, elements[i], skipFinalSub = true)
    else:
      acc.prod(acc, elements[i], skipFinalSub = false)

  acc.inv_vartime()

  for i in countdown(N-1, 0):
    if zeros[i] == true:
      continue
    dst[i] *= acc
    acc.prod(acc, elements[i], skipFinalSub = true)

func batchInv*[F](dst: var openArray[F], source: openArray[F]) {.inline.} =
  debug: doAssert dst.len == source.len
  batchInv(dst.asUnchecked(), source.asUnchecked(), dst.len)

func batchInv*[N: static int, F](dst: var array[N, F], src: array[N, F]) =
  batchInv(dst.asUnchecked(), src.asUnchecked(), N)

func batchInv_vartime*[F](dst: var openArray[F], source: openArray[F]) {.inline.} =
  debug: doAssert dst.len == source.len
  batchInv_vartime(dst.asUnchecked(), source.asUnchecked(), dst.len)

func batchInv_vartime*[N: static int, F](dst: var array[N, F], src: array[N, F]) =
  batchInv_vartime(dst.asUnchecked(), src.asUnchecked(), N)

# ############################################################
#
#                 Out-of-Place functions
#
# ############################################################
#
# Except from the constant function getZero, getOne, getMinusOne
# out-of-place functions are intended for rapid prototyping, debugging and testing.
#
# They SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145

func getZero*(T: type FF): T {.inline.} =
  discard

func getOne*(T: type FF): T {.noInit, inline.} =
  cast[ptr T](T.getMontyOne().unsafeAddr)[]

func getMinusOne*(T: type FF): T {.noInit, inline.} =
  cast[ptr T](T.getMontyPrimeMinus1().unsafeAddr)[]

func `+`*(a, b: FF): FF {.noInit, inline.} =
  ## Finite Field addition
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.sum(a, b)

func `-`*(a, b: FF): FF {.noInit, inline.} =
  ## Finite Field substraction
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.diff(a, b)

func `*`*(a, b: FF): FF {.noInit, inline.} =
  ## Finite Field multiplication
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.prod(a, b)

func `^`*(a: FF, b: FF or BigInt or openArray[byte]): FF {.noInit, inline.} =
  ## Finite Field exponentiation
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.pow(a, b)

func `~^`*(a: FF, b: FF or BigInt or openArray[byte]): FF {.noInit, inline.} =
  ## Finite Field vartime exponentiation
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.pow_vartime(a, b)
