# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  ../../platforms/abstractions

type
  SignedSecretWord* = distinct SecretWord

  LimbsUnsaturated*[N, Excess: static int] = object
    ## An array of signed secret words
    ## with each word having their top Excess bits unused between function calls
    ## This allows efficient handling of carries and signs without intrinsics or assembly.
    #
    # Comparison with packed representation:
    # 
    # Packed representation
    # - pro: uses less words (important for multiplication which is O(n²) with n the number of words)
    # - pro: less "mental overhead" to keep track (clear/shift) excess bits
    # - con: addition-with-carry require compiler intrinsics or inline assembly.
    #        Compiler codegen may be incredibly bad (GCC).
    # - con: addition-with-carry cannot use instruction-level-parallelism or SIMD vectorization
    #        due to the dependency chain.
    # - con: on x86 addition-with-carry dependency chain has high latency
    #
    # Unsaturated representation:
    # - pro: portable, addition-with-carry can be implemented without compiler support or inline assembly
    # - con: "mental overhead" to keep track of used free bits in algorithms, shifts, multiplication, division, ...
    # - con: substraction-with-borrow internally requires signed integers
    #        or immediate canonicalization
    #        or adding a multiple of the modulus to avoid underflows
    # - con: multiplication requires immediate canonicalization
    # - con: require arithmetic right-shift if using signed integers
    # - con: more memory usage
    # - con: may be slower due to using more words
    # - con: multiple representation of integers
    # - pro: can do many additions before having to canonicalize
    #
    # Constantine used to have an unsaturated representation by default
    # before refactor PR: https://github.com/mratsim/constantine/pull/17
    # Unsaturated representation has been advocated (in particular for generalized mersenne primes)
    # by:
    # - https://bearssl.org/bigint.html
    # - https://cryptojedi.org/peter/data/pairing-20131122.pdf
    # - https://milagro.apache.org/docs/amcl-overview/#representation
    # - https://eprint.iacr.org/2017/437
    #
    # In practice:
    # - Addition is not a bottleneck in cryptography, multiplication is.
    #   Naive asymptotic analysis, makes it 4x~6x more costly
    #   on 256-bit (4-limbs) inputs to 384-bit (6-limbs) inputs
    # - CPUs have significantly reduce carry latencies.
    #   https://www.agner.org/optimize/instruction_tables.pdf
    #   - Nehalem (Intel 2008) used to have 0.33 ADD (reg, reg), 1 ADD (reg, mem)  and 2 ADC reciprcal throughput (ADD 6x faster than ADC)
    #   - Ice Lake (Intel 2019) is 0.25 ADD (reg, reg), 0.5 ADD (reg, mem) and 1 ADC reciprocal throughput
    #   - Zen 3 (AMD 2020) is 0.25 ADD (reg, reg/mem) and 1 ADC reciprocal throughput
    # - Introducing inline assembly is easier than dealing with signed integers
    # - Inline assembly is required to ensure constant-time properties
    #   as compilers get smarters
    # - Canonicalization has an overhead, it just delays (and potentially batches) paying for the dependencing chain.
    words*: array[N, SignedSecretWord]

# ############################################################
#
#                      Accessors
#
# ############################################################

template `[]`*(a: LimbsUnsaturated, idx: int): SignedSecretWord =
  a.words[idx]

template `[]=`*(a: LimbsUnsaturated, idx: int, val: SignedSecretWord) =
  a.words[idx] = val

# ############################################################
#
#                        Conversion
#
# ############################################################

# {.push checks:off.} # Avoid IndexDefect and Int overflows
func fromPackedRepr*[LU, E, LP: static int](
       dst: var LimbsUnsaturated[LU, E],
       src: Limbs[LP]) =
  ## Converts from an packed representation to an unsaturated representation  
  const UnsatBitWidth = WordBitWidth-E
  const Max = MaxWord shr E

  static:
    # Destination and Source size are consistent
    doAssert (LU-1) * UnsatBitWidth <= WordBitwidth * LP, block:
      "\n  (LU-1) * UnsatBitWidth: " & $(LU-1) & " * " & $UnsatBitWidth & " = " & $((LU-1) * UnsatBitWidth) &
      "\n  WordBitwidth * LP: " & $WordBitwidth & " * " & $LP & " = " & $(WordBitwidth * LP)

  var
    srcIdx, dstIdx = 0
    hi, lo = Zero
    accLen = 0
  
  while srcIdx < src.len:
    # Form a 2-word buffer (hi, lo)
    let w = if src_idx < src.len: src[srcIdx]
            else: Zero
    inc srcIdx
 
    if accLen == 0:
      lo = w and Max
      hi = w shr UnsatBitWidth
    else:
      lo = (lo or (w shl accLen)) and Max
      hi = w shr (UnsatBitWidth - accLen)

    accLen += WordBitWidth

    while accLen >= UnsatBitWidth:
      let s = min(accLen, UnsatBitWidth)

      dst[dstIdx] = SignedSecretWord lo
      dstIdx += 1
      accLen -= s
      lo = ((lo shr s) or (hi shl (UnsatBitWidth - s))) and Max
      hi = hi shr s
      
  if dstIdx < dst.words.len:
    dst[dstIdx] = SignedSecretWord lo

  for i in dst_idx + 1 ..< dst.words.len:
    dst[i] = SignedSecretWord Zero

func fromPackedRepr*(T: type LimbsUnsaturated, src: Limbs): T =
  ## Converts from an packed representation to an unsaturated representation
  result.fromPackedRepr(src)

func fromUnsatRepr*[LU, E, LP: static int](
       dst: var Limbs[LP],
       src: LimbsUnsaturated[LU, E]) =
  ## Converts from an packed representation to an unsaturated representation  
  const UnsatBitWidth = WordBitWidth-E

  static:
    # Destination and Source size are consistent
    doAssert (LU-1) * UnsatBitWidth <= WordBitwidth * LP, block:
      "\n  (LU-1) * UnsatBitWidth: " & $(LU-1) & " * " & $UnsatBitWidth & " = " & $((LU-1) * UnsatBitWidth) &
      "\n  WordBitwidth * LP: " & $WordBitwidth & " * " & $LP & " = " & $(WordBitwidth * LP)

  var
    srcIdx {.used.}, dstIdx = 0
    acc = Zero
    accLen = 0

  for src_idx in 0 ..< src.words.len:
    let nextWord = SecretWord src[srcIdx]

    # buffer reads
    acc = acc or (nextWord shl accLen)
    accLen += UnsatBitWidth

    # if full, dump
    if accLen >= WordBitWidth:
      dst[dstIdx] = acc
      inc dstIdx
      accLen -= WordBitWidth
      acc = nextWord shr (UnsatBitWidth - accLen)
  
  if dst_idx < dst.len:
    dst[dst_idx] = acc

  for i in dst_idx + 1 ..< dst.len:
    dst[i] = Zero

# {.pop.}

# ############################################################
#
#                      Initialization
#
# ############################################################

func setZero*(a: var LimbsUnsaturated) =
  ## Set ``a`` to 0
  for i in 0 ..< a.words.len:
    a[i] = SignedSecretWord(0)

func setOne*(a: var LimbsUnsaturated) =
  ## Set ``a`` to 1
  a[0] = SignedSecretWord(1)
  for i in 1 ..< a.words.len:
    a[i] = SignedSecretWord(0)

# ############################################################
#
#                      Arithmetic
#
# ############################################################

# Workaround bug
func `xor`*(x,y: SecretWord): SecretWord {.inline.} =
  # For some reason the template defined in constant_time.nim isn't found
  SecretWord(x.BaseType xor y.BaseType)

when sizeof(int) == 8 and not defined(Constantine32):
  type
    SignedBaseType* = int64
else:
  type
    SignedBaseType* = int32

template fmap(x: SignedSecretWord, op: untyped, y: SignedSecretWord): SignedSecretWord =
  ## Unwrap x and y from their distinct type
  ## Apply op, and rewrap them
  SignedSecretWord(op(SecretWord(x), SecretWord(y)))

template fmapAsgn(x: SignedSecretWord, op: untyped, y: SignedSecretWord) =
  ## Unwrap x and y from their distinct type
  ## Apply assignment op, and rewrap them
  op(SecretWord(x), SecretWord(y))

template `and`*(x, y: SignedSecretWord): SignedSecretWord    = fmap(x, `and`, y)
template `or`*(x, y: SignedSecretWord): SignedSecretWord     = fmap(x, `or`, y)
template `xor`*(x, y: SignedSecretWord): SignedSecretWord    = SignedSecretWord(BaseType(x) xor BaseType(y))
template `not`*(x: SignedSecretWord): SignedSecretWord       = SignedSecretWord(not SecretWord(x))
template `+`*(x, y: SignedSecretWord): SignedSecretWord      = fmap(x, `+`, y)
template `+=`*(x: var SignedSecretWord, y: SignedSecretWord) = fmapAsgn(x, `+=`, y)
template `-`*(x, y: SignedSecretWord): SignedSecretWord      = fmap(x, `-`, y)
template `-=`*(x: var SignedSecretWord, y: SignedSecretWord) = fmapAsgn(x, `-=`, y)

template `-`*(x: SignedSecretWord): SignedSecretWord =
  # We don't use Nim signed integers to avoid range checks
  SignedSecretWord(-SecretWord(x))

template `*`*(x, y: SignedSecretWord): SignedSecretWord =
  # Warning ⚠️ : We assume that hardware multiplication is constant time
  # but this is not always true. See https://www.bearssl.org/ctmul.html
  fmap(x, `*`, y)

# shifts
template ashr*(x: SignedSecretWord, y: SomeNumber): SignedSecretWord =
  ## Arithmetic right shift
  # We need to cast to Nim ints without Nim checks
  SignedSecretWord(cast[SignedBaseType](x).ashr(y))

template lshr*(x: SignedSecretWord, y: SomeNumber): SignedSecretWord =
  ## Logical right shift
  SignedSecretWord(SecretWord(x) shr y)

template lshl*(x: SignedSecretWord, y: SomeNumber): SignedSecretWord =
  ## Logical left shift
  SignedSecretWord(SecretWord(x) shl y)

# ############################################################
#
#             Hardened Boolean primitives
#
# ############################################################

template `==`*(x, y: SignedSecretWord): SecretBool =
  SecretWord(x) == SecretWord(y)

# ############################################################
#
#                Conditional arithmetic
#
# ############################################################

# SignedSecretWord
# ----------------

func isNeg*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Returns 1 if a is negative
  ## and 0 otherwise
  a.lshr(WordBitWidth-1)

func isOdd*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Returns 1 if a is odd
  ## and 0 otherwise
  a and SignedSecretWord(1)

func isZeroMask*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is negative
  ## and 0 otherwise
  not SignedSecretWord(a.SecretWord().isZero())

func isNegMask*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is negative
  ## and 0 otherwise
  a.ashr(WordBitWidth-1)

func isOddMask*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is odd
  ## and 0 otherwise
  -(a and SignedSecretWord(1))

func csetZero*(a: var SignedSecretWord, mask: SignedSecretWord) {.inline.} =
  ## Conditionally set `a` to 0 
  ## mask must be 0 (0x00000...0000) (kept as is)
  ## or -1 (0xFFFF...FFFF) (zeroed)
  a = a and mask

func cneg*(
       a: SignedSecretWord,
       mask: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Conditionally negate `a` 
  ## mask must be 0 (0x00000...0000) (no negation)
  ## or -1 (0xFFFF...FFFF) (negation)
  (a xor mask) - mask

func cadd*(
       a: var SignedSecretWord,
       b: SignedSecretWord,
       mask: SignedSecretWord) {.inline.} =
  ## Conditionally add `b` to `a` 
  ## mask must be 0 (0x00000...0000) (no addition)
  ## or -1 (0xFFFF...FFFF) (addition)
  a = a + (b and mask)

func csub*(
       a: var SignedSecretWord,
       b: SignedSecretWord,
       mask: SignedSecretWord) {.inline.} =
  ## Conditionally substract `b` from `a` 
  ## mask must be 0 (0x00000...0000) (no substraction)
  ## or -1 (0xFFFF...FFFF) (substraction)
  a = a - (b and mask)

# UnsaturatedLimbs
# ----------------

func isZeroMask*(a: LimbsUnsaturated): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is zero
  ## and 0 otherwise
  var accum = SignedSecretWord(0)
  for i in 0 ..< a.words.len:
    accum = accum or a.words[i]
  
  return accum.isZeroMask()

func isNeg*(a: LimbsUnsaturated): SignedSecretWord {.inline.} =
  ## Returns 1 if a is negative
  ## and 0 otherwise
  a[a.words.len-1].lshr(WordBitWidth - a.Excess + 1)

func isNegMask*(a: LimbsUnsaturated): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is negative
  ## and 0 otherwise
  a[a.words.len-1].ashr(WordBitWidth - a.Excess + 1)

func cneg*(
       a: var LimbsUnsaturated,
       mask: SignedSecretWord) {.inline.} =
  ## Conditionally negate `a` 
  ## mask must be 0 (0x00000...0000) (no negation)
  ## or -1 (0xFFFF...FFFF) (negation)
  ## 
  ## Carry propagation is deferred
  for i in 0 ..< a.words.len:
    a[i] = a[i].cneg(mask)

func cadd*(
       a: var LimbsUnsaturated,
       b: LimbsUnsaturated,
       mask: SignedSecretWord) {.inline.} =
  ## Conditionally add `b` to `a` 
  ## mask must be 0 (0x00000...0000) (no addition)
  ## or -1 (0xFFFF...FFFF) (addition)
  ## 
  ## Carry propagation is deferred
  for i in 0 ..< a.words.len:
    a[i].cadd(b[i], mask)

# ############################################################
#
#                Double-Width signed arithmetic
#
# ############################################################

type DSWord* = object
  lo*, hi*: SignedSecretWord

func smulAccNoCarry*(r: var DSWord, a, b: SignedSecretWord) {.inline.}=
  ## Signed accumulated multiplication
  ## (_, hi, lo) += a*b
  ## This assumes no overflowing
  var UV: array[2, SecretWord]
  var carry: Carry
  smul(UV[1], UV[0], SecretWord a, SecretWord b)
  addC(carry, UV[0], UV[0], SecretWord r.lo, Carry(0))
  addC(carry, UV[1], UV[1], SecretWord r.hi, carry)

  r.lo = SignedSecretWord UV[0]
  r.hi = SignedSecretWord UV[1]

func slincombAccNoCarry*(r: var DSWord, a, u, b, v: SignedSecretWord) {.inline.}=
  ## Accumulated linear combination
  ## (_, hi, lo) += a*u + b*v
  ## This assumes no overflowing
  var carry: Carry
  var x1, x0, y1, y0: SecretWord
  smul(x1, x0, SecretWord a, SecretWord u)
  addC(carry, x0, x0, SecretWord r.lo, Carry(0))
  addC(carry, x1, x1, SecretWord r.hi, carry)
  smul(y1, y0, SecretWord b, SecretWord v)
  addC(carry, x0, x0, y0, Carry(0))
  addC(carry, x1, x1, y1, carry)

  r.lo = SignedSecretWord x0
  r.hi = SignedSecretWord x1

func ashr*(
       r: var DSWord,
       k: SomeInteger) {.inline.} =
  ## Arithmetic right-shift of a double-word
  ## This does not normalize the excess bits
  r.lo = r.lo.lshr(k) or r.hi.lshl(WordBitWidth - k)
  r.hi = r.hi.ashr(k)