# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../math/config/precompute,
  ../math/io/io_bigints,
  ../platforms/[primitives, bithacks, endians]

# ############################################################
#
#                Metadata precomputation
#
# ############################################################

# Constantine on CPU is configured at compile-time for several properties that need to be runtime configuration GPUs:
# - word size (32-bit or 64-bit)
# - curve properties access like modulus bitsize or -1/M[0] a.k.a. m0ninv
# - constants are stored in freestanding `const`
#
# This is because it's not possible to store a BigInt[254] and a BigInt[384]
# in a generic way in the same structure, especially without using heap allocation.
# And with Nim's dead code elimination, unused curves are not compiled in.
#
# As there would be no easy way to dynamically retrieve (via an array or a table)
#    const BLS12_381_modulus = ...
#    const BN254_Snarks_modulus = ...
#
# - We would need a macro to properly access each constant.
# - We would need to create a 32-bit and a 64-bit version.
# - Unused curves would be compiled in the program.
#
# Note: on GPU we don't manipulate secrets hence branches and dynamic memory allocations are allowed.
#
# As GPU is a niche usage, instead we recreate the relevant `precompute` and IO procedures
# with dynamic wordsize support.

type
  DynWord* = uint32 or uint64
  BigNum*[T: DynWord] = object
    bits*: uint32
    limbs*: seq[T] 

# Serialization
# ------------------------------------------------

func byteLen*(bits: SomeInteger): SomeInteger =
  ## Length in bytes to serialize BigNum
  (bits + 7) shr 3 # (bits + 8 - 1) div 8

func wordsRequiredForBits*(bits, wordBitwidth: SomeInteger): SomeInteger =
  ## Compute the number of limbs required
  ## from the announced bit length
  
  debug: doAssert wordBitwidth == 32 or wordBitwidth == 64        # Power of 2
  (bits + wordBitwidth - 1) shr log2_vartime(uint32 wordBitwidth) # 5x to 55x faster than dividing by wordBitwidth

func unmarshalBE[T](dst: var BigNum[T], src: openArray[byte]) =
  ## Parse an unsigned integer from its canonical
  ## big-endian unsigned representation (octet string)
  ## and store it into a BigInt.
  ##
  ## In cryptography specifications, this is often called
  ## "Octet string to Integer"
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time
  
  var
    dst_idx = 0
    acc = T(0)
    acc_len = 0
  
  const wordBitwidth = sizeof(T) * 8

  for src_idx in countdown(src.len-1, 0):
    let src_byte = T(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= wordBitwidth:
      dst.limbs[dst_idx] = acc
      inc dst_idx
      acc_len -= wordBitwidth
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.limbs.len:
    dst.limbs[dst_idx] = acc

  for i in dst_idx + 1 ..< dst.limbs.len:
    dst.limbs[i] = 0

func marshalBE[T](
        dst: var openarray[byte],
        src: BigNum[T]) =
  ## Serialize a bigint into its canonical big-endian representation
  ## (octet string)
  ## I.e most significant bit first
  ##
  ## In cryptography specifications, this is often called
  ## "Octet string to Integer"

  var
    src_idx = 0
    acc: T = 0
    acc_len = 0

  const wordBitwidth = sizeof(T) * 8

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.limbs.len: src.limbs[src_idx]
            else: 0
    inc src_idx

    if acc_len == 0:
      # We need to refill the buffer to output 64-bit
      acc = w
      acc_len = wordBitwidth
    else:
      let lo = acc
      acc = w

      if tail >= sizeof(T):
        # Unrolled copy
        tail -= sizeof(T)
        dst.blobFrom(src = lo, tail, bigEndian)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[tail-1-i] = toByte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[tail-1-i] = toByte(lo shr ((tail-i)*8))
        return

func fromHex*(a: var BigNum, bits: uint32, s: string) =
   a.bits = bits
   var bytes = newSeq[byte](bits.byteLen())
   hexToPaddedByteArray(s, bytes, bigEndian)
   
   # 2. Convert canonical uint to BigNum
   const wordBitwidth = BigNum.T.sizeof() * 8
   let numWords = wordsRequiredForBits(bits, wordBitwidth)
   a.limbs.setLen(numWords)
   a.unmarshalBE(bytes)

func toHex*[T](a: BigNum[T]): string =
  ## Conversion to big-endian hex
  ## This is variable-time
  # 1. Convert BigInt to canonical uint
  var bytes = newSeq[byte](byteLen(a.bits))
  bytes.marshalBE(a)

  # 2 Convert canonical uint to hex
  const hexChars = "0123456789abcdef"
  result = newString(2 + 2 * bytes.len)
  result[0] = '0'
  result[1] = 'x'
  for i in 0 ..< bytes.len:
    let bi = bytes[i]
    result[2 + 2*i] = hexChars[bi shr 4 and 0xF]
    result[2 + 2*i+1] = hexChars[bi and 0xF]

# Checks
# ------------------------------------------------

func checkOdd(a: DynWord) =
  doAssert bool(a and 1), "Internal Error: the modulus must be odd to use the Montgomery representation."

func checkOdd(M: BigNum) =
  checkOdd(M.limbs[0])

func checkValidModulus(M: BigNum) =
  const wordBitwidth = uint32(BigNum.T.sizeof() * 8)
  let expectedMsb = M.bits-1 - wordBitwidth * (M.limbs.len.uint32 - 1)
  let msb = log2_vartime(M.limbs[M.limbs.len-1])

  doAssert msb == expectedMsb, "Internal Error: the modulus must use all declared bits and only those:\n" &
    "    Modulus '" & M.toHex() & "' is declared with " & $M.bits &
    " bits but uses " & $(msb + wordBitwidth * uint32(M.limbs.len - 1)) & " bits."


# BigNum arithmetic
# ------------------------------------------------
#
# We copy limbs.nim
# We do not change Limbs.nim to use openarray instead of fixed size array
# because length would become a runtime variable. The compiler wouldn't be able to unroll
# an addition with carry loop.
# Each comparison to check the length would pollute the carry flag
# and so would require saving and restoring it, slowing code at least 3x.
#
# For computing metadata for GPU setup we aren't concerned about this one-time setup cost

func dbl[T](a: var BigNum[T]): bool =
  ## In-place multiprecision double
  ##   a -> 2a
  var carry, sum: T
  for i in 0 ..< a.limbs.len:
    addC(carry, a.limbs[i], a.limbs[i], a.limbs[i], carry)
  result = bool(carry)

func csub[T](a: var BigNum[T], b: BigNum[T], ctl: bool): bool =
  ## In-place optional substraction
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var borrow, diff: T
  for i in 0 ..< a.limbs.len:
    subB(borrow, diff, a.limbs[i], b.limbs[i], borrow)
    if ctl:
      a.limbs[i] = diff

  result = bool(borrow)

func doubleMod(a: var BigNum, M: BigNum) =
  ## In-place modular double
  ##   a -> 2a (mod M)
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var ctl = dbl(a)
  ctl = ctl or not a.csub(M, false)
  discard csub(a, M, ctl)

# Fields metadata
# ------------------------------------------------

func negInvModWord*[T](M: BigNum[T]): T =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   µ ≡ -1/M[0] (mod SecretWord)
  ##
  ## M[0] is the least significant limb of M
  ## M must be odd and greater than 2.
  ##
  ## Assuming 64-bit words:
  ##
  ## µ ≡ -1/M[0] (mod 2^64)
  checkValidModulus(M)
  
  result = invModBitwidth(M.limbs[0])
  # negate to obtain the negative inverse
  result = not(result) + 1

func r_powmod[T](n: static int, M: BigNum[T]): BigNum[T] =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   R ≡ R (mod M) with R = (2^WordBitWidth)^numWords
  ##   or
  ##   R² ≡ R² (mod M) with R = (2^WordBitWidth)^numWords
  ##
  ## Assuming a field modulus of size 256-bit with 63-bit words, we require 5 words
  ##   R² ≡ ((2^63)^5)^2 (mod M) = 2^630 (mod M)

  # Algorithm
  # Bos and Montgomery, Montgomery Arithmetic from a Software Perspective
  # https://eprint.iacr.org/2017/1057.pdf
  #
  # For R = r^n = 2^wn and 2^(wn − 1) ≤ N < 2^wn
  # r^n = 2^63 in on 64-bit and w the number of words
  #
  # 1. C0 = 2^(wn - 1), the power of two immediately less than N
  # 2. for i in 1 ... wn+1
  #      Ci = C(i-1) + C(i-1) (mod M)
  #
  # Thus: C(wn+1) ≡ 2^(wn+1) C0 ≡ 2^(wn + 1) 2^(wn - 1) ≡ 2^(2wn) ≡ (2^wn)^2 ≡ R² (mod M)

  const wordBitwidth = sizeof(T) * 8

  const
    w = M.limbs.len
    msb = M.bits-1 - wordBitwidth * (w - 1)
    start = (w-1)*wordBitwidth + msb
    stop = n*wordBitwidth*w

  result.limbs[M.limbs.len-1] = T(1) shl msb # C0 = 2^(wn-1), the power of 2 immediatly less than the modulus
  for _ in start ..< stop:
    result.doubleMod(M)

func r2mod*(M: BigNum): BigNum =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   R² ≡ R² (mod M) with R = (2^WordBitWidth)^numWords
  ##
  ## Assuming a field modulus of size 256-bit with 63-bit words, we require 5 words
  ##   R² ≡ ((2^63)^5)^2 (mod M) = 2^630 (mod M)
  r_powmod(2, M)