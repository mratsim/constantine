# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[random, macros, times, strutils],
  # Third-party
  gmp,
  # Internal
  constantine/math/io/io_bigints,
  constantine/math/arithmetic,
  constantine/platforms/abstractions,
  # Test utilities
  helpers/prng_unsafe

echo "\n------------------------------------------------------\n"
# We test up to 1024-bit, more is really slow

var bitSizeRNG {.compileTime.} = initRand(1234)

macro testRandomModSizes(numSizes: static int, rBits, aBits, bBits, wordsStartIndex, body: untyped): untyped =
  ## Generate `numSizes` random bit sizes known at compile-time to test against GMP
  ## for A mod M
  result = newStmtList()

  for _ in 0 ..< numSizes:
    let aBitsVal = bitSizeRNG.rand(126 .. 2048)
    let bBitsVal = bitSizeRNG.rand(126 .. 2048)
    let rBitsVal = bitSizeRNG.rand(62 .. 4096+128)
    let wordsStartIndexVal = bitSizeRNG.rand(1 .. wordsRequired(4096+128))

    result.add quote do:
      block:
        const `aBits` = `aBitsVal`
        const `bBits` = `bBitsVal`
        const `rBits` = `rBitsVal`
        const `wordsStartIndex` = `wordsStartIndexVal`

        block:
          `body`

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian {.used.} = -1'i32
  GMP_WordNativeEndian {.used.} = 0'i32
  GMP_WordBigEndian {.used.} = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst {.used.} = -1'i32

proc main() =
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo "test_bigints_mod_vs_gmp xoshiro512** seed: ", seed

  var r, a, b: mpz_t
  mpz_init(r)
  mpz_init(a)
  mpz_init(b)
  defer:
    mpz_clear(b)
    mpz_clear(a)
    mpz_clear(r)

  testRandomModSizes(12, rBits, aBits, bBits, wordsStartIndex):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: random mul_high_words  r (", align($rBits, 4),
      "-bit, keeping from ", wordsStartIndex,
      " word index) <- a (", align($aBits, 4),
      "-bit) * b (", align($bBits, 4), "-bit) (full mul bits: ", align($(aBits+bBits), 4),
      "), r large enough? ", wordsRequired(rBits) >= wordsRequired(aBits+bBits) - wordsStartIndex

    # Build the bigints
    let aTest = rng.random_unsafe(BigInt[aBits])
    var bTest = rng.random_unsafe(BigInt[bBits])

    #########################################################
    # Conversion to GMP
    const aLen = aBits.ceilDiv_vartime(8)
    const bLen = bBits.ceilDiv_vartime(8)

    var aBuf: array[aLen, byte]
    var bBuf: array[bLen, byte]

    aBuf.marshal(aTest, bigEndian)
    bBuf.marshal(bTest, bigEndian)

    mpz_import(a, aLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, aBuf[0].addr)
    mpz_import(b, bLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, bBuf[0].addr)

    #########################################################
    # Multiplication + drop low words
    mpz_mul(r, a, b)
    var shift: mpz_t
    mpz_init(shift)
    r.mpz_tdiv_q_2exp(r, WordBitWidth * wordsStartIndex)

    # If a*b overflow the result size we truncate
    const numWords = wordsRequired(rBits)
    when numWords < wordsRequired(aBits+bBits):
      echo "  truncating from ", wordsRequired(aBits+bBits), " words to ", numWords, " (2^", WordBitWidth * numWords, ")"
      r.mpz_tdiv_r_2exp(r, WordBitWidth * numWords)

    # Constantine
    var rTest: BigInt[rBits]
    rTest.prod_high_words(aTest, bTest, wordsStartIndex)

    #########################################################
    # Check

    {.push warnings: off.} # deprecated csize
    var aW, bW, rW: csize  # Word written by GMP
    {.pop.}

    const rLen = numWords * WordBitWidth
    var rGMP: array[rLen, byte]
    discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

    var rConstantine: array[rLen, byte]
    marshal(rConstantine, rTest, bigEndian)

    # Note: in bigEndian, GMP aligns left while constantine aligns right
    doAssert rGMP.toOpenArray(0, rW-1) == rConstantine.toOpenArray(rLen-rW, rLen-1), block:
      # Reexport as bigEndian for debugging
      discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
      discard mpz_export(bBuf[0].addr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)
      "\nMultiplication with operands\n" &
      "  a (" & align($aBits, 4) & "-bit):   " & aBuf.toHex & "\n" &
      "  b (" & align($bBits, 4) & "-bit):   " & bBuf.toHex & "\n" &
      "  keeping words starting from:   " & $wordsStartIndex & "\n" &
      "into r of size " & align($rBits, 4) & "-bit failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rConstantine.toHex() & "\n" &
      "(Note that GMP aligns bytes left while constantine aligns bytes right)"

main()
