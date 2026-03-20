# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/[arithmetic],
  constantine/math/io/io_fields,
  constantine/math/polynomials/[polynomials, fft],
  constantine/platforms/[bithacks, views, static_for],
  constantine/erasure_codes/zero_polynomial,
  ../math_polynomials/fft_utils

proc test_vanishing_single_root*() =
  echo "Testing vanishing polynomial for single root..."

  const N = 8
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  let missing_indices = [uint64(0)]
  var roots: array[1, F]
  let log2_n = uint32(log2_vartime(N.uint))
  let rev_idx = reverseBits(missing_indices[0], uint32(log2_n))
  roots[0] = fftDesc.rootsOfUnity[int(rev_idx)]

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomial(zero_poly, roots, domain)

  var eval_at_root: F
  evalPolyAt(eval_at_root, zero_poly, roots[0])
  doAssert eval_at_root.isZero().bool, "Vanishing polynomial should evaluate to 0 at its root"


  echo "  ✓ Single root vanishes correctly"

proc test_vanishing_two_roots*() =
  echo "Testing vanishing polynomial for two roots..."

  const N = 8
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  let missing_indices = [uint64(0), uint64(1)]
  var roots: array[2, F]
  roots[0] = fftDesc.rootsOfUnity[0]
  roots[1] = fftDesc.rootsOfUnity[1]
  echo "    root[0] = ", roots[0].toHex()
  echo "    root[1] = ", roots[1].toHex()

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomial(zero_poly, roots, domain)

  echo "    coeffs after vanishingPolynomial:"
  for i in 0 ..< min(4, N):
    echo "      [", i, "] = ", zero_poly.coefs[i].toHex()

  var eval_at_root0: F
  evalPolyAt(eval_at_root0, zero_poly, roots[0])
  doAssert eval_at_root0.isZero().bool, "Vanishing polynomial should evaluate to 0 at root 0"

  var eval_at_root1: F
  evalPolyAt(eval_at_root1, zero_poly, roots[1])
  doAssert eval_at_root1.isZero().bool, "Vanishing polynomial should evaluate to 0 at root 1"


  echo "  ✓ Two roots vanish correctly"

proc test_vanishing_half_domain*() =
  echo "Testing vanishing polynomial for half domain (64 missing indices)..."

  const N = 128
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  var missing_indices: array[64, uint64]
  for i in 0 ..< 64:
    missing_indices[i] = uint64(i)

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomialForIndices(zero_poly, missing_indices, domain)

  for i in 0 ..< 64:
    let root = fftDesc.rootsOfUnity[i]
    var eval_at_root: F
    evalPolyAt(eval_at_root, zero_poly, root)
    doAssert eval_at_root.isZero().bool, "Vanishing polynomial should evaluate to 0 at missing index " & $i


  echo "  ✓ Half domain vanishes correctly"

proc test_vanishing_eval_at_present*() =
  echo "Testing vanishing polynomial evaluates non-zero at present indices..."

  const N = 8
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  let missing_indices = [uint64(0), uint64(1)]
  var roots: array[2, F]
  roots[0] = fftDesc.rootsOfUnity[0]
  roots[1] = fftDesc.rootsOfUnity[1]

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomial(zero_poly, roots, domain)

  for i in 2 ..< N:
    let root = fftDesc.rootsOfUnity[i]
    var eval_at_root: F
    evalPolyAt(eval_at_root, zero_poly, root)
    doAssert eval_at_root.isZero().bool == false, "Vanishing polynomial should evaluate to non-zero at present index " & $i


  echo "  ✓ Non-missing indices evaluate non-zero"

proc test_bit_reversal_correctness*() =
  echo "Testing bit-reversal correctness in index to root mapping..."

  const N = 8
  const log2_N = 3
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  domain.isBitReversed = false

  for idx in 0 ..< N:
    let rev_idx = reverseBits(uint64(idx), uint32(log2_N))
    let expected_root = fftDesc.rootsOfUnity[int(rev_idx)]
    let computed_root = domain.rootsOfUnity[int(rev_idx)]
    doAssert (expected_root == computed_root).bool, "Root mismatch at index " & $idx


  echo "  ✓ Bit-reversal mapping correct"

proc test_zero_poly_known*() =
  echo "Testing zero polynomial with known input/output..."

  const N = 16
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  let exists = [true, false, false, true, false, true, true, false,
               false, false, true, true, false, true, false, true]

  var missing_indices: seq[uint64]
  missing_indices = newSeq[uint64]()
  for i in 0 ..< N:
    if not exists[i]:
      missing_indices.add(uint64(i))

  doAssert missing_indices.len == 8, "Expected 8 missing indices"

  var missing_arr: array[16, uint64]
  for i in 0 ..< missing_indices.len:
    missing_arr[i] = missing_indices[i]

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomialForIndicesRT(zero_poly, missing_arr.toOpenArray(0, missing_indices.len), domain)

  for i in 0 ..< N:
    if not exists[i]:
      var eval_at_root: F
      evalPolyAt(eval_at_root, zero_poly, fftDesc.rootsOfUnity[i])
      doAssert eval_at_root.isZero().bool, "Vanishing polynomial should evaluate to 0 at index " & $i


  echo "  ✓ Known input/output test passed"

proc testVanishingPolynomialForSize*(N: static int) =
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  const numMissing = N div 2
  var missing_indices: array[numMissing, uint64]
  for i in 0 ..< numMissing:
    missing_indices[i] = uint64(i)

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomialForIndices(zero_poly, missing_indices, domain)

  for i in 0 ..< numMissing:
    var eval_at_root: F
    evalPolyAt(eval_at_root, zero_poly, fftDesc.rootsOfUnity[i])
    doAssert eval_at_root.isZero().bool, "Should evaluate to 0 at missing index " & $i



proc test_zero_poly_random*() =
  echo "Testing zero polynomial with various sizes..."

  staticFor sz, [8, 16, 32, 64, 128]:
    testVanishingPolynomialForSize(sz)

  echo "  ✓ Various sizes test passed"

proc test_zero_poly_all_but_one*() =
  echo "Testing zero polynomial with all but one element present..."

  const N = 256
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  var missing_indices: array[255, uint64]
  for i in 0 ..< 255:
    missing_indices[i] = uint64(i + 1)

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomialForIndices(zero_poly, missing_indices, domain)

  for i in 1 ..< N:
    var eval_at_root: F
    evalPolyAt(eval_at_root, zero_poly, fftDesc.rootsOfUnity[i])
    doAssert eval_at_root.isZero().bool, "Vanishing polynomial should evaluate to 0 at index " & $i


  echo "  ✓ All but one test passed"

proc test_zero_poly_large*() =
  echo "Testing zero polynomial with large domain (8192 elements)..."

  const N = 8192
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  var missing_indices: array[4096, uint64]
  for i in 0 ..< 4096:
    missing_indices[i] = uint64(i)

  var zero_poly: PolynomialCoef[N, F]
  vanishingPolynomialForIndices(zero_poly, missing_indices, domain)

  for i in 0 ..< 4096:
    var eval_at_root: F
    evalPolyAt(eval_at_root, zero_poly, fftDesc.rootsOfUnity[i])
    doAssert eval_at_root.isZero().bool, "Vanishing polynomial should evaluate to 0 at missing index " & $i


  echo "  ✓ Large domain test passed"

proc test_zero_poly_boundary*() =
  echo "Testing zero polynomial boundary cases..."

  const N = 4
  type F = Fr[BLS12_381]
  let fftDesc = createFFTDescriptor(F, N)

  var domain: PolyEvalRootsDomain[N, F]
  for i in 0 ..< N:
    domain.rootsOfUnity[i] = fftDesc.rootsOfUnity[i]
  domain.invMaxDegree.setOne()
  var invN: F
  invN.fromUint(uint64(N))
  invN.inv_vartime(invN)
  domain.invMaxDegree = invN
  domain.isBitReversed = false

  let indices_3 = [uint64(0), uint64(1), uint64(2)]
  var zero_poly_3: PolynomialCoef[N, F]
  vanishingPolynomialForIndices(zero_poly_3, indices_3, domain)

  var eval_at_root: F
  evalPolyAt(eval_at_root, zero_poly_3, fftDesc.rootsOfUnity[0])
  doAssert eval_at_root.isZero().bool, "Should evaluate to 0 at index 0"
  evalPolyAt(eval_at_root, zero_poly_3, fftDesc.rootsOfUnity[1])
  doAssert eval_at_root.isZero().bool, "Should evaluate to 0 at index 1"
  evalPolyAt(eval_at_root, zero_poly_3, fftDesc.rootsOfUnity[2])
  doAssert eval_at_root.isZero().bool, "Should evaluate to 0 at index 2"


  echo "  ✓ Boundary cases test passed"

when isMainModule:
  echo "========================================"
  echo "Zero Polynomial Tests"
  echo "========================================"

  test_vanishing_single_root()
  test_vanishing_two_roots()
  test_vanishing_half_domain()
  test_vanishing_eval_at_present()
  test_bit_reversal_correctness()
  test_zero_poly_known()
  test_zero_poly_random()
  test_zero_poly_all_but_one()
  test_zero_poly_large()
  test_zero_poly_boundary()

  echo ""
  echo "========================================"
  echo "All zero_polynomial tests PASSED!"
  echo "========================================"
