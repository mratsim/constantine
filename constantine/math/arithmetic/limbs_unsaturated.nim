# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  ../../platforms/abstractions

type
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
    doAssert (LU-1) * UnsatBitWidth <= WordBitWidth * LP, block:
      "\n  (LU-1) * UnsatBitWidth: " & $(LU-1) & " * " & $UnsatBitWidth & " = " & $((LU-1) * UnsatBitWidth) &
      "\n  WordBitWidth * LP: " & $WordBitWidth & " * " & $LP & " = " & $(WordBitWidth * LP)

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
    doAssert (LU-1) * UnsatBitWidth <= WordBitWidth * LP, block:
      "\n  (LU-1) * UnsatBitWidth: " & $(LU-1) & " * " & $UnsatBitWidth & " = " & $((LU-1) * UnsatBitWidth) &
      "\n  WordBitWidth * LP: " & $WordBitWidth & " * " & $LP & " = " & $(WordBitWidth * LP)

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

# Workaround bug
# --------------

func `xor`*(x,y: SecretWord): SecretWord {.inline.} =
  # For some reason the template defined in constant_time.nim isn't found
  SecretWord(x.BaseType xor y.BaseType)


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
