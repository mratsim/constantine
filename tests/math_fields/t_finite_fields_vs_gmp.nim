# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[random, macros, times],
  # Third-party
  gmp,
  # Internal
  constantine/platforms/abstractions,
  constantine/serialization/codecs,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/named/algebras,
  # Test utilities
  helpers/prng_unsafe

echo "\n------------------------------------------------------\n"

var RNG {.compileTime.} = initRand(1234)

const AvailableCurves = [
  P224,
  BN254_Nogami, BN254_Snarks,
  P256, Secp256k1, Edwards25519, Bandersnatch, Pallas, Vesta,
  BLS12_377, BLS12_381, BW6_761
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

proc binary_prologue[Name: static Algebra, N: static int](
        rng: var RngState,
        a, b, p: var mpz_t,
        aTest, bTest: var Fp[Name],
        aBuf, bBuf: var array[N, byte]) =

  # Build the field elements
  aTest = rng.random_unsafe(Fp[Name])
  bTest = rng.random_unsafe(Fp[Name])

  # Set modulus to curve modulus
  let err = mpz_set_str(p, Fp[Name].getModulus().toHex(), 0)
  doAssert err == 0, "Error on prime for curve " & $Name

  #########################################################
  # Conversion to GMP
  const aLen = Fp[Name].bits().ceilDiv_vartime(8)
  const bLen = Fp[Name].bits().ceilDiv_vartime(8)

  var aBuf: array[aLen, byte]
  var bBuf: array[bLen, byte]

  aBuf.marshal(aTest, bigEndian)
  bBuf.marshal(bTest, bigEndian)

  mpz_import(a, aLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, aBuf[0].addr)
  mpz_import(b, bLen, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, bBuf[0].addr)

proc binary_epilogue[Name: static Algebra, N: static int](
        r, a, b: mpz_t,
        rTest: Fp[Name],
        aBuf, bBuf: array[N, byte],
        operation: string
      ) =

  #########################################################
  # Check

  {.push warnings: off.} # deprecated csize
  var aW, bW, rW: csize  # Word written by GMP
  {.pop.}

  var rGMP: array[N, byte]
  discard mpz_export(rGMP[0].addr, rW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, r)

  var rConstantine: array[N, byte]
  marshal(rConstantine, rTest, bigEndian)

  # Note: in bigEndian, GMP aligns left while constantine aligns right
  doAssert rGMP.toOpenArray(0, rW-1) == rConstantine.toOpenArray(N-rW, N-1), block:
    # Reexport as bigEndian for debugging
    discard mpz_export(aBuf[0].unsafeAddr, aW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, a)
    discard mpz_export(bBuf[0].unsafeAddr, bW.addr, GMP_MostSignificantWordFirst, 1, GMP_WordNativeEndian, 0, b)
    "\nModular " & operation & " on curve " & $Name & " with operands\n" &
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

proc addTests(rng: var RngState, a, b, p, r: var mpz_t, Name: static Algebra) =
  # echo "Testing: random modular addition on ", $Name

  const
    bits = Fp[Name].bits
    bufLen = bits.ceilDiv_vartime(8)
  var
    aTest, bTest{.noInit.}: Fp[Name]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(rng, a, b, p, aTest, bTest, aBuf, bBuf)

  mpz_add(r, a, b)
  mpz_mod(r, r, p)

  var rTest {.noInit.}: Fp[Name]
  rTest.sum(aTest, bTest)

  var r2Test = aTest
  r2Test += bTest

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Addition (with result)")
  binary_epilogue(r, a, b, r2Test, aBuf, bBuf, "Addition (in-place)")

proc subTests(rng: var RngState, a, b, p, r: var mpz_t, Name: static Algebra) =
  # echo "Testing: random modular substraction on ", $Name

  const
    bits = Fp[Name].bits
    bufLen = bits.ceilDiv_vartime(8)
  var
    aTest, bTest{.noInit.}: Fp[Name]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(rng, a, b, p, aTest, bTest, aBuf, bBuf)

  mpz_sub(r, a, b)
  mpz_mod(r, r, p)

  var rTest {.noInit.}: Fp[Name]
  rTest.diff(aTest, bTest)

  var r2Test = aTest
  r2Test -= bTest

  # Substraction with r and b aliasing
  var r3Test = bTest
  r3Test.diff(aTest, r3Test)

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Substraction (with result)")
  binary_epilogue(r, a, b, r2Test, aBuf, bBuf, "Substraction (in-place)")
  binary_epilogue(r, a, b, r3Test, aBuf, bBuf, "Substraction (result aliasing)")

proc mulTests(rng: var RngState, a, b, p, r: var mpz_t, Name: static Algebra) =
  # echo "Testing: random modular multiplication on ", $Name

  const
    bits = Fp[Name].bits
    bufLen = bits.ceilDiv_vartime(8)
  var
    aTest, bTest{.noInit.}: Fp[Name]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(rng, a, b, p, aTest, bTest, aBuf, bBuf)

  mpz_mul(r, a, b)
  mpz_mod(r, r, p)

  var rTest {.noInit.}: Fp[Name]
  rTest.prod(aTest, bTest)

  var r2Test = aTest
  r2Test *= bTest

  binary_epilogue(r, a, b, rTest, aBuf, bBuf, "Multiplication (with result)")
  binary_epilogue(r, a, b, r2Test, aBuf, bBuf, "Multiplication (in-place)")

proc invTests(rng: var RngState, a, b, p, r: var mpz_t, Name: static Algebra) =
  # We use the binary prologue epilogue but the "b" parameter is actual unused
  # echo "Testing: random modular inversion on ", $Name

  const
    bits = Fp[Name].bits
    bufLen = bits.ceilDiv_vartime(8)
  var
    aTest, bTest{.noInit.}: Fp[Name]
    aBuf, bBuf: array[bufLen, byte]
  binary_prologue(rng, a, b, p, aTest, bTest, aBuf, bBuf)

  let exist = mpz_invert(r, a, p)
  doAssert exist != 0

  var rTest {.noInit.}: Fp[Name]
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
        const `curveSym` = Algebra(`curve`)
        block:
          `body`

template testSetup {.dirty.} =
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo "test_finite_fields_vs_gmp** seed: ", seed

  var a, b, p, r: mpz_t
  mpz_init(a)
  mpz_init(b)
  mpz_init(p)
  mpz_init(r)
  defer:
    mpz_clear(r)
    mpz_clear(p)
    mpz_clear(b)
    mpz_clear(a)

proc mainMul() =
  testSetup()
  echo "Testing modular multiplications vs GMP"
  randomTests(24, curve):
    mulTests(rng, a, b, p, r, curve)

proc mainAdd() =
  testSetup()
  echo "Testing modular additions vs GMP"
  randomTests(24, curve):
    addTests(rng, a, b, p, r, curve)

proc mainSub() =
  testSetup()
  echo "Testing modular substractions vs GMP"
  randomTests(24, curve):
    subTests(rng, a, b, p, r, curve)

proc mainInv() =
  testSetup()
  echo "Testing modular inversions vs GMP"
  randomTests(24, curve):
    invTests(rng, a, b, p, r, curve)


mainMul()
mainAdd()
mainSub()
mainInv()
