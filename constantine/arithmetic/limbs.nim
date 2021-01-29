# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../primitives

when UseASM_X86_32:
  import ./assembly/limbs_asm_x86
when UseASM_X86_64:
  import ./assembly/limbs_asm_mul_x86
  import ./assembly/limbs_asm_mul_x86_adx_bmi2

# ############################################################
#
#         Limbs raw representation and operations
#
# ############################################################
#
# This file holds the raw operations done on big ints
# The representation is optimized for:
# - constant-time (not leaking secret data via side-channel)
# - performance
# - generated code size, datatype size and stack usage
# in this order
#
# The "limbs" API limits code duplication
# due to generic/static monomorphization for bit-width
# that are represented with the same number of words.
#
# It also exposes at the number of words to the compiler
# to allow aggressive unrolling and inlining for example
# of multi-precision addition which is so small (2 instructions per word)
# that inlining it improves both performance and code-size
# even for 2 curves (secp256k1 and BN254) that could share the code.
#
# The limb-endianess is little-endian, less significant limb is at index 0.
# The word-endianness is native-endian.

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                   Limbs Primitives
#
# ############################################################

{.push inline.}
# The following primitives are small enough on regular limb sizes
# (BN254 and secp256k1 -> 4 limbs, BLS12-381 -> 6 limbs)
# that inline both decreases the code size and increases speed
# as we avoid the parmeter packing/unpacking ceremony at function entry/exit
# and unrolling overhead is minimal.

# Initialization
# ------------------------------------------------------------

func setZero*(a: var Limbs) =
  ## Set ``a`` to 0
  zeroMem(a[0].addr, sizeof(a))

func setOne*(a: var Limbs) =
  ## Set ``a`` to 1
  a[0] = One
  when a.len > 1:
    zeroMem(a[1].addr, (a.len - 1) * sizeof(SecretWord))

func setUint*(a: var Limbs, n: SomeUnsignedInt) =
  ## set ``a`` to an unsigned integer ``n``
  when sizeof(SecretWord) >= sizeof(n):
    a[0] = SecretWord(n)
    when a.len > 1:
      zeroMem(a[1].addr, (a.len - 1) * sizeof(SecretWord))
  else:
    static: doAssert a.len >= 2,
      "Overflow, trying to store a " & $(sizeof(n)*8) & " integer " &
      "in ", a.len, " limb of size ", sizeof(SecretWord), "."

    a[0] = SecretWord(n) # Truncate the upper part
    a[1] = SecretWord(n shr log2(sizeof(SecretWord)))
    when a.len > 2:
      zeroMem(a[2].addr, (a.len - 2) * sizeof(SecretWord))

func czero*(a: var Limbs, ctl: SecretBool) =
  ## Set ``a`` to 0 if ``ctl`` is true
  # Only used for FF neg in pure Nim fallback
  # so no need for assembly
  for i in 0 ..< a.len:
    ctl.ccopy(a[i], Zero)

# Copy
# ------------------------------------------------------------

func ccopy*(a: var Limbs, b: Limbs, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  when UseASM_X86_32:
    ccopy_asm(a, b, ctl)
  else:
    for i in 0 ..< a.len:
      ctl.ccopy(a[i], b[i])

func cswap*(a, b: var Limbs, ctl: CTBool) =
  ## Swap ``a`` and ``b`` if ``ctl`` is true
  ##
  ## Constant-time:
  ## Whether ``ctl`` is true or not, the same
  ## memory accesses are done (unless the compiler tries to be clever)

  var mask = -(SecretWord ctl)
  for i in 0 ..< a.len:
    let t = mask and (a[i] xor b[i])
    a[i] = a[i] xor t
    b[i] = b[i] xor t

# Comparison
# ------------------------------------------------------------

func `==`*(a, b: Limbs): SecretBool =
  ## Returns true if 2 limbs are equal
  ## Comparison is constant-time
  var accum = Zero
  for i in 0 ..< a.len:
    accum = accum or (a[i] xor b[i])
  result = accum.isZero()

func `<`*(a, b: Limbs): SecretBool =
  ## Returns true if a < b
  ## Comparison is constant-time
  var diff: SecretWord
  var borrow: Borrow
  for i in 0 ..< a.len:
    subB(borrow, diff, a[i], b[i], borrow)

  result = (SecretBool)(borrow)

func `<=`*(a, b: Limbs): SecretBool =
  ## Returns true if a <= b
  ## Comparison is constant-time
  not(b < a)

func isZero*(a: Limbs): SecretBool =
  ## Returns true if ``a`` is equal to zero
  var accum = Zero
  for i in 0 ..< a.len:
    accum = accum or a[i]
  result = accum.isZero()

func eq*(a: Limbs, n: SecretWord): SecretBool =
  ## Returns true if ``a`` is equal
  ## to the specified small word
  result = a[0] == n
  for i in 1 ..< a.len:
    result = result and a[i].isZero()

func isOne*(a: Limbs): SecretBool =
  ## Returns true if ``a`` is equal to one
  a.eq(One)

func isOdd*(a: Limbs): SecretBool =
  ## Returns true if a is odd
  SecretBool(a[0] and One)

func isEven*(a: Limbs): SecretBool =
  ## Returns true if a is even
  not SecretBool(a[0] and One)

# Bit manipulation
# ------------------------------------------------------------

func shiftRight*(a: var Limbs, k: int) {.inline.}=
  ## Shift right by k.
  ##
  ## k MUST be less than the base word size (2^32 or 2^64)
  # We don't reuse shr as this is an in-place operation
  # Do we need to return the shifted out part?
  #
  # Note: for speed, loading a[i] and a[i+1]
  #       instead of a[i-1] and a[i]
  #       is probably easier to parallelize for the compiler
  #       (antidependence WAR vs loop-carried dependence RAW)

  # checkWordShift(k)

  for i in 0 ..< a.len-1:
    a[i] = (a[i] shr k) or (a[i+1] shl (WordBitWidth - k))
  a[a.len-1] = a[a.len-1] shr k

# Basic Arithmetic
# ------------------------------------------------------------

func add*(a: var Limbs, b: Limbs): Carry =
  ## Limbs addition
  ## Returns the carry
  when UseASM_X86_32:
    result = add_asm(a, a, b)
  else:
    result = Carry(0)
    for i in 0 ..< a.len:
      addC(result, a[i], a[i], b[i], result)

func add*(a: var Limbs, w: SecretWord): Carry =
  ## Limbs addition, add a number that fits in a word
  ## Returns the carry
  result = Carry(0)
  addC(result, a[0], a[0], w, result)
  for i in 1 ..< a.len:
    addC(result, a[i], a[i], Zero, result)

func sum*(r: var Limbs, a, b: Limbs): Carry =
  ## Sum `a` and `b` into `r`
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  when UseASM_X86_32:
    result = add_asm(r, a, b)
  else:
    result = Carry(0)
    for i in 0 ..< a.len:
      addC(result, r[i], a[i], b[i], result)

func sub*(a: var Limbs, b: Limbs): Borrow =
  ## Limbs substraction
  ## Returns the borrow
  when UseASM_X86_32:
    result = sub_asm(a, a, b)
  else:
    result = Borrow(0)
    for i in 0 ..< a.len:
      subB(result, a[i], a[i], b[i], result)

func sub*(a: var Limbs, w: SecretWord): Borrow =
  ## Limbs substraction, sub a number that fits in a word
  ## Returns the borrow
  result = Borrow(0)
  subB(result, a[0], a[0], w, result)
  for i in 1 ..< a.len:
    subB(result, a[i], a[i], Zero, result)

func diff*(r: var Limbs, a, b: Limbs): Borrow =
  ## Diff `a` and `b` into `r`
  ## `r` is initialized/overwritten
  ##
  ## Returns the borrow
  when UseASM_X86_32:
    result = sub_asm(r, a, b)
  else:
    result = Borrow(0)
    for i in 0 ..< a.len:
      subB(result, r[i], a[i], b[i], result)

# Conditional arithmetic
# ------------------------------------------------------------

func cadd*(a: var Limbs, b: Limbs, ctl: SecretBool): Carry =
  ## Limbs conditional addition
  ## Returns the carry
  ##
  ## if ctl is true: a <- a + b
  ## if ctl is false: a <- a
  ## The carry is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Carry(0)
  var sum: SecretWord
  for i in 0 ..< a.len:
    addC(result, sum, a[i], b[i], result)
    ctl.ccopy(a[i], sum)

func cadd*(a: var Limbs, w: SecretWord, ctl: SecretBool): Borrow =
  ## Limbs conditional addition, sub a number that fits in a word
  ## Returns the borrow
  result = Carry(0)
  var diff: SecretWord
  addC(result, diff, a[0], w, result)
  ctl.ccopy(a[0], diff)
  for i in 1 ..< a.len:
    addC(result, diff, a[i], Zero, result)
    ctl.ccopy(a[i], diff)

func csub*(a: var Limbs, b: Limbs, ctl: SecretBool): Borrow =
  ## Limbs conditional substraction
  ## Returns the borrow
  ##
  ## if ctl is true: a <- a - b
  ## if ctl is false: a <- a
  ## The borrow is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Borrow(0)
  var diff: SecretWord
  for i in 0 ..< a.len:
    subB(result, diff, a[i], b[i], result)
    ctl.ccopy(a[i], diff)

func csub*(a: var Limbs, w: SecretWord, ctl: SecretBool): Borrow =
  ## Limbs conditional substraction, sub a number that fits in a word
  ## Returns the borrow
  result = Borrow(0)
  var diff: SecretWord
  subB(result, diff, a[0], w, result)
  ctl.ccopy(a[0], diff)
  for i in 1 ..< a.len:
    subB(result, diff, a[i], Zero, result)
    ctl.ccopy(a[i], diff)

func cneg*(a: var Limbs, ctl: CTBool) =
  ## Conditional negation.
  ## Negate if ``ctl`` is true

  # Algorithm:
  # In two-complement representation
  #  -x <=> not(x) + 1 <=> x xor 0xFF... + 1
  # and
  #   x <=> x xor 0x00...<=> x xor 0x00... + 0
  #
  # So we need to xor all words and then add 1
  # The "+1" might carry
  # So we fuse the 2 steps
  let mask = -SecretWord(ctl)        # Obtain a 0xFF... or 0x00... mask
  var carry = SecretWord(ctl)
  for i in 0 ..< a.len:
    let t = (a[i] xor mask) + carry  # XOR with mask and add 0x01 or 0x00 respectively
    carry = SecretWord(t < carry)    # Carry on
    a[i] = t

{.pop.} # inline

# Multiplication
# ------------------------------------------------------------

func prod*[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision multiplication
  ## r <- a*b
  ##
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitwidth)^r.limbs.len)
  ##
  ## `r` must not alias ``a`` or ``b``

  when UseASM_X86_64 and aLen <= 6:
    if ({.noSideEffect.}: hasBmi2()) and ({.noSideEffect.}: hasAdx()):
      mul_asm_adx_bmi2(r, a, b)
    else:
      mul_asm(r, a, b)
  elif UseASM_X86_64:
    mul_asm(r, a, b)
  else:
    # We use Product Scanning / Comba multiplication
    var t, u, v = Zero

    staticFor i, 0, min(a.len+b.len, r.len):
      const ib = min(b.len-1, i)
      const ia = i - ib
      staticFor j, 0, min(a.len - ia, ib+1):
        mulAcc(t, u, v, a[ia+j], b[ib-j])

      r[i] = v
      v = u
      u = t
      t = Zero

    if aLen+bLen < rLen:
      for i in aLen+bLen ..< rLen:
        r[i] = Zero

func prod_high_words*[rLen, aLen, bLen](
       r: var Limbs[rLen],
       a: Limbs[aLen], b: Limbs[bLen],
       lowestWordIndex: static int) =
  ## Multi-precision multiplication keeping only high words
  ## r <- a*b >> (2^WordBitWidth)^lowestWordIndex
  ##
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len - lowestWordIndex
  ## The result will be truncated, i.e. it will be
  ## a * b >> (2^WordBitWidth)^lowestWordIndex (mod (2^WordBitwidth)^r.limbs.len)
  #
  # This is useful for
  # - Barret reduction
  # - Approximating multiplication by a fractional constant in the form f(a) = K/C * a
  #   with K and C known at compile-time.
  #   We can instead find a well chosen M = (2^WordBitWidth)^w, with M > C (i.e. M is a power of 2 bigger than C)
  #   Precompute P = K*M/C at compile-time
  #   and at runtime do P*a/M <=> P*a >> (WordBitWidth*w)
  #   i.e. prod_high_words(result, P, a, w)

  # We use Product Scanning / Comba multiplication
  var t, u, v = Zero # Will raise warning on empty iterations
  var z: Limbs[rLen] # zero-init, ensure on stack and removes in-place problems

  # The previous 2 columns can affect the lowest word due to carries
  # but not the ones before (we accumulate in 3 words (t, u, v))
  const w = lowestWordIndex - 2

  staticFor i, max(0, w), min(a.len+b.len, r.len+lowestWordIndex):
    const ib = min(b.len-1, i)
    const ia = i - ib
    staticFor j, 0, min(a.len - ia, ib+1):
      mulAcc(t, u, v, a[ia+j], b[ib-j])

    when i >= lowestWordIndex:
      z[i-lowestWordIndex] = v
    v = u
    u = t
    t = Zero

  r = z

# Division
# ------------------------------------------------------------

func div10*(a: var Limbs): SecretWord =
  ## Divide `a` by 10 in-place and return the remainder
  ## TODO constant-time
  result = Zero

  let clz = WordBitWidth - 1 - log2(10)
  let norm10 = SecretWord(10) shl clz

  for i in countdown(a.len-1, 0):
    # dividend = 2^64 * remainder + a[i]
    var hi = result
    var lo = a[i]
    # Normalize
    hi = (hi shl clz) or (lo shr (WordBitWidth - clz))
    lo = lo shl clz
    unsafeDiv2n1n(a[i], result, hi, lo, norm10)
    # Undo normalization
    result = result shr clz

{.pop.} # raises no exceptions
