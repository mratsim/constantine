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

type Limbs*[N: static int] = array[N, Word]
  ## Limbs-type
  ## Should be distinct type to avoid builtins to use non-constant time
  ## implementation, for example for comparison.
  ##
  ## but for unknown reason, it prevents semchecking `bits`

debug:
  import strutils

  func toString*(a: Limbs): string =
    result = "["
    result.add $BaseType(a[0]) & " (0x" & toHex(BaseType(a[0])) & ')'
    for i in 1 ..< a.len:
      result.add ", "
      result.add $BaseType(a[i]) & " (0x" & toHex(BaseType(a[i])) & ')'
    result.add "])"

  func toHex*(a: Limbs): string =
    result = "0x"
    for i in countdown(a.len-1, 0):
      result.add toHex(BaseType(a[i]))

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                      Accessors
#
# ############################################################
#
# Commented out since we don't use a distinct type

# template `[]`[N](v: Limbs[N], idx: int): Word =
#   (array[N, Word])(v)[idx]
#
# template `[]`[N](v: var Limbs[N], idx: int): var Word =
#   (array[N, Word])(v)[idx]
#
# template `[]=`[N](v: Limbs[N], idx: int, val: Word) =
#   (array[N, Word])(v)[idx] = val

# ############################################################
#
#           Checks and debug/test only primitives
#
# ############################################################

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
  a[0] = Word(1)
  when a.len > 1:
    zeroMem(a[1].addr, (a.len - 1) * sizeof(Word))

# Copy
# ------------------------------------------------------------

func ccopy*(a: var Limbs, b: Limbs, ctl: CTBool[Word]) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  # TODO: on x86, we use inline assembly for CMOV
  #       the codegen is a bit inefficient as the condition `ctl`
  #       is tested for each limb.
  for i in 0 ..< a.len:
    ctl.ccopy(a[i], b[i])

func cswap*(a, b: var Limbs, ctl: CTBool) =
  ## Swap ``a`` and ``b`` if ``ctl`` is true
  ##
  ## Constant-time:
  ## Whether ``ctl`` is true or not, the same
  ## memory accesses are done (unless the compiler tries to be clever)

  var mask = -(Word ctl)
  for i in 0 ..< a.len:
    let t = mask and (a[i] xor b[i])
    a[i] = a[i] xor t
    b[i] = b[i] xor t

# Comparison
# ------------------------------------------------------------

func `==`*(a, b: Limbs): CTBool[Word] =
  ## Returns true if 2 limbs are equal
  ## Comparison is constant-time
  var accum = Zero
  for i in 0 ..< a.len:
    accum = accum or (a[i] xor b[i])
  result = accum.isZero()

func `<`*(a, b: Limbs): CTBool[Word] =
  ## Returns true if a < b
  ## Comparison is constant-time
  var diff: Word
  var borrow: Borrow
  for i in 0 ..< a.len:
    subB(borrow, diff, a[i], b[i], borrow)

  result = (CTBool[Word])(borrow)

func `<=`*(a, b: Limbs): CTBool[Word] =
  ## Returns true if a <= b
  ## Comparison is constant-time
  not(b < a)

func isZero*(a: Limbs): CTBool[Word] =
  ## Returns true if ``a`` is equal to zero
  var accum = Zero
  for i in 0 ..< a.len:
    accum = accum or a[i]
  result = accum.isZero()

func isOne*(a: Limbs): CTBool[Word] =
  ## Returns true if ``a`` is equal to one
  result = a[0] == Word(1)
  for i in 1 ..< a.len:
    result = result and a[i].isZero()

func isOdd*(a: Limbs): CTBool[Word] =
  ## Returns true if a is odd
  CTBool[Word](a[0] and Word(1))

# Arithmetic
# ------------------------------------------------------------

func add*(a: var Limbs, b: Limbs): Carry =
  ## Limbs addition
  ## Returns the carry
  result = Carry(0)
  for i in 0 ..< a.len:
    addC(result, a[i], a[i], b[i], result)

func add*(a: var Limbs, w: Word): Carry =
  ## Limbs addition, add a number that fits in a word
  ## Returns the carry
  result = Carry(0)
  addC(result, a[0], a[0], w, result)
  for i in 1 ..< a.len:
    addC(result, a[i], a[i], Zero, result)

func cadd*(a: var Limbs, b: Limbs, ctl: CTBool[Word]): Carry =
  ## Limbs conditional addition
  ## Returns the carry
  ##
  ## if ctl is true: a <- a + b
  ## if ctl is false: a <- a
  ## The carry is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Carry(0)
  var sum: Word
  for i in 0 ..< a.len:
    addC(result, sum, a[i], b[i], result)
    ctl.ccopy(a[i], sum)

func sum*(r: var Limbs, a, b: Limbs): Carry =
  ## Sum `a` and `b` into `r`
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  result = Carry(0)
  for i in 0 ..< a.len:
    addC(result, r[i], a[i], b[i], result)

func sub*(a: var Limbs, b: Limbs): Borrow =
  ## Limbs substraction
  ## Returns the borrow
  result = Borrow(0)
  for i in 0 ..< a.len:
    subB(result, a[i], a[i], b[i], result)

func csub*(a: var Limbs, b: Limbs, ctl: CTBool[Word]): Borrow =
  ## Limbs conditional substraction
  ## Returns the borrow
  ##
  ## if ctl is true: a <- a - b
  ## if ctl is false: a <- a
  ## The borrow is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Borrow(0)
  var diff: Word
  for i in 0 ..< a.len:
    subB(result, diff, a[i], b[i], result)
    ctl.ccopy(a[i], diff)

func diff*(r: var Limbs, a, b: Limbs): Borrow =
  ## Diff `a` and `b` into `r`
  ## `r` is initialized/overwritten
  ##
  ## Returns the borrow
  result = Borrow(0)
  for i in 0 ..< a.len:
    subB(result, r[i], a[i], b[i], result)

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
  let mask = -Word(ctl)              # Obtain a 0xFF... or 0x00... mask
  var carry = Word(ctl)
  for i in 0 ..< a.len:
    let t = (a[i] xor mask) + carry  # XOR with mask and add 0x01 or 0x00 respectively
    carry = Word(t < carry)          # Carry on
    a[i] = t

# Bit manipulation
# ------------------------------------------------------------

func shiftRight*(a: var Limbs, k: int) =
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

{.pop.} # inline
{.pop.} # raises no exceptions
