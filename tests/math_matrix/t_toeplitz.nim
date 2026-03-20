# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/ec_shortweierstrass,
  constantine/math/matrix/toeplitz,
  constantine/math/io/[io_fields, io_ec],
  constantine/math/arithmetic/finite_fields,
  ../math_polynomials/fft_utils

type BLS12_381_G1 = EC_ShortW_Prj[Fp[BLS12_381], G1]
type BLS12_381_Fr = Fr[BLS12_381]

proc toeplitzMatVecMulNaive(
  output: var openArray[BLS12_381_G1],
  coeffs: openArray[BLS12_381_Fr],
  input: openArray[BLS12_381_G1]
) {.raises: [].} =
  ## Naive O(n²) Toeplitz matrix-vector multiplication for testing.
  let n = input.len
  let n2 = coeffs.len
  doAssert output.len == n
  doAssert n2 == 2 * n

  for i in 0 ..< n:
    var sum: BLS12_381_G1
    sum.setNeutral()

    for j in 0 ..< n:
      let coeffIdx = if i >= j: i - j else: n2 - (j - i)
      var term: BLS12_381_G1
      term.scalarMul_vartime(coeffs[coeffIdx].toBig(), input[j])

      if j == 0:
        sum = term
      else:
        sum.sum_vartime(sum, term)

    output[i] = sum

proc testCheckCirculant() =
  echo "Testing checkCirculant validation..."

  const n = 4
  var poly = newSeq[Fr[BLS12_381]](n)
  var coeffs = newSeq[Fr[BLS12_381]](2 * n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)
  doAssert checkCirculant(coeffs, poly, 0, 1), "Valid circulant should pass"

  # Corrupt it
  coeffs[0].fromUint(999)
  doAssert not checkCirculant(coeffs, poly, 0, 1), "Corrupted circulant should fail"

  echo "✓ checkCirculant test PASSED"

proc testMakeCirculantMatrix() =
  echo "Testing makeCirculantMatrix..."

  const n = 4
  var poly = newSeq[Fr[BLS12_381]](n)
  var coeffs = newSeq[Fr[BLS12_381]](2 * n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)

  var zero: Fr[BLS12_381]
  zero.fromUint(0)

  doAssert coeffs[0].toHex() == poly[3].toHex(), "c[0] should be poly[3]"
  doAssert coeffs[1].toHex() == zero.toHex(), "c[1] should be 0"
  doAssert coeffs[2].toHex() == zero.toHex(), "c[2] should be 0"
  doAssert coeffs[3].toHex() == zero.toHex(), "c[3] should be 0"
  doAssert coeffs[4].toHex() == zero.toHex(), "c[4] should be 0"
  doAssert coeffs[5].toHex() == zero.toHex(), "c[5] should be 0"
  doAssert coeffs[6].toHex() == poly[1].toHex(), "c[6] should be poly[1]"
  doAssert coeffs[7].toHex() == poly[2].toHex(), "c[7] should be poly[2]"

  echo "✓ makeCirculantMatrix test PASSED"

proc testToeplitz4x4() =
  echo "Testing 4x4 Toeplitz matrix-vector multiplication..."

  let frFftDesc = createFFTDescriptor(Fr[BLS12_381], 8)

  let ecFftDesc = createFFTDescriptor(BLS12_381_G1, Fr[BLS12_381], 8)

  const n = 4
  var poly = newSeq[BLS12_381_Fr](n)
  var coeffs = newSeq[BLS12_381_Fr](2 * n)
  var input = newSeq[BLS12_381_G1](n)
  var outputNaive = newSeq[BLS12_381_G1](n)
  var outputFft = newSeq[BLS12_381_G1](n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)

  input[0].setGenerator()
  for i in 1 ..< n:
    input[i].mixedSum(input[i-1], BLS12_381.getGenerator("G1"))

  toeplitzMatVecMulNaive(outputNaive, coeffs, input)

  let status = toeplitzMatVecMul[BLS12_381_G1, BLS12_381_Fr](outputFft, coeffs, input, frFftDesc, ecFftDesc)
  doAssert status == FFT_Success, "FFT-based multiplication failed: " & $status

  for i in 0 ..< n:
    if bool(outputNaive[i] != outputFft[i]):
      echo "Error at index ", i
      echo "  Naive: ", outputNaive[i].toHex()
      echo "  FFT:   ", outputFft[i].toHex()
      quit 1

  echo "✓ 4x4 Toeplitz test PASSED"

proc testToeplitz8x8() =
  echo "Testing 8x8 Toeplitz matrix-vector multiplication..."

  let frFftDesc = createFFTDescriptor(Fr[BLS12_381], 16)

  let ecFftDesc = createFFTDescriptor(BLS12_381_G1, Fr[BLS12_381], 16)

  const n = 8
  var poly = newSeq[BLS12_381_Fr](n)
  var coeffs = newSeq[BLS12_381_Fr](2 * n)
  var input = newSeq[BLS12_381_G1](n)
  var outputNaive = newSeq[BLS12_381_G1](n)
  var outputFft = newSeq[BLS12_381_G1](n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)

  input[0].setGenerator()
  for i in 1 ..< n:
    input[i].mixedSum(input[i-1], BLS12_381.getGenerator("G1"))

  toeplitzMatVecMulNaive(outputNaive, coeffs, input)

  let status = toeplitzMatVecMul[BLS12_381_G1, BLS12_381_Fr](outputFft, coeffs, input, frFftDesc, ecFftDesc)
  doAssert status == FFT_Success, "FFT-based multiplication failed: " & $status

  for i in 0 ..< n:
    if bool(outputNaive[i] != outputFft[i]):
      echo "Error at index ", i
      echo "  Naive: ", outputNaive[i].toHex()
      echo "  FFT:   ", outputFft[i].toHex()
      quit 1

  echo "✓ 8x8 Toeplitz test PASSED"

when isMainModule:
  testCheckCirculant()
  testMakeCirculantMatrix()
  testToeplitz4x4()
  testToeplitz8x8()
  echo "\nAll Toeplitz tests PASSED ✓"