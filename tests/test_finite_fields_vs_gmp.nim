# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  random, macros, times, strutils,
  # Third-party
  gmp, stew/byteutils,
  # Internal
  ../constantine/io/[io_bigints, io_fields],
  ../constantine/arithmetic/[finite_fields, bigints_checked],
  ../constantine/primitives/constant_time,
  ../constantine/config/curves

# We test up to 1024-bit, more is really slow

var RNG {.compileTime.} = initRand(1234)
const CurveParams = [
  BN254: (254, "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"),
  BLS12_381: (381, "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab")
]

macro randomTests(numTests: static int, curveSym, body: untyped): untyped =
  ## Generate `num` random tests at compile-time to test against GMP
  ## for A mod M
  result = newStmtList()

  for _ in 0 ..< numTests:
    let curve = RNG.rand([BN254, BLS12_381])

    result.add quote do:
      block:
        const `curveSym` = Curve(`curve`)
        block:
          `body`

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian = -1'i32
  GMP_WordNativeEndian = 0'i32
  GMP_WordBigEndian = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst = -1'i32

proc mainMul() =
  var gmpRng: gmp_randstate_t
  gmp_randinit_mt(gmpRng)
  # The GMP seed varies between run so that
  # test coverage increases as the library gets tested.
  # This requires to dump the seed in the console or the function inputs
  # to be able to reproduce a bug
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  echo "GMP seed: ", seed
  gmp_randseed_ui(gmpRng, seed)

  var a, b, p, r: mpz_t
  mpz_init(a)
  mpz_init(b)
  mpz_init(p)
  mpz_init(r)

  randomTests(128, curve):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: random modular multiplication on ", $curve

    const bits = CurveParams[curve][0]

    # Generate random value in the range 0 ..< 2^(bits-1)
    mpz_urandomb(a, gmpRng, uint bits)
    mpz_urandomb(b, gmpRng, uint bits)
    # Set modulus to curve modulus
    let err = mpz_set_str(p, CurveParams[curve][1], 0)
    doAssert err == 0

    #########################################################
    # Conversion buffers
    const len = csize (bits + 7) div 8

    var aBuf: array[len, byte]
    var bBuf: array[len, byte]

    var aW, bW: csize # Word written by GMP

    discard mpz_export(aBuf[0].addr, aW.addr, GMP_LeastSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
    discard mpz_export(bBuf[0].addr, bW.addr, GMP_LeastSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)

    # Since the modulus is using all bits, it's we can test for exact amount copy
    doAssert len >= aW, "Expected at most " & $len & " bytes but wrote " & $aW & " for " & toHex(aBuf) & " (little-endian)"
    doAssert len >= bW, "Expected at most " & $len & " bytes but wrote " & $bW & " for " & toHex(bBuf) & " (little-endian)"

    # Build the bigint - TODO more fields codecs
    let aTest = Fq[curve].fromBig BigInt[bits].fromRawUint(aBuf, littleEndian)
    let bTest = Fq[curve].fromBig BigInt[bits].fromRawUint(bBuf, littleEndian)

    #########################################################
    # Modular multiplication
    mpz_mul(r, a, b)
    mpz_mod(r, r, p)

    let rTest = aTest * bTest

    #########################################################
    # Check
    var rGMP: array[len, byte]
    var rW: csize # Word written by GMP
    discard mpz_export(rGMP[0].addr, rW.addr, GMP_LeastSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

    var rConstantine: array[len, byte]
    exportRawUint(rConstantine, rTest, littleEndian)

    # echo "rGMP: ", rGMP.toHex()
    # echo "rConstantine: ", rConstantine.toHex()

    doAssert rGMP == rConstantine, block:
      # Reexport as bigEndian for debugging
      discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
      discard mpz_export(bBuf[0].addr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)
      "\nModular Multiplication on curve " & $curve & " with operand\n" &
      "  a:   " & aBuf.toHex & "\n" &
      "  b:   " & bBuf.toHex & "\n" &
      "failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rConstantine.toHex()

proc mainInv() =
  var gmpRng: gmp_randstate_t
  gmp_randinit_mt(gmpRng)
  # The GMP seed varies between run so that
  # test coverage increases as the library gets tested.
  # This requires to dump the seed in the console or the function inputs
  # to be able to reproduce a bug
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  echo "GMP seed: ", seed
  gmp_randseed_ui(gmpRng, seed)

  var a, p, r: mpz_t
  mpz_init(a)
  mpz_init(p)
  mpz_init(r)

  randomTests(128, curve):
    # echo "--------------------------------------------------------------------------------"
    echo "Testing: random modular inversion on ", $curve

    const bits = CurveParams[curve][0]

    # Generate random value in the range 0 ..< 2^(bits-1)
    mpz_urandomb(a, gmpRng, uint bits)
    # Set modulus to curve modulus
    let err = mpz_set_str(p, CurveParams[curve][1], 0)
    doAssert err == 0

    #########################################################
    # Conversion buffers
    const len = csize (bits + 7) div 8

    # Note: GMP does not pad right the bigendian numbers if there is extra space
    var aBuf: array[len, byte]

    var aW: csize # Word written by GMP
    discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)

    # Since the modulus is using all bits, it's we can test for exact amount copy
    doAssert len >= aW, "Expected at most " & $len & " bytes but wrote " & $aW & " for " & toHex(aBuf) & " (little-endian)"

    # Build the bigint - TODO more fields codecs
    let aTest = Fq[curve].fromBig BigInt[bits].fromRawUint(aBuf[0 ..< aW], bigEndian)

    #########################################################
    # Modular inversion
    let exist = mpz_invert(r, a, p)
    doAssert exist != 0

    var rTest = aTest
    rTest.inv()

    #########################################################
    # Check
    var rGMP: array[len, byte]
    var rW: csize # Word written by GMP
    discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

    var rConstantine: array[len, byte]
    exportRawUint(rConstantine, rTest, bigEndian)

    # echo "rGMP: ", rGMP.toHex()
    # echo "rConstantine: ", rConstantine.toHex()

    doAssert rGMP[0 ..< rW] == rConstantine[^rW..^1], block:
      # Reexport as bigEndian for debugging
      discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
      "\nModular Inversion on curve " & $curve & " with operand\n" &
      "  a:   0x" & aBuf.toHex & "\n" &
      "  p:   " & CurveParams[curve][1] & "\n" &
      "failed:" & "\n" &
      "  GMP:            " & rGMP.toHex() & "\n" &
      "  Constantine:    " & rConstantine.toHex()

mainMul()
mainInv()
