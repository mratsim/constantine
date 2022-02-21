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
  gmp, stew/byteutils,
  # Internal
  ../../constantine/backend/io/io_bigints,
  ../../constantine/backend/arithmetic,
  ../../constantine/backend/primitives,
  ../../constantine/backend/config/[common, type_bigint]

echo "\n------------------------------------------------------\n"
# We test up to 1024-bit, more is really slow

var bitSizeRNG {.compileTime.} = initRand(1234)

macro testRandomModSizes(numSizes: static int, rBits, aBits, bBits, body: untyped): untyped =
  ## Generate `numSizes` random bit sizes known at compile-time to test against GMP
  ## for A mod M
  result = newStmtList()

  for _ in 0 ..< numSizes:
    let aBitsVal = bitSizeRNG.rand(126 .. 2048)
    let bBitsVal = bitSizeRNG.rand(126 .. 2048)
    let rBitsVal = bitSizeRNG.rand(62 .. 4096+128)

    result.add quote do:
      block:
        const `aBits` = `aBitsVal`
        const `bBits` = `bBitsVal`
        const `rBits` = `rBitsVal`
        block:
          `body`

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian {.used.} = -1'i32
  GMP_WordNativeEndian {.used.} = 0'i32
  GMP_WordBigEndian {.used.} = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst {.used.} = -1'i32

proc main() =
  var gmpRng: gmp_randstate_t
  gmp_randinit_mt(gmpRng)
  # The GMP seed varies between run so that
  # test coverage increases as the library gets tested.
  # This requires to dump the seed in the console or the function inputs
  # to be able to reproduce a bug
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  echo "GMP seed: ", seed
  gmp_randseed_ui(gmpRng, seed)

  var r, a, b: mpz_t
  mpz_init(r)
  mpz_init(a)
  mpz_init(b)

  testRandomModSizes(12, rBits, aBits, bBits):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: random mul  r (", align($rBits, 4), "-bit) <- a (", align($aBits, 4), "-bit) * b (", align($bBits, 4), "-bit) (full mul bits: ", align($(aBits+bBits), 4), "), r large enough? ", rBits >= aBits+bBits

    # Generate random value in the range 0 ..< 2^aBits
    mpz_urandomb(a, gmpRng, aBits)
    # Generate random modulus and ensure the MSB is set
    mpz_urandomb(b, gmpRng, bBits)
    mpz_setbit(r, aBits+bBits)

    # discard gmp_printf(" -- %#Zx mod %#Zx\n", a.addr, m.addr)

    #########################################################
    # Conversion buffers
    const aLen = (aBits + 7) div 8
    const bLen = (bBits + 7) div 8

    var aBuf: array[aLen, byte]
    var bBuf: array[bLen, byte]

    {.push warnings: off.} # deprecated csize
    var aW, bW: csize # Word written by GMP
    {.pop.}

    discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
    discard mpz_export(bBuf[0].addr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)

    # Since the modulus is using all bits, it's we can test for exact amount copy
    doAssert aLen >= aW, "Expected at most " & $aLen & " bytes but wrote " & $aW & " for " & toHex(aBuf) & " (big-endian)"
    doAssert bLen >= bW, "Expected at most " & $bLen & " bytes but wrote " & $bW & " for " & toHex(bBuf) & " (big-endian)"

    # Build the bigint
    let aTest = BigInt[aBits].fromRawUint(aBuf.toOpenArray(0, aW-1), bigEndian)
    let bTest = BigInt[bBits].fromRawUint(bBuf.toOpenArray(0, bW-1), bigEndian)

    #########################################################
    # Multiplication
    mpz_mul(r, a, b)

    # If a*b overflow the result size we truncate
    const numWords = wordsRequired(rBits)
    when numWords < wordsRequired(aBits+bBits):
      echo "  truncating from ", wordsRequired(aBits+bBits), " words to ", numWords, " (2^", WordBitwidth * numWords, ")"
      r.mpz_tdiv_r_2exp(r, WordBitwidth * numWords)

    # Constantine
    var rTest: BigInt[rBits]
    rTest.prod(aTest, bTest)

    #########################################################
    # Check
    const rLen = numWords * WordBitWidth
    var rGMP: array[rLen, byte]
    {.push warnings: off.} # deprecated csize
    var rW: csize # Word written by GMP
    {.pop.}
    discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

    var rConstantine: array[rLen, byte]
    exportRawUint(rConstantine, rTest, bigEndian)

    # Note: in bigEndian, GMP aligns left while constantine aligns right
    doAssert rGMP.toOpenArray(0, rW-1) == rConstantine.toOpenArray(rLen-rW, rLen-1), block:
      # Reexport as bigEndian for debugging
      discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
      discard mpz_export(bBuf[0].addr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)
      "\nMultiplication with operands\n" &
      "  a (" & align($aBits, 4) & "-bit):   " & aBuf.toHex & "\n" &
      "  b (" & align($bBits, 4) & "-bit):   " & bBuf.toHex & "\n" &
      "into r of size " & align($rBits, 4) & "-bit failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rConstantine.toHex() & "\n" &
      "(Note that GMP aligns bytes left while constantine aligns bytes right)"

main()
