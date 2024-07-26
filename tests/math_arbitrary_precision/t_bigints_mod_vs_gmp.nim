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
  constantine/math/[arithmetic, io/io_bigints],
  constantine/platforms/primitives,
  constantine/serialization/codecs,
  constantine/math_arbitrary_precision/arithmetic/limbs_divmod_vartime,
  # Test utilities
  helpers/prng_unsafe

echo "\n------------------------------------------------------\n"
# We test up to 1024-bit, more is really slow

var bitSizeRNG {.compileTime.} = initRand(1234)
const CryptoModSizes = [
  # Modulus sizes occuring in crypto
  # To be tested more often

  # Special-case
  64,

  # RSA
  1024,
  2048,
  3072,
  # secp256k1, Edwards25519
  256,
  # Barreto-Naehrig
  254, # BN254
  # Barreto-Lynn-Scott
  377, # BLS12-377
  381, # BLS12-381
  # Brezing-Weng
  761, # BW6-761
  # Cocks-Pinch
  782, # CP6-782
  # Miyaji-Nakabayashi-Takano
  298, # MNT4-298, MNT6-298
  753, # MNT4-753, MNT6-753
  # NIST recommended curves for US Federal Government (FIPS)
  # https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-4.pdf
  192,
  224,
  # 256
  384,
  521
]

macro testRandomModSizes(numSizes: static int, aBits, mBits, body: untyped): untyped =
  ## Generate `numSizes` random bit sizes known at compile-time to test against GMP
  ## for A mod M
  result = newStmtList()

  for _ in 0 ..< numSizes:
    let aBitsVal = bitSizeRNG.rand(62 .. 8192)
    let mBitsVal = block:
      # Pick from curve modulus if odd
      if bool(bitSizeRNG.rand(high(int)) and 1):
        bitSizeRNG.sample(CryptoModSizes)
      else:
        # range 62..1024 to highlight edge effects of the WordBitWidth (63)
        bitSizeRNG.rand(62 .. 1024)

    result.add quote do:
      block:
        const `aBits` = `aBitsVal`
        const `mBits` = `mBitsVal`
        block:
          `body`

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian = -1'i32
  GMP_WordNativeEndian = 0'i32
  GMP_WordBigEndian = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst = -1'i32

proc main() =
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo "test_bigints_mod_vs_gmp xoshiro512** seed: ", seed

  var a, m, r: mpz_t
  mpz_init(a)
  mpz_init(m)
  mpz_init(r)

  testRandomModSizes(60, aBits, mBits):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: random dividend (" & align($aBits, 4) & "-bit) -- random modulus (" & align($mBits, 4) & "-bit)"

    # Build the bigints
    let aTest = rng.random_unsafe(BigInt[aBits])
    var mTest = rng.random_unsafe(BigInt[mBits])
    # Ensure modulus MSB is set
    mTest.setBit(mBits-1)

    #########################################################
    # Conversion to GMP
    const aLen = aBits.ceilDiv_vartime(8)
    const mLen = mBits.ceilDiv_vartime(8)

    var aBuf: array[aLen, byte]
    var mBuf: array[mLen, byte]

    aBuf.marshal(aTest, bigEndian)
    mBuf.marshal(mTest, bigEndian)

    mpz_import(a, aLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, aBuf[0].addr)
    mpz_import(m, mLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, mBuf[0].addr)

    #########################################################
    # Modulus
    mpz_mod(r, a, m)

    var rTest, rTest_vartime: BigInt[mBits]
    rTest.reduce(aTest, mTest)
    doAssert rTest_vartime.limbs.reduce_vartime(aTest.limbs, mTest.limbs)

    #########################################################
    # Check

    {.push warnings: off.} # deprecated csize
    var aW, mW, rW: csize  # Words written by GMP
    {.pop.}

    var rGMP: array[mLen, byte]
    discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

    var rConstantine, rCttVartime: array[mLen, byte]
    marshal(rConstantine, rTest, bigEndian)
    marshal(rCttVartime, rTest_vartime, bigEndian)

    # echo "rGMP: ", rGMP.toHex()
    # echo "rConstantine: ", rConstantine.toHex()

    # Note: in bigEndian, GMP aligns left while constantine aligns right
    doAssert rGMP.toOpenArray(0, rW-1) == rConstantine.toOpenArray(mLen-rW, mLen-1), block:
      # Reexport as bigEndian for debugging
      discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
      discard mpz_export(mBuf[0].addr, mW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, m)
      "\nModulus with operands\n" &
      "  a (" & align($aBits, 4) & "-bit):   " & aBuf.toHex & "\n" &
      "  m (" & align($mBits, 4) & "-bit):   " & mBuf.toHex & "\n" &
      "failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rConstantine.toHex() & "\n" &
      "(Note that GMP aligns bytes left while constantine aligns bytes right)"

    doAssert rGMP.toOpenArray(0, rW-1) == rCttVartime.toOpenArray(mLen-rW, mLen-1), block:
      # Reexport as bigEndian for debugging
      discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
      discard mpz_export(mBuf[0].addr, mW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, m)
      "\nModulus with operands\n" &
      "  a (" & align($aBits, 4) & "-bit):   " & aBuf.toHex & "\n" &
      "  m (" & align($mBits, 4) & "-bit):   " & mBuf.toHex & "\n" &
      "failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rCttVartime.toHex() & "\n" &
      "(Note that GMP aligns bytes left while constantine aligns bytes right)"

  mpz_clear(r)
  mpz_clear(m)
  mpz_clear(a)

main()
