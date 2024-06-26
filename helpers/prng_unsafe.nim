# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/arithmetic/limbs_montgomery,
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended,
    ec_twistededwards_affine,
    ec_twistededwards_projective],
  constantine/math/io/io_bigints,
  constantine/math/extension_fields/towers

# ############################################################
#
#              Pseudo-Random Number Generator
#       Unsafe: for testing and benchmarking purposes
#
# ############################################################
#
# Our field elements for elliptic curve cryptography
# are in the 2^256~2^512 range.
# For pairings, with embedding degrees of 12 to 48
# We would need 12~48 field elements per point on the curve
#
# The recommendation by Vigna at http://prng.di.unimi.it
# is to have a period of t^2 if we need t values (i.e. about 2^1024)
# but also that for all practical purposes 2^256 period is enough
#
# We use 2^512 to cover the range the base field elements

# We use Nim effect system to track RNG subroutines
type UnsafePRNG* = object

type RngState* = object
  ## This is the state of a Xoshiro512** PRNG
  ## Unsafe: for testing and benchmarking purposes only
  s: array[8, uint64]

func splitMix64(state: var uint64): uint64 =
  state += 0x9e3779b97f4a7c15'u64
  result = state
  result = (result xor (result shr 30)) * 0xbf58476d1ce4e5b9'u64
  result = (result xor (result shr 27)) * 0xbf58476d1ce4e5b9'u64
  result = result xor (result shr 31)

func seed*(rng: var RngState, x: SomeInteger) =
  ## Seed the random number generator with a fixed seed
  var sm64 = uint64(x)
  rng.s[0] = splitMix64(sm64)
  rng.s[1] = splitMix64(sm64)
  rng.s[2] = splitMix64(sm64)
  rng.s[3] = splitMix64(sm64)
  rng.s[4] = splitMix64(sm64)
  rng.s[5] = splitMix64(sm64)
  rng.s[6] = splitMix64(sm64)
  rng.s[7] = splitMix64(sm64)

func rotl(x: uint64, k: static int): uint64 {.inline.} =
  return (x shl k) or (x shr (64 - k))

template `^=`(x: var uint64, y: uint64) =
  x = x xor y

func next*(rng: var RngState): uint64 {.tags: [UnsafePRNG].} =
  ## Compute a random uint64 from the input state
  ## using xoshiro512** algorithm by Vigna et al
  ## State is updated.
  result = rotl(rng.s[1] * 5, 7) * 9

  let t = rng.s[1] shl 11
  rng.s[2] ^= rng.s[0];
  rng.s[5] ^= rng.s[1];
  rng.s[1] ^= rng.s[2];
  rng.s[7] ^= rng.s[3];
  rng.s[3] ^= rng.s[4];
  rng.s[4] ^= rng.s[5];
  rng.s[0] ^= rng.s[6];
  rng.s[6] ^= rng.s[7];

  rng.s[6] ^= t;

  rng.s[7] = rotl(rng.s[7], 21);

# Integer ranges
# ------------------------------------------------------------

func random_unsafe*(rng: var RngState, maxExclusive: uint32): uint32 =
  ## Generate a random integer in 0 ..< maxExclusive
  ## Uses an unbiaised generation method
  ## See Lemire's algorithm modified by Melissa O'Neill
  ##   https://www.pcg-random.org/posts/bounded-rands.html
  ## Original:
  ##   biaised:   https://lemire.me/blog/2016/06/27/a-fast-alternative-to-the-modulo-reduction/
  ##   unbiaised: https://arxiv.org/pdf/1805.10941.pdf
  ## Also:
  ##   Barrett Reduction: https://en.wikipedia.org/wiki/Barrett_reduction
  ##                      http://www.acsel-lab.com/arithmetic/arith18/papers/ARITH18_Hasenplaugh.pdf
  let max = maxExclusive
  var x = uint32 rng.next()
  var m = x.uint64 * max.uint64
  var l = uint32 m
  if l < max:
    var t = not(max) + 1 # -max
    if t >= max:
      t -= max
      if t >= max:
        t = t mod max
    while l < t:
      x = uint32 rng.next()
      m = x.uint64 * max.uint64
      l = uint32 m
  return uint32(m shr 32)

func random_unsafe*[T: SomeInteger](rng: var RngState, inclRange: Slice[T]): T =
  ## Return a random integer in the given range.
  ## The range bounds must fit in an int32.
  let maxExclusive = inclRange.b + 1 - inclRange.a
  result = T(rng.random_unsafe(uint32 maxExclusive))
  result += inclRange.a

# Containers
# ------------------------------------------------------------

func sample_unsafe*[T](rng: var RngState, src: openarray[T]): T =
  ## Return a random sample from an array
  result = src[rng.random_unsafe(uint32 src.len)]

# BigInts and Fields
# ------------------------------------------------------------
#
# Statistics note:
# - A skewed distribution is not symmetric, it has a longer tail in one direction.
#   for example a RNG that is not centered over 0.5 distribution of 0 and 1 but
#   might produces more 1 than 0 or vice-versa.
# - A bias is a result that is consistently off from the true value i.e.
#   a deviation of an estimate from the quantity under observation

func reduceViaMont[N: static int, F](reduced: var array[N, SecretWord], unreduced: array[2*N, SecretWord], _: typedesc[F]) =
  #  reduced.reduce(unreduced, FF.getModulus())
  #  ----------------------------------------
  #  With R ≡ (2^WordBitWidth)^numWords (mod p)
  #  redc2xMont(a) computes a/R (mod p)
  #  mulMont(a, b) computes a.b.R⁻¹ (mod p)
  #  Hence with b = R², this computes a (mod p).
  #  Montgomery reduction works word by word, quadratically
  #  so for 384-bit prime (6-words on 64-bit CPUs), so 6*6 = 36, twice for multiplication and reduction
  #  significantly faster than division which works bit-by-bit due to constant-time requirement
  reduced.redc2xMont(unreduced,                          # a/R
                     F.getModulus().limbs, F.getNegInvModWord(),
                     F.getSpareBits())
  reduced.mulMont(reduced, F.getR2modP().limbs,          # (a/R) * R² * R⁻¹ ≡ a (mod p)
                  F.getModulus().limbs, F.getNegInvModWord(),
                  F.getSpareBits())

func random_unsafe(rng: var RngState, a: var Limbs) =
  ## Initialize standalone limbs
  for i in 0 ..< a.len:
    a[i] = SecretWord(rng.next())

template clearExtraBitsOverMSB(a: var BigInt) =
  ## If we do bit manipulation at the word level,
  ## for example a 381-bit BigInt stored in a 384-bit buffer
  ## we need to clear the upper 3-bit
  when a.bits != a.limbs.len * WordBitWidth:
    const posExtraBits = a.bits - (a.limbs.len-1) * WordBitWidth
    const mask = (One shl posExtraBits) - One
    a.limbs[a.limbs.len-1] = a.limbs[a.limbs.len-1] and mask

func random_unsafe(rng: var RngState, a: var BigInt) =
  ## Initialize a standalone BigInt
  rng.random_unsafe(a.limbs)
  a.clearExtraBitsOverMSB()

func random_unsafe(rng: var RngState, a: var FF) =
  ## Initialize a Field element
  ## Unsafe: for testing and benchmarking purposes only
  var unreduced{.noinit.}: Limbs[2*a.mres.limbs.len]
  rng.random_unsafe(unreduced)
  a.mres.limbs.reduceViaMont(unreduced, FF)

func random_unsafe(rng: var RngState, a: var ExtensionField) =
  ## Recursively initialize an extension Field element
  ## Unsafe: for testing and benchmarking purposes only
  for i in 0 ..< a.coords.len:
    rng.random_unsafe(a.coords[i])

func random_word_highHammingWeight(rng: var RngState): BaseType =
  let numZeros = rng.random_unsafe(WordBitWidth div 3) # Average Hamming Weight is 1-0.33/2 = 0.83
  result = high(BaseType)
  for _ in 0 ..< numZeros:
    result = result.clearBit rng.random_unsafe(WordBitWidth)

func random_highHammingWeight(rng: var RngState, a: var Limbs) =
  ## Initialize standalone limbs
  ## with high Hamming weight
  ## to have a higher probability of triggering carries
  for i in 0 ..< a.len:
    a[i] = SecretWord rng.random_word_highHammingWeight()

func random_highHammingWeight(rng: var RngState, a: var BigInt) =
  ## Initialize a standalone BigInt
  ## with high Hamming weight
  ## to have a higher probability of triggering carries
  rng.random_highHammingWeight(a.limbs)
  a.clearExtraBitsOverMSB()

func random_highHammingWeight(rng: var RngState, a: var FF) =
  ## Recursively initialize a BigInt (part of a field) or Field element
  ## Unsafe: for testing and benchmarking purposes only
  ## The result will have a high Hamming Weight
  ## to have a higher probability of triggering carries
  var unreduced{.noinit.}: Limbs[2*a.mres.limbs.len]
  rng.random_highHammingWeight(unreduced)
  a.mres.limbs.reduceViaMont(unreduced, FF)

func random_highHammingWeight(rng: var RngState, a: var ExtensionField) =
  ## Recursively initialize an extension Field element
  ## Unsafe: for testing and benchmarking purposes only
  for i in 0 ..< a.coords.len:
    rng.random_highHammingWeight(a.coords[i])

func random_long01Seq(rng: var RngState, a: var openArray[byte]) =
  ## Initialize a bytearray
  ## It is skewed towards producing strings of 1111... and 0000
  ## to trigger edge cases
  # See libsecp256k1: https://github.com/bitcoin-core/secp256k1/blob/dbd41db1/src/testrand_impl.h#L90-L104
  let Bits = a.len * 8
  var bit = 0
  zeroMem(a[0].addr, a.len)
  while bit < Bits :
    var now = 1 + (rng.random_unsafe(1 shl 6) * rng.random_unsafe(1 shl 5) + 16) div 31
    let val = rng.sample_unsafe([0, 1])
    while now > 0 and bit < Bits:
      a[bit shr 3] = a[bit shr 3] or byte(val shl (bit and 7))
      dec now
      inc bit

func random_long01Seq(rng: var RngState, a: var BigInt) =
  ## Initialize a bigint
  ## It is skewed towards producing strings of 1111... and 0000
  ## to trigger edge cases
  var buf: array[a.bits.ceilDiv_vartime(8), byte]
  rng.random_long01Seq(buf)
  let order = rng.sample_unsafe([bigEndian, littleEndian])
  if order == bigEndian:
    a.unmarshal(buf, bigEndian)
  else:
    a.unmarshal(buf, littleEndian)
  a.clearExtraBitsOverMSB()

func random_long01Seq(rng: var RngState, a: var Limbs) =
  ## Initialize standalone limbs
  ## It is skewed towards producing strings of 1111... and 0000
  ## to trigger edge cases
  const bits = a.len*WordBitWidth

  var t{.noInit.}: BigInt[bits]
  rng.random_long01Seq(t)
  a = t.limbs

func random_long01Seq(rng: var RngState, a: var FF) =
  ## Recursively initialize a BigInt (part of a field) or Field element
  ## It is skewed towards producing strings of 1111... and 0000
  ## to trigger edge cases
  var unreduced{.noinit.}: Limbs[2*a.mres.limbs.len]
  rng.random_long01Seq(unreduced)
  a.mres.limbs.reduceViaMont(unreduced, FF)

func random_long01Seq(rng: var RngState, a: var ExtensionField) =
  ## Recursively initialize an extension Field element
  ## Unsafe: for testing and benchmarking purposes only
  for i in 0 ..< a.coords.len:
    rng.random_long01Seq(a.coords[i])

# Elliptic curves
# ------------------------------------------------------------

type ECP = EC_ShortW_Aff or EC_ShortW_Prj or EC_ShortW_Jac or EC_ShortW_JacExt or
           EC_TwEdw_Aff or EC_TwEdw_Prj
type ECP_ext = EC_ShortW_Prj or EC_ShortW_Jac or EC_ShortW_JacExt or
               EC_TwEdw_Prj

template trySetFromCoord[F](a: ECP, fieldElem: F): SecretBool =
  when a is (EC_ShortW_Aff or EC_ShortW_Prj or EC_ShortW_Jac or EC_ShortW_JacExt):
    trySetFromCoordX(a, fieldElem)
  else:
    trySetFromCoordY(a, fieldElem)

template trySetFromCoords[F](a: ECP, fieldElem, scale: F): SecretBool =
  when a is (EC_ShortW_Prj or EC_ShortW_Jac or EC_ShortW_JacExt):
    trySetFromCoordsXandZ(a, fieldElem, scale)
  else:
    trySetFromCoordsYandZ(a, fieldElem, scale)

func random_unsafe(rng: var RngState, a: var ECP) =
  ## Initialize a random curve point with Z coordinate == 1
  ## Unsafe: for testing and benchmarking purposes only
  var fieldElem {.noInit.}: a.F
  var success = CtFalse

  while not bool(success):
    # Euler's criterion: there are (p-1)/2 squares in a field with modulus `p`
    #                    so we have a probability of ~0.5 to get a good point
    rng.random_unsafe(fieldElem)
    success = trySetFromCoord(a, fieldElem)

func random_unsafe_with_randZ(rng: var RngState, a: var ECP_ext) =
  ## Initialize a random curve point with Z coordinate being random
  ## Unsafe: for testing and benchmarking purposes only
  var Z{.noInit.}: a.F
  rng.random_unsafe(Z) # If Z is zero, X will be zero and that will be an infinity point

  var fieldElem {.noInit.}: a.F
  var success = CtFalse

  while not bool(success):
    rng.random_unsafe(fieldElem)
    success = trySetFromCoords(a, fieldElem, Z)

func random_highHammingWeight(rng: var RngState, a: var ECP) =
  ## Initialize a random curve point with Z coordinate == 1
  ## This will be generated with a biaised RNG with high Hamming Weight
  ## to trigger carry bugs
  var fieldElem {.noInit.}: a.F
  var success = CtFalse

  while not bool(success):
    # Euler's criterion: there are (p-1)/2 squares in a field with modulus `p`
    #                    so we have a probability of ~0.5 to get a good point
    rng.random_highHammingWeight(fieldElem)
    success = trySetFromCoord(a, fieldElem)

func random_highHammingWeight_with_randZ(rng: var RngState, a: var ECP_ext) =
  ## Initialize a random curve point with Z coordinate == 1
  ## This will be generated with a biaised RNG with high Hamming Weight
  ## to trigger carry bugs
  var Z{.noInit.}: a.F
  rng.random_highHammingWeight(Z) # If Z is zero, X will be zero and that will be an infinity point

  var fieldElem {.noInit.}: a.F
  var success = CtFalse

  while not bool(success):
    rng.random_highHammingWeight(fieldElem)
    success = trySetFromCoords(a, fieldElem, Z)

func random_long01Seq(rng: var RngState, a: var ECP) =
  ## Initialize a random curve point with Z coordinate == 1
  ## This will be generated with a biaised RNG
  ## that produces long bitstrings of 0 and 1
  ## to trigger edge cases
  var fieldElem {.noInit.}: a.F
  var success = CtFalse

  while not bool(success):
    # Euler's criterion: there are (p-1)/2 squares in a field with modulus `p`
    #                    so we have a probability of ~0.5 to get a good point
    rng.random_long01Seq(fieldElem)
    success = trySetFromCoord(a, fieldElem)

func random_long01Seq_with_randZ(rng: var RngState, a: var ECP_ext) =
  ## Initialize a random curve point with Z coordinate == 1
  ## This will be generated with a biaised RNG
  ## that produces long bitstrings of 0 and 1
  ## to trigger edge cases
  var Z{.noInit.}: a.F
  rng.random_long01Seq(Z) # If Z is zero, X will be zero and that will be an infinity point

  var fieldElem {.noInit.}: a.F
  var success = CtFalse

  while not bool(success):
    rng.random_long01Seq(fieldElem)
    success = trySetFromCoords(a, fieldElem, Z)

# Generic over any Constantine type
# ------------------------------------------------------------

func random_unsafe*(rng: var RngState, T: typedesc): T =
  ## Create a random Field or Extension Field or Curve Element
  ## Unsafe: for testing and benchmarking purposes only
  when T is ECP:
    rng.random_unsafe(result)
  elif T is SomeNumber:
    cast[T](rng.next())
  elif T is BigInt:
    rng.random_unsafe(result)
  else: # Fields
    rng.random_unsafe(result)

func random_unsafe_with_randZ*(rng: var RngState, T: typedesc[ECP_ext]): T =
  ## Create a random curve element with a random Z coordinate
  ## Unsafe: for testing and benchmarking purposes only
  rng.random_unsafe_with_randZ(result)

func random_highHammingWeight*(rng: var RngState, T: typedesc): T =
  ## Create a random Field or Extension Field or Curve Element
  ## Skewed towards high Hamming Weight
  when T is ECP:
    rng.random_highHammingWeight(result)
  elif T is SomeNumber:
    cast[T](rng.next())
  elif T is BigInt:
    rng.random_highHammingWeight(result)
  else: # Fields
    rng.random_highHammingWeight(result)

func random_highHammingWeight_with_randZ*(rng: var RngState, T: typedesc[ECP_ext]): T =
  ## Create a random curve element with a random Z coordinate
  ## Skewed towards high Hamming Weight
  rng.random_highHammingWeight_with_randZ(result)

func random_long01Seq*(rng: var RngState, T: typedesc): T =
  ## Create a random Field or Extension Field or Curve Element
  ## Skewed towards long bitstrings of 0 or 1
  when T is ECP:
    rng.random_long01Seq(result)
  elif T is SomeNumber:
    cast[T](rng.next())
  elif T is BigInt:
    rng.random_long01Seq(result)
  else: # Fields
    rng.random_long01Seq(result)

func random_long01Seq_with_randZ*(rng: var RngState, T: typedesc[ECP_ext]): T =
  ## Create a random curve element with a random Z coordinate
  ## Skewed towards long bitstrings of 0 or 1
  rng.random_long01Seq_with_randZ(result)

func random_unsafe*[T](rng: var RngState, a: var openArray[T]) =
  ## Initialize an array or sequence of T
  ## with random values
  for elem in a.mitems():
    elem = rng.random_unsafe(typeof(elem))

# Byte sequences
# ------------------------------------------------------------

func random_byte_seq*(rng: var RngState, length: int): seq[byte] =
  result.newSeq(length)
  for b in result.mitems:
    b = byte rng.next()

# Sanity checks
# ------------------------------------------------------------

when isMainModule:
  import std/[tables, times, strutils]

  var rng: RngState
  let timeSeed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(timeSeed)
  echo "prng_sanity_checks xoshiro512** seed: ", timeSeed


  proc test[T](s: Slice[T]) =
    var c = initCountTable[int]()

    for _ in 0 ..< 1_000_000:
      c.inc(rng.random_unsafe(s))

    echo "1'000'000 pseudo-random outputs from ", s.a, " to ", s.b, " (incl): ", c

  test(0..1)
  test(0..2)
  test(1..52)
  test(-10..10)

  echo "\n-----------------------------\n"
  echo "High Hamming Weight check"
  for _ in 0 ..< 10:
    let word = rng.random_word_highHammingWeight()
    echo "0b", cast[BiggestInt](word).toBin(WordBitWidth), " - 0x", word.toHex()

  echo "\n-----------------------------\n"
  echo "Long strings of 0 or 1 check"
  for _ in 0 ..< 10:
    var a: BigInt[127]
    rng.random_long01seq(a)
    stdout.write "0b"
    for word in a.limbs:
      stdout.write cast[BiggestInt](word).toBin(WordBitWidth)
    stdout.write " - 0x"
    for word in a.limbs:
      stdout.write word.BaseType.toHex()
    stdout.write '\n'
