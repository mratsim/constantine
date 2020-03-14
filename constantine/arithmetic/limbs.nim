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

func `==`*(a, b: Limbs): CTBool[Word] =
  ## Returns true if 2 limbs are equal
  ## Comparison is constant-time
  var accum = Zero
  for i in 0 ..< a.len:
    accum = accum or (a[i] xor b[i])
  result = accum.isZero()

func isZero*(a: Limbs): CTBool[Word] =
  ## Returns true if ``a`` is equal to zero
  var accum = Zero
  for i in 0 ..< a.len:
    accum = accum or a[i]
  result = accum.isZero()

func setZero*(a: var Limbs) =
  ## Set ``a`` to 0
  zeroMem(a[0].addr, sizeof(a))

func setOne*(a: var Limbs) =
  ## Set ``a`` to 1
  a[0] = Word(1)
  when a.len > 1:
    zeroMem(a[1].addr, (a.len - 1) * sizeof(Word))

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

func add*(a: var Limbs, b: Limbs): Carry =
  ## Limbs addition
  ## Returns the carry
  result = Carry(0)
  for i in 0 ..< a.len:
    addC(result, a[i], a[i], b[i], result)

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

{.pop.} # inline

# ############################################################
#
#                   Modular BigInt
#
# ############################################################
#
# To avoid code-size explosion due to monomorphization
# and given that reductions are not in hot path in Constantine
# we use type-erased procedures, instead of instantiating
# one per number of limbs combination

# Type-erasure
# ------------------------------------------------------------

type
  LimbsView = ptr UncheckedArray[Word]
    ## Type-erased fixed-precision limbs
    ##
    ## This type mirrors the Limb type and is used
    ## for some low-level computation API
    ## This design
    ## - avoids code bloat due to generic monomorphization
    ##   otherwise limbs routines would have an instantiation for
    ##   each number of words.
    ##
    ## Accesses should be done via BigIntViewConst / BigIntViewConst
    ## to have the compiler check for mutability

  # "Indirection" to enforce pointer types deep immutability
  LimbsViewConst = distinct LimbsView
    ## Immutable view into the limbs of a BigInt
  LimbsViewMut = distinct LimbsView
    ## Mutable view into a BigInt
  LimbsViewAny = LimbsViewConst or LimbsViewMut

# Deep Mutability safety
# ------------------------------------------------------------

template view(a: Limbs): LimbsViewConst =
  ## Returns a borrowed type-erased immutable view to a bigint
  LimbsViewConst(cast[LimbsView](a.unsafeAddr))

template view(a: var Limbs): LimbsViewMut =
  ## Returns a borrowed type-erased mutable view to a mutable bigint
  LimbsViewMut(cast[LimbsView](a.addr))

template `[]`*(v: LimbsViewConst, limbIdx: int): Word =
  LimbsView(v)[limbIdx]

template `[]`*(v: LimbsViewMut, limbIdx: int): var Word =
  LimbsView(v)[limbIdx]

template `[]=`*(v: LimbsViewMut, limbIdx: int, val: Word) =
  LimbsView(v)[limbIdx] = val

# Type-erased add-sub
# ------------------------------------------------------------

func cadd(a: LimbsViewMut, b: LimbsViewAny, ctl: CTBool[Word], len: int): Carry =
  ## Type-erased conditional addition
  ## Returns the carry
  ##
  ## if ctl is true: a <- a + b
  ## if ctl is false: a <- a
  ## The carry is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Carry(0)
  var sum: Word
  for i in 0 ..< len:
    addC(result, sum, a[i], b[i], result)
    ctl.ccopy(a[i], sum)

func csub(a: LimbsViewMut, b: LimbsViewAny, ctl: CTBool[Word], len: int): Borrow =
  ## Type-erased conditional addition
  ## Returns the borrow
  ##
  ## if ctl is true: a <- a - b
  ## if ctl is false: a <- a
  ## The borrow is always computed whether ctl is true or false
  ##
  ## Time and memory accesses are the same whether a copy occurs or not
  result = Borrow(0)
  var diff: Word
  for i in 0 ..< len:
    subB(result, diff, a[i], b[i], result)
    ctl.ccopy(a[i], diff)

# Modular reduction
# ------------------------------------------------------------

func numWordsFromBits(bits: int): int {.inline.} =
  const divShiftor = log2(uint32(sizeof(Word)))
  result = (bits + sizeof(Word) - 1) shr divShiftor

func shlAddMod_estimate(a: LimbsViewMut, aLen: int,
                        c: Word, M: LimbsViewConst, mBits: int
                      ): tuple[neg, tooBig: CTBool[Word]] =
  ## Estimate a <- a shl 2^w + c (mod M)
  ##
  ## with w the base word width, usually 32 on 32-bit platforms and 64 on 64-bit platforms
  ##
  ## Updates ``a`` and returns ``neg`` and ``tooBig``
  ## If ``neg``, the estimate in ``a`` is negative and ``M`` must be added to it.
  ## If ``tooBig``, the estimate in ``a`` overflowed and ``M`` must be substracted from it.

  # Aliases
  # ----------------------------------------------------------------------
  let MLen = numWordsFromBits(mBits)

  # Captures aLen and MLen
  template `[]`(v: untyped, limbIdxFromEnd: BackwardsIndex): Word {.dirty.}=
    v[`v Len` - limbIdxFromEnd.int]

  # ----------------------------------------------------------------------
                                                          # Assuming 64-bit words
  let hi = a[^1]                                          # Save the high word to detect carries
  let R = mBits and (WordBitWidth - 1)                    # R = mBits mod 64

  var a0, a1, m0: Word
  if R == 0:                                              # If the number of mBits is a multiple of 64
    a0 = a[^1]                                            #
    moveMem(a[1].addr, a[0].addr, (aLen-1) * Word.sizeof) # we can just shift words
    a[0] = c                                              # and replace the first one by c
    a1 = a[^1]
    m0 = M[^1]
  else:                                                   # Else: need to deal with partial word shifts at the edge.
    a0 = (a[^1] shl (WordBitWidth-R)) or (a[^2] shr R)
    moveMem(a[1].addr, a[0].addr, (aLen-1) * Word.sizeof)
    a[0] = c
    a1 = (a[^1] shl (WordBitWidth-R)) or (a[^2] shr R)
    m0 = (M[^1] shl (WordBitWidth-R)) or (M[^2] shr R)

  # m0 has its high bit set. (a0, a1)/p0 fits in a limb.
  # Get a quotient q, at most we will be 2 iterations off
  # from the true quotient

  var q, r: Word
  unsafeDiv2n1n(q, r, a0, a1, m0)                # Estimate quotient
  q = mux(                                       # If n_hi == divisor
        a0 == m0, MaxWord,                       # Quotient == MaxWord (0b1111...1111)
        mux(
          q.isZero, Zero,                        # elif q == 0, true quotient = 0
          q - One                                # else instead of being of by 0, 1 or 2
        )                                        # we returning q-1 to be off by -1, 0 or 1
      )

  # Now substract a*2^64 - q*p
  var carry = Zero
  var over_p = CtTrue                            # Track if quotient greater than the modulus

  for i in 0 ..< MLen:
    var qp_lo: Word

    block: # q*p
      # q * p + carry (doubleword) carry from previous limb
      muladd1(carry, qp_lo, q, M[i], Word carry)

    block: # a*2^64 - q*p
      var borrow: Borrow
      subB(borrow, a[i], a[i], qp_lo, Borrow(0))
      carry += Word(borrow) # Adjust if borrow

    over_p = mux(
              a[i] == M[i], over_p,
              a[i] > M[i]
            )

  # Fix quotient, the true quotient is either q-1, q or q+1
  #
  # if carry < q or carry == q and over_p we must do "a -= p"
  # if carry > hi (negative result) we must do "a += p"

  result.neg = Word(carry) > hi
  result.tooBig = not(result.neg) and (over_p or (Word(carry) < hi))

func shlAddMod(a: LimbsViewMut, aLen: int,
               c: Word, M: LimbsViewConst, mBits: int) =
  ## Fused modular left-shift + add
  ## Shift input `a` by a word and add `c` modulo `M`
  ##
  ## With a word W = 2^WordBitSize and a modulus M
  ## Does a <- a * W + c (mod M)
  ##
  ## The modulus `M` most-significant bit at `mBits` MUST be set.
  if mBits <= WordBitWidth:
    # If M fits in a single limb
    var q: Word
    unsafeDiv2n1n(q, a[0], a[0], c, M[0])  # (hi, lo) mod M
  else:
    ## Multiple limbs
    let (neg, tooBig) = shlAddMod_estimate(a, aLen, c, M, mBits)
    discard a.cadd(M, ctl = neg, aLen)
    discard a.csub(M, ctl = tooBig, aLen)

func reduce(r: LimbsViewMut,
            a: LimbsViewAny, aBits: int,
            M: LimbsViewConst, mBits: int) =
  ## Reduce `a` modulo `M` and store the result in `r`
  let aLen = numWordsFromBits(aBits)
  let mLen = numWordsFromBits(mBits)
  let rLen = mLen

  if aBits < mBits:
    # if a uses less bits than the modulus,
    # it is guaranteed < modulus.
    # This relies on the precondition that the modulus uses all declared bits
    copyMem(r[0].addr, a[0].unsafeAddr, aLen * sizeof(Word))
    for i in aLen ..< mLen:
      r[i] = Zero
  else:
    # a length i at least equal to the modulus.
    # we can copy modulus.limbs-1 words
    # and modular shift-left-add the rest
    let aOffset = aLen - mLen
    copyMem(r[0].addr, a[aOffset+1].unsafeAddr, (mLen-1) * sizeof(Word))
    r[rLen - 1] = Zero
    # Now shift-left the copied words while adding the new word modulo M
    for i in countdown(aOffset, 0):
      shlAddMod(r, rLen, a[i], M, mBits)

func reduce*[aLen, mLen](r: var Limbs[mLen],
                         a: Limbs[aLen], aBits: static int,
                         M: Limbs[mLen], mBits: static int
                        ) {.inline.} =
  ## Reduce `a` modulo `M` and store the result in `r`
  ##
  ## Warning ⚠: At the moment this is NOT constant-time
  ##            as it relies on hardware division.
  # This is implemented via type-erased indirection to avoid
  # a significant amount of code duplication if instantiated for
  # varying bitwidth.
  reduce(r.view(), a.view(), aBits, M.view(), mBits)
