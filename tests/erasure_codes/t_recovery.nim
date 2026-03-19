# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[random, options],
  constantine/named/algebras,
  constantine/math/[arithmetic],
  constantine/math/io/io_fields,
  constantine/math/polynomials/[polynomials, fft],
  constantine/platforms/[bithacks, views],
  constantine/erasure_codes/[zero_polynomial, recovery],
  ../math_polynomials/fft_utils

{.push raises:[].}

proc createDomain*(F: typedesc[Fr], N: static int): PolyEvalRootsDomain[N, F] =
  let fftDesc = createFFTDescriptor(F, N)
  for i in 0 ..< N:
    result.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  result.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  result.invMaxDegree = invN
  result.isBitReversed = false

proc test_simple_4_elements*() =
  echo "Testing simple recovery with 4 elements (samples [0, None, None, 3])..."

  const N = 4
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i))
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  samples[0] = some(data[0])
  samples[1] = none(F)
  samples[2] = none(F)
  samples[3] = some(data[3])

  var recovered_poly: PolynomialCoef[N, F]
  let recover_status = recoverPolyFromSamples(recovered_poly, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered_poly.coefs[i] == poly[i]).bool,
      "Recovered coeff at index " & $i & " doesn't match"

  let fftDesc2 = createFFTDescriptor(F, N)
  var recovered_data: array[N, F]
  let fft_status2 = fft_nr(fftDesc2, recovered_data, recovered_poly.coefs)
  doAssert fft_status2 == FFT_Success

  for i in 0 ..< N:
    doAssert (recovered_data[i] == data[i]).bool,
      "Recovered data at index " & $i & " doesn't match"

  echo "  ✓ Simple 4 elements recovery works"

proc test_simple_half_missing*() =
  echo "Testing recovery with exactly half available..."

  const N = 8
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i))
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< N:
    if i >= N div 2:
      samples[i] = some(data[i])
    else:
      samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ Half available recovery works"

proc test_random_50_percent*() =
  echo "Testing recovery with 50% random available..."

  const N = 16
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) + 1)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< N:
    if i mod 2 == 0:
      samples[i] = some(data[i])
    else:
      samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 50% random recovery works"

proc test_random_55_percent*() =
  echo "Testing recovery with 55% available..."

  const N = 16
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) * 7 + 3)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< 9:
    samples[i] = some(data[i])
  for i in 9 ..< N:
    samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 55% recovery works"

proc test_random_60_percent*() =
  echo "Testing recovery with 60% available..."

  const N = 16
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) * 13 + 5)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< 10:
    samples[i] = some(data[i])
  for i in 10 ..< N:
    samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 60% recovery works"

proc test_random_70_percent*() =
  echo "Testing recovery with 70% available..."

  const N = 16
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) * 17 + 7)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< 12:
    samples[i] = some(data[i])
  for i in 12 ..< N:
    samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 70% recovery works"

proc test_random_80_percent*() =
  echo "Testing recovery with 80% available..."

  const N = 16
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) * 19 + 11)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< 13:
    samples[i] = some(data[i])
  for i in 13 ..< N:
    samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 80% recovery works"

proc test_random_90_percent*() =
  echo "Testing recovery with 90% available..."

  const N = 16
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) * 23 + 13)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< 15:
    samples[i] = some(data[i])
  for i in 15 ..< N:
    samples[i] = none(F)

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 90% recovery works"

proc test_random_100_percent*() =
  echo "Testing with all samples available (no recovery needed)..."

  const N = 8
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) + 1)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< N:
    samples[i] = some(data[i])

  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_Success, "Recovery failed: " & $recover_status

  for i in 0 ..< N:
    doAssert (recovered.evals[i] == data[i]).bool,
      "Recovered value at index " & $i & " doesn't match"

  echo "  ✓ 100% available works"

proc test_boundary_under_50*() =
  echo "Testing that recovery fails with under 50% available..."

  const N = 8
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) + 1)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  for i in 0 ..< 3:
    samples[i] = some(data[i])
  for i in 3 ..< N:
    samples[i] = none(F)

  # This should return Recovery_TooFewSamples
  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_TooFewSamples,
    "Expected Recovery_TooFewSamples, got: " & $recover_status
  echo "  ✓ Correctly rejected under 50% samples"

proc test_boundary_single_sample*() =
  echo "Testing that recovery fails with single sample..."

  const N = 8
  type F = Fr[BLS12_381]
  let domain = createDomain(F, N)

  var poly: array[N, F]
  for i in 0 ..< N div 2:
    poly[i].fromUint(uint64(i) + 1)
  for i in N div 2 ..< N:
    poly[i].setZero()

  let fftDesc = createFFTDescriptor(F, N)
  var data: array[N, F]
  let fft_status = fft_nr(fftDesc, data, poly)
  doAssert fft_status == FFT_Success


  var samples: array[N, Option[F]]
  samples[0] = some(data[0])
  for i in 1 ..< N:
    samples[i] = none(F)

  # This should return Recovery_TooFewSamples
  var recovered: PolynomialEval[N, F]
  let recover_status = recoverEvalsFromSamples(recovered, samples, domain)
  doAssert recover_status == Recovery_TooFewSamples,
    "Expected Recovery_TooFewSamples, got: " & $recover_status
  echo "  ✓ Correctly rejected single sample"

when isMainModule:
  echo "========================================"
  echo "Recovery Tests"
  echo "========================================"

  test_simple_4_elements()
  test_simple_half_missing()
  test_random_50_percent()
  test_random_55_percent()
  test_random_60_percent()
  test_random_70_percent()
  test_random_80_percent()
  test_random_90_percent()
  test_random_100_percent()
  test_boundary_under_50()
  test_boundary_single_sample()

  echo ""
  echo "========================================"
  echo "All recovery tests completed!"
  echo "========================================"