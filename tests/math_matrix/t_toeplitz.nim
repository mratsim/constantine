# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../constantine/named/algebras,
  ../../constantine/named/zoo_generators,
  ../../constantine/math/ec_shortweierstrass,
  ../../constantine/math/polynomials/fft,
  ../../constantine/math/matrix/toeplitz,
  ../../constantine/math/io/[io_fields, io_ec],
  ../../constantine/math/arithmetic/finite_fields

type EC_G1 = EC_ShortW_Prj[Fp[BLS12_381], G1]
type F = Fr[BLS12_381]

proc toeplitzMatVecMulNaive(
  output: var openArray[EC_G1],
  coeffs: openArray[F],
  input: openArray[EC_G1]
) {.raises: [].} =
  ## Naive O(n²) Toeplitz matrix-vector multiplication for testing.
  let n = input.len
  let n2 = coeffs.len
  doAssert output.len == n
  doAssert n2 == 2 * n

  for i in 0 ..< n:
    var sum: EC_G1
    sum.setNeutral()

    for j in 0 ..< n:
      let coeffIdx = if i >= j: i - j else: n2 - (j - i)
      var term: EC_G1
      term.scalarMul_vartime(coeffs[coeffIdx].toBig(), input[j])

      if j == 0:
        sum = term
      else:
        sum.sum_vartime(sum, term)

    output[i] = sum

const ctt_eth_kzg_fr_pow2_roots_of_unity = [
  Fr[BLS12_381].fromHex"0x1",
  Fr[BLS12_381].fromHex"0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000",
  Fr[BLS12_381].fromHex"0x8d51ccce760304d0ec030002760300000001000000000000",
  Fr[BLS12_381].fromHex"0x345766f603fa66e78c0625cd70d77ce2b38b21c28713b7007228fd3397743f7a",
  Fr[BLS12_381].fromHex"0x20b1ce9140267af9dd1c0af834cec32c17beb312f20b6f7653ea61d87742bcce",
  Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e",
  Fr[BLS12_381].fromHex"0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53",
  Fr[BLS12_381].fromHex"0x6898111413588742b7c68b4d7fdd60d098d0caac87f5713c5130c2c1660125be",
  Fr[BLS12_381].fromHex"0x4f9b4098e2e9f12e6b368121ac0cf4ad0a0865a899e8deff4935bd2f817f694b",
  Fr[BLS12_381].fromHex"0x95166525526a65439feec240d80689fd697168a3a6000fe4541b8ff2ee0434e",
  Fr[BLS12_381].fromHex"0x325db5c3debf77a18f4de02c0f776af3ea437f9626fc085e3c28d666a5c2d854",
  Fr[BLS12_381].fromHex"0x6d031f1b5c49c83409f1ca610a08f16655ea6811be9c622d4a838b5d59cd79e5",
  Fr[BLS12_381].fromHex"0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306",
  Fr[BLS12_381].fromHex"0x485d512737b1da3d2ccddea2972e89ed146b58bc434906ac6fdd00bfc78c8967",
  Fr[BLS12_381].fromHex"0x56624634b500a166dc86b01c0d477fa6ae4622f6a9152435034d2ff22a5ad9e1",
  Fr[BLS12_381].fromHex"0x3291357ee558b50d483405417a0cbe39c8d5f51db3f32699fbd047e11279bb6e",
  Fr[BLS12_381].fromHex"0x2155379d12180caa88f39a78f1aeb57867a665ae1fcadc91d7118f85cd96b8ad",
  Fr[BLS12_381].fromHex"0x224262332d8acbf4473a2eef772c33d6cd7f2bd6d0711b7d08692405f3b70f10",
  Fr[BLS12_381].fromHex"0x2d3056a530794f01652f717ae1c34bb0bb97a3bf30ce40fd6f421a7d8ef674fb",
  Fr[BLS12_381].fromHex"0x520e587a724a6955df625e80d0adef90ad8e16e84419c750194e8c62ecb38d9d",
  Fr[BLS12_381].fromHex"0x3e1c54bcb947035a57a6e07cb98de4a2f69e02d265e09d9fece7e0e39898d4b",
  Fr[BLS12_381].fromHex"0x47c8b5817018af4fc70d0874b0691d4e46b3105f04db5844cd3979122d3ea03a",
  Fr[BLS12_381].fromHex"0xabe6a5e5abcaa32f2d38f10fbb8d1bbe08fec7c86389beec6e7a6ffb08e3363",
  Fr[BLS12_381].fromHex"0x73560252aa0655b25121af06a3b51e3cc631ffb2585a72db5616c57de0ec9eae",
  Fr[BLS12_381].fromHex"0x291cf6d68823e6876e0bcd91ee76273072cf6a8029b7d7bc92cf4deb77bd779c",
  Fr[BLS12_381].fromHex"0x19fe632fd3287390454dc1edc61a1a3c0ba12bb3da64ca5ce32ef844e11a51e",
  Fr[BLS12_381].fromHex"0xa0a77a3b1980c0d116168bffbedc11d02c8118402867ddc531a11a0d2d75182",
  Fr[BLS12_381].fromHex"0x23397a9300f8f98bece8ea224f31d25db94f1101b1d7a628e2d0a7869f0319ed",
  Fr[BLS12_381].fromHex"0x52dd465e2f09425699e276b571905a7d6558e9e3f6ac7b41d7b688830a4f2089",
  Fr[BLS12_381].fromHex"0xc83ea7744bf1bee8da40c1ef2bb459884d37b826214abc6474650359d8e211b",
  Fr[BLS12_381].fromHex"0x2c6d4e4511657e1e1339a815da8b398fed3a181fabb30adc694341f608c9dd56",
  Fr[BLS12_381].fromHex"0x4b5371495990693fad1715b02e5713b5f070bb00e28a193d63e7cb4906ffc93f"
]

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

  let frFftDesc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = 8, ctt_eth_kzg_fr_pow2_roots_of_unity[3])
  defer: frFftDesc.delete()

  let ecFftDesc = ECFFT_Descriptor[EC_G1].new(order = 8, ctt_eth_kzg_fr_pow2_roots_of_unity[3])
  defer: ecFftDesc.delete()

  const n = 4
  var poly = newSeq[F](n)
  var coeffs = newSeq[F](2 * n)
  var input = newSeq[EC_G1](n)
  var outputNaive = newSeq[EC_G1](n)
  var outputFft = newSeq[EC_G1](n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)

  input[0].setGenerator()
  for i in 1 ..< n:
    input[i].mixedSum(input[i-1], BLS12_381.getGenerator("G1"))

  toeplitzMatVecMulNaive(outputNaive, coeffs, input)

  let status = toeplitzMatVecMul[EC_G1, F](outputFft, coeffs, input, frFftDesc, ecFftDesc)
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

  let frFftDesc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = 16, ctt_eth_kzg_fr_pow2_roots_of_unity[4])
  defer: frFftDesc.delete()

  let ecFftDesc = ECFFT_Descriptor[EC_G1].new(order = 16, ctt_eth_kzg_fr_pow2_roots_of_unity[4])
  defer: ecFftDesc.delete()

  const n = 8
  var poly = newSeq[F](n)
  var coeffs = newSeq[F](2 * n)
  var input = newSeq[EC_G1](n)
  var outputNaive = newSeq[EC_G1](n)
  var outputFft = newSeq[EC_G1](n)

  for i in 0 ..< n:
    poly[i].fromUint((i + 1).uint64)

  makeCirculantMatrix(coeffs, poly, 0, 1)

  input[0].setGenerator()
  for i in 1 ..< n:
    input[i].mixedSum(input[i-1], BLS12_381.getGenerator("G1"))

  toeplitzMatVecMulNaive(outputNaive, coeffs, input)

  let status = toeplitzMatVecMul[EC_G1, F](outputFft, coeffs, input, frFftDesc, ecFftDesc)
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