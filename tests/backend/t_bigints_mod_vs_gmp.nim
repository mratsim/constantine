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
  ../../constantine/backend/primitives

echo "\n------------------------------------------------------\n"
# We test up to 1024-bit, more is really slow

var bitSizeRNG {.compileTime.} = initRand(1234)
const CryptoModSizes = [
  # Modulus sizes occuring in crypto
  # To be tested more often

  # RSA
  1024,
  2048,
  3072,
  # secp256k1, Curve25519
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
    let aBitsVal = bitSizeRNG.rand(126 .. 8192)
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
  var gmpRng: gmp_randstate_t
  gmp_randinit_mt(gmpRng)
  # The GMP seed varies between run so that
  # test coverage increases as the library gets tested.
  # This requires to dump the seed in the console or the function inputs
  # to be able to reproduce a bug
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  echo "GMP seed: ", seed
  gmp_randseed_ui(gmpRng, seed)

  var a, m, r: mpz_t
  mpz_init(a)
  mpz_init(m)
  mpz_init(r)

  testRandomModSizes(12, aBits, mBits):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: random dividend (" & align($aBits, 4) & "-bit) -- random modulus (" & align($mBits, 4) & "-bit)"

    # Generate random value in the range 0 ..< 2^aBits
    mpz_urandomb(a, gmpRng, aBits)
    # Generate random modulus and ensure the MSB is set
    mpz_urandomb(m, gmpRng, mBits)
    mpz_setbit(m, mBits-1)

    # discard gmp_printf(" -- %#Zx mod %#Zx\n", a.addr, m.addr)

    #########################################################
    # Conversion buffers
    const aLen = (aBits + 7) div 8
    const mLen = (mBits + 7) div 8

    var aBuf: array[aLen, byte]
    var mBuf: array[mLen, byte]

    var aW, mW: csize # Word written by GMP

    discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
    discard mpz_export(mBuf[0].addr, mW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, m)

    # Since the modulus is using all bits, it's we can test for exact amount copy
    doAssert aLen >= aW, "Expected at most " & $aLen & " bytes but wrote " & $aW & " for " & toHex(aBuf) & " (big-endian)"
    doAssert mLen == mW, "Expected " & $mLen & " bytes but wrote " & $mW & " for " & toHex(mBuf) & " (big-endian)"

    # Build the bigint
    let aTest = BigInt[aBits].fromRawUint(aBuf.toOpenArray(0, aW-1), bigEndian)
    let mTest = BigInt[mBits].fromRawUint(mBuf.toOpenArray(0, mW-1), bigEndian)

    #########################################################
    # Modulus
    mpz_mod(r, a, m)

    var rTest: BigInt[mBits]
    rTest.reduce(aTest, mTest)

    #########################################################
    # Check
    var rGMP: array[mLen, byte]
    var rW: csize # Word written by GMP
    discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

    var rConstantine: array[mLen, byte]
    exportRawUint(rConstantine, rTest, bigEndian)

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

main()
