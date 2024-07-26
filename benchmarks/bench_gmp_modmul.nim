# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[macros, times, strutils, monotimes],
  # Third-party
  gmp,
  # Internal
  constantine/math/io/io_bigints,
  constantine/math/arithmetic,
  constantine/math_arbitrary_precision/arithmetic/limbs_divmod_vartime,
  constantine/platforms/abstractions,
  constantine/serialization/codecs,
  # Test utilities
  helpers/prng_unsafe

echo "\n------------------------------------------------------\n"
# We test up to 1024-bit, more is really slow

macro testSizes(rBits, aBits, bBits, body: untyped): untyped =
  ## Configure sizes known at compile-time to test against GMP
  result = newStmtList()

  for size in [256, 384, 121*8]:
    let aBitsVal = size
    let bBitsVal = size
    let rBitsVal = size * 2

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
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo "rng xoshiro512** seed: ", seed
  echo ""

  var r, rMod, a, b: mpz_t
  mpz_init(r)
  mpz_init(rMod)
  mpz_init(a)
  mpz_init(b)
  defer:
    mpz_clear(b)
    mpz_clear(a)
    mpz_clear(rMod)
    mpz_clear(r)

  testSizes(rBits, aBits, bBits):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: mul  r (", align($rBits, 4), "-bit) <- a (", align($aBits, 4), "-bit) * b (", align($bBits, 4), "-bit)"

    # Build the bigints
    let aTest = rng.random_unsafe(BigInt[aBits])
    var bTest = rng.random_unsafe(BigInt[bBits])

    #########################################################
    # Conversion to GMP
    const aLen = (aBits + 7) div 8
    const bLen = (bBits + 7) div 8

    var aBuf: array[aLen, byte]
    var bBuf: array[bLen, byte]

    aBuf.marshal(aTest, bigEndian)
    bBuf.marshal(bTest, bigEndian)

    mpz_import(a, aLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, aBuf[0].addr)
    mpz_import(b, bLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, bBuf[0].addr)

    #########################################################
    # Multiplication
    const NumIters = 1000000

    let startGMP = getMonoTime()
    for _ in 0 ..< NumIters:
      mpz_mul(r, a, b)
    let stopGMP = getMonoTime()
    echo "GMP         - ", aBits, "  x  ", bBits, "           -> ", rBits,  " mul: ", float(inNanoseconds((stopGMP-startGMP)))/float(NumIters), " ns"

    # If a*b overflow the result size we truncate
    const numWords = wordsRequired(rBits)
    when numWords < wordsRequired(aBits+bBits):
      echo "  truncating from ", wordsRequired(aBits+bBits), " words to ", numWords, " (2^", WordBitwidth * numWords, ")"
      r.mpz_tdiv_r_2exp(r, WordBitwidth * numWords)

    var rTest: BigInt[rBits]

    let startCTT = getMonoTime()
    for _ in 0 ..< NumIters:
      rTest.prod(aTest, bTest)
    let stopCTT = getMonoTime()
    echo "Constantine - ", aBits, "  x  ", bBits, "           -> ", rBits,  " mul: ", float(inNanoseconds((stopCTT-startCTT)))/float(NumIters), " ns"

    echo "----"
    # Modular reduction

    let startGMPmod = getMonoTime()
    for _ in 0 ..< NumIters:
      mpz_mod(rMod, a, b)
    let stopGMPmod = getMonoTime()
    echo "GMP         - ", aBits, " mod ", bBits, "           -> ", bBits,  " mod: ", float(inNanoseconds((stopGMPmod-startGMPmod)))/float(NumIters), " ns"

    var rTestMod: BigInt[bBits]

    let startCTTMod = getMonoTime()
    for _ in 0 ..< NumIters:
      rTestMod.reduce(aTest, bTest)
    let stopCTTMod = getMonoTime()
    echo "Constantine - ", aBits, " mod ", bBits, "           -> ", bBits,  " mod: ", float(inNanoseconds((stopCTTmod-startCTTmod)))/float(NumIters), " ns"

    let startCTTvartimeMod = getMonoTime()
    var q {.noInit.}: BigInt[bBits]
    for _ in 0 ..< NumIters:
      discard divRem_vartime(q.limbs, rTestMod.limbs, aTest.limbs, bTest.limbs)
    let stopCTTvartimeMod = getMonoTime()
    echo "Constantine - ", aBits, " mod ", bBits, " (vartime) -> ", bBits,  " mod: ", float(inNanoseconds((stopCTTvartimeMod-startCTTvartimeMod)))/float(NumIters), " ns"

    echo "----"
    # Modular reduction - double-size

    let startGMPmod2 = getMonoTime()
    for _ in 0 ..< NumIters:
      mpz_mod(rMod, r, b)
    let stopGMPmod2 = getMonoTime()
    echo "GMP         - ", rBits, " mod ", bBits, "           -> ", bBits,  " mod: ", float(inNanoseconds((stopGMPmod2-startGMPmod2)))/float(NumIters), " ns"

    let startCTTMod2 = getMonoTime()
    for _ in 0 ..< NumIters:
      rTestMod.reduce(rTest, bTest)
    let stopCTTMod2 = getMonoTime()
    echo "Constantine - ", rBits, " mod ", bBits, "           -> ", bBits,  " mod: ", float(inNanoseconds((stopCTTmod2-startCTTmod2)))/float(NumIters), " ns"

    let startCTTvartimeMod2 = getMonoTime()
    var q2 {.noInit.}: BigInt[bBits]
    for _ in 0 ..< NumIters:
      discard divRem_vartime(q2.limbs, rTestMod.limbs, rTest.limbs, bTest.limbs)
    let stopCTTvartimeMod2 = getMonoTime()
    echo "Constantine - ", rBits, " mod ", bBits, " (vartime) -> ", bBits,  " mod: ", float(inNanoseconds((stopCTTvartimeMod2-startCTTvartimeMod2)))/float(NumIters), " ns"

    echo ""

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
      "into r of size " & align($rBits, 4) & "-bit failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rConstantine.toHex() & "\n" &
      "(Note that GMP aligns bytes left while constantine aligns bytes right)"

main()
