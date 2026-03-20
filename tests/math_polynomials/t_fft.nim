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

import
  ../../constantine/named/algebras,
  ../../constantine/named/zoo_generators,
  ../../constantine/math/[arithmetic, ec_shortweierstrass],
  ../../constantine/math/polynomials/fft,
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
      let fftOk = fft_nr(fftDesc, freq, data)
      doAssert fftOk == FFT_Success

      var recovered = newSeq[F](order)
      let ifftOk = ifft_rn(fftDesc, recovered, freq)
      doAssert ifftOk == FFT_Success

      if order == 2:
        echo "  === Size 2 Debug ==="
        echo "  FFT: [", freq[0].toHex(), ", ", freq[1].toHex(), "]"
        echo "  IFFT: [", recovered[0].toHex(), ", ", recovered[1].toHex(), "]"

      for i in 0 ..< order:
        doAssert (recovered[i] == data[i]).bool,
          "Roundtrip failed at size " & $order & " index " & $i

    fftDesc.delete()

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
    let fftOk = fft_vartime(fftDesc, freq, data)
    doAssert fftOk == FFT_Success

    var recovered = newSeq[EC](order)
    let ifftOk = ec_ifft_rn(fftDesc, recovered, freq)
    doAssert ifftOk == FFT_Success

    for i in 0 ..< order:
      doAssert (recovered[i] == data[i]).bool,
        "EC Roundtrip failed at size " & $order & " index " & $i

    fftDesc.delete()

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

    # Create bit-reversed input for ifft_rn (which expects bit-reversed order)
    var ys_bitrev: array[2, F]
    ys_bitrev[0] = ys[0]  # index 0 bit-reversed is 0
    ys_bitrev[1] = ys[1]  # index 1 bit-reversed is 1 (for log2(2)=1)

    var coeffs: array[2, F]
    let status = ifft_rn(fftDesc, coeffs.toOpenArray(0, L-1), ys_bitrev.toOpenArray(0, L-1))
    fftDesc.delete()
    doAssert status == FFT_Success

    doAssert (coeffs[0] == v0_expected).bool, "IFFT coefficient 0 mismatch for L=2"
    doAssert (coeffs[1] == v1_expected).bool, "IFFT coefficient 1 mismatch for L=2"

    var v_at_1, v_at_omegaL: F
    v_at_1.sum(coeffs[0], coeffs[1])
    v_at_omegaL.diff(coeffs[0], coeffs[1])

    doAssert (v_at_1 == ys[0]).bool, "Interpolation at 1 failed"
    doAssert (v_at_omegaL == ys[1]).bool, "Interpolation at ω_L failed"

  echo "  ✓ IFFT interpolation test PASSED"

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

  echo "\n========================================"
  echo "    All FFT tests PASSED ✓"
  echo "========================================"
