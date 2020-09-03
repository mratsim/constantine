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
  ../constantine/io/[io_bigints, io_fields],
  ../constantine/arithmetic,
  ../constantine/primitives,
  ../constantine/config/curves

echo "\n------------------------------------------------------\n"

var RNG {.compileTime.} = initRand(1234)

const AvailableCurves = [
  P224,
  BN254_Nogami, BN254_Snarks,
  P256, Secp256k1,
  BLS12_381
]

const # https://gmplib.org/manual/Integer-Import-and-Export.html
  GMP_WordLittleEndian = -1'i32
  GMP_WordNativeEndian = 0'i32
  GMP_WordBigEndian = 1'i32

  GMP_MostSignificantWordFirst = 1'i32
  GMP_LeastSignificantWordFirst = -1'i32

# ############################################################
#
#                         Helpers
#
# ############################################################
#
# Factor common things in proc to avoid generating 100k+ lines of C code

proc binary_prologue[C: static Curve, N: static int](
        gmpRng: var gmp_randstate_t,
        a, b, p: var mpz_t,
        aTest, bTest: var Fp[C],
        aBuf, bBuf: var array[N, byte]) =
  const bits = C.getCurveBitwidth()

  # Generate random value in the range 0 ..< 2^(bits-1)
  mpz_urandomb(a, gmpRng, uint bits)
  mpz_urandomb(b, gmpRng, uint bits)
  # Set modulus to curve modulus
  let err = mpz_set_str(p, Curve(C).Mod.toHex(), 0)
  doAssert err == 0, "Error on prime for curve " & $Curve(C)

  #########################################################
  # Conversion buffers
  const len = (bits + 7) div 8

  static: doAssert N >= len

  var aW, bW: csize # Word written by GMP
  discard mpz_export(aBuf[0].addr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
  discard mpz_export(bBuf[0].addr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)

  # Since the modulus is using all bits, it's we can test for exact amount copy
  doAssert len >= aW, "Expected at most " & $len & " bytes but wrote " & $aW & " for " & toHex(aBuf) & " (big-endian)"
  doAssert len >= bW, "Expected at most " & $len & " bytes but wrote " & $bW & " for " & toHex(bBuf) & " (big-endian)"

  # Build the bigint - TODO more fields codecs
  aTest = Fp[C].fromBig BigInt[bits].fromRawUint(aBuf.toOpenArray(0, aW-1), bigEndian)
  bTest = Fp[C].fromBig BigInt[bits].fromRawUint(bBuf.toOpenArray(0, bW-1), bigEndian)

proc binary_epilogue[C: static Curve, N: static int](
        r, a, b: mpz_t,
        rTest: Fp[C],
        aBuf, bBuf: array[N, byte],
        operation: string
      ) =

  #########################################################
  # Check
  var rGMP: array[N, byte]
  var rW: csize # Word written by GMP
  discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

  var rConstantine: array[N, byte]
  exportRawUint(rConstantine, rTest, bigEndian)

  # Note: in bigEndian, GMP aligns left while constantine aligns right
  doAssert rGMP.toOpenArray(0, rW-1) == rConstantine.toOpenArray(N-rW, N-1), block:
    # Reexport as bigEndian for debugging
    var aW, bW: csize
    discard mpz_export(aBuf[0].unsafeAddr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
    discard mpz_export(bBuf[0].unsafeAddr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)
    "\nModular " & operation & " on curve " & $C & " with operands\n" &
    "  a:   " & aBuf.toHex & "\n" &
    "  b:   " & bBuf.toHex & "\n" &
    "failed:" & "\n" &
    "  GMP:            " & rGMP.toHex() & "\n" &
    "  Constantine:    " & rConstantine.toHex() & "\n" &
    "(Note that GMP aligns bytes left while constantine aligns bytes right)"

# ############################################################
#
#                   Test Definitions
#
# ############################################################

proc addTests(gmpRng: var gmp_randstate_t, a, b, p, r: var mpz_t, C: static Curve) =
  # echo "Testing: random modular addition on ", $C

  const
    bits = C.getCurveBitwidth()
    bufLen = (bits + 7) div 8
  var
    aTest, bTest{.noInit.}: Fp[C]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(gmpRng, a, b, p, aTest, bTest, aBuf, bBuf)

  mpz_add(r, a, b)
  mpz_mod(r, r, p)

  var rTest {.noInit.}: Fp[C]
  rTest.sum(aTest, bTest)

  var r2Test = aTest
  r2Test += bTest

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Addition (with result)")
  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Addition (in-place)")

proc subTests(gmpRng: var gmp_randstate_t, a, b, p, r: var mpz_t, C: static Curve) =
  # echo "Testing: random modular substraction on ", $C

  const
    bits = C.getCurveBitwidth()
    bufLen = (bits + 7) div 8
  var
    aTest, bTest{.noInit.}: Fp[C]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(gmpRng, a, b, p, aTest, bTest, aBuf, bBuf)

  mpz_sub(r, a, b)
  mpz_mod(r, r, p)

  var rTest {.noInit.}: Fp[C]
  rTest.diff(aTest, bTest)

  var r2Test = aTest
  r2Test -= bTest

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Substraction (with result)")
  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Substraction (in-place)")

proc mulTests(gmpRng: var gmp_randstate_t, a, b, p, r: var mpz_t, C: static Curve) =
  # echo "Testing: random modular multiplication on ", $C

  const
    bits = C.getCurveBitwidth()
    bufLen = (bits + 7) div 8
  var
    aTest, bTest{.noInit.}: Fp[C]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(gmpRng, a, b, p, aTest, bTest, aBuf, bBuf)

  mpz_mul(r, a, b)
  mpz_mod(r, r, p)

  var rTest {.noInit.}: Fp[C]
  rTest.prod(aTest, bTest)

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Multiplication")

proc invTests(gmpRng: var gmp_randstate_t, a, b, p, r: var mpz_t, C: static Curve) =
  # We use the binary prologue epilogue but the "b" parameter is actual unused
  # echo "Testing: random modular inversion on ", $C

  const
    bits = C.getCurveBitwidth()
    bufLen = (bits + 7) div 8
  var
    aTest, bTest{.noInit.}: Fp[C]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(gmpRng, a, b, p, aTest, bTest, aBuf, bBuf)

  let exist = mpz_invert(r, a, p)
  doAssert exist != 0

  var rTest {.noInit.}: Fp[C]
  rTest.inv(aTest)

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Inversion (b is unused)")

# ############################################################
#
#                   Test Runners
#
# ############################################################

macro randomTests(numTests: static int, curveSym, body: untyped): untyped =
  ## Generate `num` random tests at compile-time to test against GMP
  ## for A mod M
  result = newStmtList()

  for _ in 0 ..< numTests:
    let curve = RNG.sample(AvailableCurves)

    result.add quote do:
      block:
        const `curveSym` = Curve(`curve`)
        block:
          `body`

template testSetup {.dirty.} =
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

proc mainMul() =
  testSetup()
  echo "Testing modular multiplications vs GMP"
  randomTests(24, curve):
    mulTests(gmpRng, a, b, p, r, curve)

proc mainAdd() =
  testSetup()
  echo "Testing modular additions vs GMP"
  randomTests(24, curve):
    addTests(gmpRng, a, b, p, r, curve)

proc mainSub() =
  testSetup()
  echo "Testing modular substractions vs GMP"
  randomTests(24, curve):
    subTests(gmpRng, a, b, p, r, curve)

proc mainInv() =
  testSetup()
  echo "Testing modular inversions vs GMP"
  randomTests(24, curve):
    invTests(gmpRng, a, b, p, r, curve)


mainMul()
mainAdd()
mainSub()
mainInv()
