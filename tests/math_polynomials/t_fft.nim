# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# FFT/IFFT Roundtrip Tests
#
# Critical for FK20 multi-proof verification where L=2 uses ω=-1 (2nd root).
# The IFFT must correctly invert the FFT for ALL root orders, not just 4th roots
# where negation happens to equal inversion (ω = i, -i = i^{-1}).

# Compile and run with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/math_polynomials/t_fft.nim

import
  ../../constantine/named/algebras,
  ../../constantine/named/zoo_generators,
  ../../constantine/math/[arithmetic, ec_shortweierstrass],
  ../../constantine/math/polynomials/fft_fields {.all.},
  ../../constantine/math/polynomials/fft_ec {.all.},
  ../../constantine/math/io/io_fields,
  ./fft_utils

proc testBitReversal*(T: typedesc) =
  echo "Testing bit-reversal permutation..."

  # Test small sizes
  for logN in 1 .. 10:
    let N = 1 shl logN

    var src = newSeq[T](N)
    for i in 0 ..< N:
      src[i] = T(i)

    var dst = newSeq[T](N)
    bit_reversal_permutation(dst, src)

    # Verify each element is in correct bit-reversed position
    for i in 0 ..< N:
      let rev_i = reverseBits(uint i, uint logN)
      doAssert dst[i] == T(rev_i),
        "Bit-reversal failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $dst[i].int & ")"

  # Test in-place version
  for logN in 1 .. 10:
    let N = 1 shl logN

    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i)

    buf.bit_reversal_permutation()

    for i in 0 ..< N:
      let rev_i = reverseBits(uint i, uint logN)
      doAssert buf[i] == T(rev_i),
        "In-place bit-reversal failed at logN=" & $logN & " index=" & $i

  # Test involution property: applying bit-reversal twice returns to original
  echo "  Testing involution property (BRP(BRP(x)) = x)..."
  for logN in 1 .. 12:
    let N = 1 shl logN

    # Test out-of-place version
    var src = newSeq[T](N)
    for i in 0 ..< N:
      src[i] = T(i + 1)  # Use i+1 to avoid all zeros

    var pass1 = newSeq[T](N)
    var pass2 = newSeq[T](N)

    bit_reversal_permutation(pass1, src)
    bit_reversal_permutation(pass2, pass1)

    for i in 0 ..< N:
      doAssert pass2[i] == src[i],
        "Out-of-place involution failed at logN=" & $logN & " index=" & $i &
        " (expected " & $src[i].int & " but got " & $pass2[i].int & ")"

    # Test in-place version
    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i + 1)

    buf.bit_reversal_permutation()
    buf.bit_reversal_permutation()

    for i in 0 ..< N:
      doAssert buf[i] == T(i + 1),
        "In-place involution failed at logN=" & $logN & " index=" & $i

  echo "  ✓ All bit-reversal tests PASSED"

proc testFrFFTRoundtrip*(F: typedesc[Fr]) =
  echo "Testing Fr FFT/IFFT roundtrip..."

  for scale in 1 .. 5:
    let order = 1 shl scale
    let fftDesc = createFFTDescriptor(F, order)

    block:
      var data = newSeq[F](order)
      for i in 0 ..< order:
        data[i].fromUint(uint64(i + 1))

      var freq = newSeq[F](order)
      let fftOk = fft_nn(fftDesc, freq, data)
      doAssert fftOk == FFT_Success

      var recovered = newSeq[F](order)
      let ifftOk = ifft_nn(fftDesc, recovered, freq)
      doAssert ifftOk == FFT_Success

      if order == 2:
        echo "  === Size 2 Debug ==="
        echo "  FFT: [", freq[0].toHex(), ", ", freq[1].toHex(), "]"
        echo "  IFFT: [", recovered[0].toHex(), ", ", recovered[1].toHex(), "]"

      for i in 0 ..< order:
        doAssert (recovered[i] == data[i]).bool,
          "Roundtrip failed at size " & $order & " index " & $i

  echo "  ✓ All Fr FFT/IFFT roundtrip tests PASSED"

proc testECFFTRoundtrip*(EC: typedesc, F: typedesc[Fr]) =
  echo "Testing EC FFT/IFFT roundtrip..."

  for scale in 2 .. 5:
    let order = 1 shl scale

    let fftDesc = createFFTDescriptor(EC, F, order)

    var data = newSeq[EC](order)
    data[0].setGenerator()
    let gen = EC.F.Name.getGenerator($EC.G)
    for i in 1 ..< order:
      data[i].mixedSum(data[i-1], gen)

    var freq = newSeq[EC](order)
    let fftOk = ec_fft_nn(fftDesc, freq, data)
    doAssert fftOk == FFT_Success

    var recovered = newSeq[EC](order)
    let ifftOk = ec_ifft_nn(fftDesc, recovered, freq)
    doAssert ifftOk == FFT_Success

    for i in 0 ..< order:
      doAssert (recovered[i] == data[i]).bool,
        "EC Roundtrip failed at size " & $order & " index " & $i

  echo "  ✓ All EC FFT/IFFT roundtrip tests PASSED"

proc testIFFTInterpolation*(F: typedesc[Fr]) =
  echo "Testing IFFT interpolation correctness..."

  block:
    let L = 2
    let fftDesc = createFFTDescriptor(F, L)
    let omegaL = fftDesc.rootsOfUnity[1]

    var ys: array[2, F]
    ys[0].fromUint(142'u64)
    ys[1].fromHex("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfefffffffeffffffff")

    var v0_expected, v1_expected: F
    var sum_ys, two_inv, omega_inv: F
    sum_ys.sum(ys[0], ys[1])
    two_inv.fromUint(2'u64)
    two_inv.inv()
    omega_inv.inv(omegaL)
    v0_expected.prod(sum_ys, two_inv)

    var y1_times_omega_inv: F
    y1_times_omega_inv.prod(ys[1], omega_inv)
    v1_expected.sum(ys[0], y1_times_omega_inv)
    v1_expected.prod(v1_expected, two_inv)

    var coeffs: array[2, F]
    let status = ifft_nn(fftDesc, coeffs.toOpenArray(0, L-1), ys.toOpenArray(0, L-1))
    doAssert status == FFT_Success

    doAssert (coeffs[0] == v0_expected).bool, "IFFT coefficient 0 mismatch for L=2"
    doAssert (coeffs[1] == v1_expected).bool, "IFFT coefficient 1 mismatch for L=2"

    var v_at_1, v_at_omegaL: F
    v_at_1.sum(coeffs[0], coeffs[1])
    v_at_omegaL.diff(coeffs[0], coeffs[1])

    doAssert (v_at_1 == ys[0]).bool, "Interpolation at 1 failed"
    doAssert (v_at_omegaL == ys[1]).bool, "Interpolation at ω_L failed"

  block:
    let L = 4
    let fftDesc = createFFTDescriptor(F, L)
    let omegaL = fftDesc.rootsOfUnity[1]

    var ys: array[4, F]
    ys[0].fromUint(10'u64)
    ys[1].fromUint(20'u64)
    ys[2].fromUint(30'u64)
    ys[3].fromUint(40'u64)

    var ys_bitrev: array[4, F]
    for i in 0..<4:
      let rev_i = reverseBits(uint32(i), 2'u32)
      ys_bitrev[rev_i] = ys[i]

    var coeffs: array[4, F]
    let status = ifft_nn(fftDesc, coeffs.toOpenArray(0, L-1), ys.toOpenArray(0, L-1))
    doAssert status == FFT_Success

    var evals: array[4, F]
    let fftStatus = fft_nn(fftDesc, evals.toOpenArray(0, L-1), coeffs.toOpenArray(0, L-1))
    doAssert fftStatus == FFT_Success

    for i in 0..<4:
      doAssert (evals[i] == ys[i]).bool, "Re-evaluation at ω^" & $i & " failed for L=4"

  echo "  ✓ IFFT interpolation test PASSED"

proc naiveDFT[F](vals: openArray[F], omega: F): seq[F] =
  ## Compute DFT using naive O(n²) algorithm - produces natural order output
  result = newSeq[F](vals.len)

  for k in 0..<vals.len:
    var sum: F
    sum.setZero()

    var wkj: F
    wkj.setOne()   # ω^(k*0)

    var wk: F
    wk.setOne()
    for _ in 0..<k:
      wk *= omega  # ω^k

    for j in 0..<vals.len:
      var term: F
      term.prod(vals[j], wkj)
      sum += term
      wkj *= wk    # ω^(k*(j+1))

    result[k] = sum

proc testFFTOrdering*(F: typedesc[Fr]) =
  echo "Testing FFT output ordering..."

  for order in [4, 8]:
    let fftDesc = createFFTDescriptor(F, order)
    let omega = fftDesc.rootsOfUnity[1]

    var vals = newSeq[F](order)
    for i in 0..<order:
      vals[i].fromUint(uint64(i + 1))

    let naive = naiveDFT(vals, omega)

    var output_nn = newSeq[F](order)
    var output_nr = newSeq[F](order)
    discard fft_nn(fftDesc, output_nn, vals)
    discard fft_nr(fftDesc, output_nr, vals)

    var nn_is_natural = true
    for i in 0..<order:
      if not (output_nn[i] == naive[i]).bool:
        nn_is_natural = false
        break

    var nr_is_bitrev = true
    let log2_order = order.uint64.log2_vartime()
    for i in 0..<order:
      let br_i = reverseBits(uint(i), log2_order)
      if not (output_nr[i] == naive[br_i]).bool:
        nr_is_bitrev = false
        break

    doAssert nn_is_natural, "fft_nn should produce natural order (N=" & $order & ")"
    doAssert nr_is_bitrev, "fft_nr should produce bit-reversed order (N=" & $order & ")"

  echo "  ✓ FFT ordering tests PASSED"

proc testECFFTOrdering*(EC: typedesc, F: typedesc[Fr]) =
  echo "Testing EC FFT output ordering..."

  for order in [4, 8]:
    let fftDesc = createFFTDescriptor(EC, F, order)

    var vals = newSeq[EC](order)
    vals[0].setGenerator()
    let gen = EC.F.Name.getGenerator($EC.G)
    for i in 1..<order:
      vals[i].mixedSum(vals[i-1], gen)

    var output_nn = newSeq[EC](order)
    var output_nr = newSeq[EC](order)
    discard ec_fft_nn(fftDesc, output_nn, vals)
    discard ec_fft_nr(fftDesc, output_nr, vals)

    for i in 0..<order:
      let br_i = reverseBits(uint(i), order.uint64.log2_vartime())
      doAssert (output_nr[i] == output_nn[br_i]).bool,
        "EC fft_nr should produce bit-reversed of fft_nn (N=" & $order & ")"

  echo "  ✓ EC FFT ordering tests PASSED"

proc testIFFTOrdering*(F: typedesc[Fr]) =
  echo "Testing IFFT input/output ordering..."

  for order in [4, 8]:
    let fftDesc = createFFTDescriptor(F, order)

    var vals = newSeq[F](order)
    for i in 0..<order:
      vals[i].fromUint(uint64(i + 1))

    var freq_nn = newSeq[F](order)
    discard fft_nn(fftDesc, freq_nn, vals)

    var recovered_nn = newSeq[F](order)
    discard ifft_nn(fftDesc, recovered_nn, freq_nn)

    for i in 0..<order:
      doAssert (recovered_nn[i] == vals[i]).bool,
        "ifft_nn(fft_nn(x)) should equal x (N=" & $order & ")"

    var freq_nr = newSeq[F](order)
    let fftNrStatus = fft_nr(fftDesc, freq_nr, vals)
    doAssert fftNrStatus == FFT_Success

    var recovered_rn = newSeq[F](order)
    let ifftRnStatus = ifft_rn(fftDesc, recovered_rn, freq_nr)
    doAssert ifftRnStatus == FFT_Success

    for i in 0..<order:
      doAssert (recovered_rn[i] == vals[i]).bool,
        "ifft_rn(fft_nr(x)) should equal x (N=" & $order & ")"

  echo "  ✓ IFFT ordering tests PASSED"

proc testInPlaceFFT*(F: typedesc[Fr]) =
  echo "Testing in-place FFT support (aliasing)..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(F, order)

    # Test DIF in-place (Natural → Bit-Reversed)
    var data_dif = newSeq[F](order)
    for i in 0..<order:
      data_dif[i].fromUint(uint64(i + 1))

    let status_dif = fft_nr_iterative_dif(fftDesc, data_dif, data_dif)
    doAssert status_dif == FFT_Success, "In-place DIF failed (N=" & $order & ")"

    # Verify output is bit-reversed by comparing with out-of-place version
    var data_dif_oop = newSeq[F](order)
    for i in 0..<order:
      data_dif_oop[i].fromUint(uint64(i + 1))
    var out_dif = newSeq[F](order)
    discard fft_nr_iterative_dif(fftDesc, out_dif, data_dif_oop)

    for i in 0..<order:
      doAssert (data_dif[i] == out_dif[i]).bool,
        "In-place DIF mismatch at index " & $i & " (order=" & $order & ")"

    # Test DIT in-place (Bit-Reversed → Natural)
    var data_dit = newSeq[F](order)
    for i in 0..<order:
      data_dit[i].fromUint(uint64(i + 1))
    bit_reversal_permutation(data_dit)

    let status_dit = fft_rn_iterative_dit(fftDesc, data_dit, data_dit)
    doAssert status_dit == FFT_Success, "In-place DIT failed (N=" & $order & ")"

    # Verify output is natural order by comparing with out-of-place version
    var data_dit_oop = newSeq[F](order)
    for i in 0..<order:
      data_dit_oop[i].fromUint(uint64(i + 1))
    bit_reversal_permutation(data_dit_oop)
    var out_dit = newSeq[F](order)
    discard fft_rn_iterative_dit(fftDesc, out_dit, data_dit_oop)

    for i in 0..<order:
      doAssert (data_dit[i] == out_dit[i]).bool,
        "In-place DIT mismatch at index " & $i & " (order=" & $order & ")"

    # Test IFFT DIT in-place (Bit-Reversed → Natural)
    var ifft_data = newSeq[F](order)
    for i in 0..<order:
      ifft_data[i].fromUint(uint64(i + 1))
    bit_reversal_permutation(ifft_data)

    let status_ifft = ifft_rn_iterative_dit(fftDesc, ifft_data, ifft_data)
    doAssert status_ifft == FFT_Success, "In-place IFFT DIT failed (N=" & $order & ")"

    # Compare with out-of-place version
    var ifft_data_oop = newSeq[F](order)
    for i in 0..<order:
      ifft_data_oop[i].fromUint(uint64(i + 1))
    bit_reversal_permutation(ifft_data_oop)
    var out_ifft = newSeq[F](order)
    discard ifft_rn_iterative_dit(fftDesc, out_ifft, ifft_data_oop)

    for i in 0..<order:
      doAssert (ifft_data[i] == out_ifft[i]).bool,
        "In-place IFFT DIT mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ In-place FFT tests PASSED"

when isMainModule:
  echo "========================================"
  echo "    FFT/IFFT Correctness Tests"
  echo "========================================\n"

  testBitReversal(int64)
  echo ""
  testFrFFTRoundtrip(Fr[BLS12_381])
  echo ""
  testECFFTRoundtrip(EC_ShortW_Prj[Fp[BLS12_381], G1], Fr[BLS12_381])
  echo ""
  testIFFTInterpolation(Fr[BLS12_381])
  echo ""
  testFFTOrdering(Fr[BLS12_381])
  echo ""
  testECFFTOrdering(EC_ShortW_Prj[Fp[BLS12_381], G1], Fr[BLS12_381])
  echo ""
  testIFFTOrdering(Fr[BLS12_381])
  echo ""
  testInPlaceFFT(Fr[BLS12_381])

  echo "\n========================================"
  echo "    All FFT tests PASSED ✓"
  echo "========================================"
