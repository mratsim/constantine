# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Run with
#   nim c -r -d:CTT_DEBUG -d:release --hints:off --warnings:off --outdir:build/wip --nimcache:nimcache/wip tests/math_matrix/t_toeplitz.nim

import
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/ec_shortweierstrass,
  constantine/math/matrix/toeplitz,
  constantine/math/io/[io_fields, io_ec],
  constantine/math/arithmetic/finite_fields,
  ../math_polynomials/fft_utils

type BLS12_381_G1_Prj = EC_ShortW_Prj[Fp[BLS12_381], G1]
type BLS12_381_Fr = Fr[BLS12_381]

proc toeplitzMatVecMulNaive(
  output: var openArray[BLS12_381_G1_Prj],
  coeffs: openArray[BLS12_381_Fr],
  input: openArray[BLS12_381_G1_Prj]
) {.raises: [].} =
  ## Naive O(n²) Toeplitz matrix-vector multiplication for testing.
  let n = input.len
  let n2 = coeffs.len
  doAssert output.len == n
  doAssert n2 == 2 * n

  for i in 0 ..< n:
    var sum: BLS12_381_G1_Prj
    sum.setNeutral()

    for j in 0 ..< n:
      let coeffIdx = if i >= j: i - j else: n2 - (j - i)
      var term: BLS12_381_G1_Prj
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

proc testToeplitz(n: static int) =
  ## Test Toeplitz matrix-vector multiplication for given size
  echo "Testing ", n, "x", n, " Toeplitz matrix-vector multiplication..."

  let fftSize = 2 * n
  let frFftDesc = createFFTDescriptor(Fr[BLS12_381], fftSize)
  let ecFftDesc = createFFTDescriptor(BLS12_381_G1_Prj, Fr[BLS12_381], fftSize)

  var poly = newSeq[BLS12_381_Fr](n)
  var coeffs = newSeq[BLS12_381_Fr](2 * n)
  var input = newSeq[BLS12_381_G1_Prj](n)
  var outputNaive = newSeq[BLS12_381_G1_Prj](n)
  var outputFft = newSeq[BLS12_381_G1_Prj](n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)

  input[0].setGenerator()
  for i in 1 ..< n:
    input[i].mixedSum(input[i-1], BLS12_381.getGenerator("G1"))

  toeplitzMatVecMulNaive(outputNaive, coeffs, input)

  let status = toeplitzMatVecMul[BLS12_381_G1_Prj, BLS12_381_Fr](outputFft, coeffs, input, frFftDesc, ecFftDesc)
  doAssert status == Toeplitz_Success, "FFT-based multiplication failed: " & $status

  for i in 0 ..< n:
    if bool(outputNaive[i] != outputFft[i]):
      echo "Error at index ", i
      echo "  Naive: ", outputNaive[i].toHex()
      echo "  FFT:   ", outputFft[i].toHex()
      quit 1
  echo "✓ ", n, "x", n, " Toeplitz test PASSED"

proc testToeplitzAccumulatorInitErrors() =
  echo "Testing ToeplitzAccumulator.init error paths..."
  type BLS12_381_G1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
  let fftSize = 128
  let frDesc = createFFTDescriptor(Fr[BLS12_381], fftSize)
  let ecDesc = createFFTDescriptor(BLS12_381_G1_Prj, Fr[BLS12_381], fftSize)

  var acc: ToeplitzAccumulator[BLS12_381_G1_Prj, BLS12_381_G1_aff, Fr[BLS12_381]]

  # size = 0 → Toeplitz_SizeNotPowerOfTwo
  doAssert acc.init(frDesc, ecDesc, size = 0, L = 1) == Toeplitz_SizeNotPowerOfTwo

  # L = 0 → Toeplitz_SizeNotPowerOfTwo
  doAssert acc.init(frDesc, ecDesc, size = 4, L = 0) == Toeplitz_SizeNotPowerOfTwo

  # non-power-of-2 → Toeplitz_SizeNotPowerOfTwo
  doAssert acc.init(frDesc, ecDesc, size = 6, L = 1) == Toeplitz_SizeNotPowerOfTwo

  # negative size
  doAssert acc.init(frDesc, ecDesc, size = -1, L = 1) == Toeplitz_SizeNotPowerOfTwo

  # Valid init should succeed
  doAssert acc.init(frDesc, ecDesc, size = 4, L = 2) == Toeplitz_Success
  # (acc will be destroyed on scope exit, freeing buffers)

  echo "✓ ToeplitzAccumulator.init errors PASSED"

proc testToeplitzAccumulatorFinishErrors() =
  echo "Testing ToeplitzAccumulator.finish error paths..."
  type G1Aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
  let fftSize = 128
  let frDesc = createFFTDescriptor(Fr[BLS12_381], fftSize)
  let ecDesc = createFFTDescriptor(BLS12_381_G1_Prj, Fr[BLS12_381], fftSize)

  var acc: ToeplitzAccumulator[BLS12_381_G1_Prj, G1Aff, Fr[BLS12_381]]
  doAssert acc.init(frDesc, ecDesc, size = 4, L = 2) == Toeplitz_Success

  # finish without any accumulate → Toeplitz_MismatchedSizes (offset != L)
  var output: array[4, BLS12_381_G1_Prj]
  var basisPts: array[4, array[2, G1Aff]]
  let basis = cast[ptr UncheckedArray[array[2, G1Aff]]](addr basisPts[0])
  doAssert acc.finish(output.toOpenArray(0, 3), basis.toOpenArray(0, 3)) == Toeplitz_MismatchedSizes

  echo "✓ ToeplitzAccumulator.finish errors PASSED"

proc testCheckCirculantR1() =
  echo "Testing checkCirculant with r=1 (circulant length 2)..."
  var poly = newSeq[Fr[BLS12_381]](2)  # n=2, so circulant = 2*r where r = CDS/2
  var circ = newSeq[Fr[BLS12_381]](2)  # 2*r = 2, so r=1

  poly[0].fromUint(1)
  poly[1].fromUint(2)

  makeCirculantMatrix(circ, poly, 0, 1)
  doAssert checkCirculant(circ, poly, 0, 1), "Valid r=1 circulant should pass"

  # Corrupt
  circ[0].fromUint(999)
  doAssert not checkCirculant(circ, poly, 0, 1), "Corrupted r=1 circulant should fail"

  echo "✓ checkCirculant r=1 PASSED"

when isMainModule:
  testToeplitzAccumulatorInitErrors()
  testToeplitzAccumulatorFinishErrors()
  testCheckCirculantR1()
  testCheckCirculant()
  testMakeCirculantMatrix()
  testToeplitz(4)
  testToeplitz(8)
  testToeplitz(16)
  echo "\nAll Toeplitz tests PASSED ✓"