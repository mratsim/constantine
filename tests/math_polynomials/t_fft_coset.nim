# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Coset FFT/IFFT Tests
#
# These tests verify the coset FFT functions used in:
# - Layer 1: Polynomial recovery (avoiding division by zero)
# - EIP-7594 PeerDAS: Data availability sampling
#
# Coset FFT shifts the domain so polynomials that vanish at certain points
# don't cause issues during division operations.

# Compile and run with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/math_polynomials/t_fft_coset.nim

import
  ../../constantine/named/algebras,
  ../../constantine/math/[arithmetic, ec_shortweierstrass],
  ../../constantine/math/polynomials/[fft, polynomials],
  ../../constantine/math/io/io_fields,
  ./fft_utils

proc testCosetFFTRoundtrip*(F: typedesc[Fr]) =
  echo "Testing Coset FFT/IFFT roundtrip..."

  for scale in 2 .. 5:
    let n = 1 shl scale
    let fftDesc = createFFTDescriptor(F, n)

    var shift_factor: F
    shift_factor.fromUint(7'u64)

    block:
      var data = newSeq[F](n)
      for i in 0 ..< n:
        data[i].fromUint(uint64(i + 1))

      var coset_freq = newSeq[F](n)
      let cosetFftOk = coset_fft_nn(fftDesc, coset_freq, data, shift_factor)
      doAssert cosetFftOk == FFT_Success

      var recovered = newSeq[F](n)
      let cosetIfftOk = coset_ifft_nn(fftDesc, recovered, coset_freq, shift_factor)
      doAssert cosetIfftOk == FFT_Success

      for i in 0 ..< n:
        doAssert (recovered[i] == data[i]).bool,
          "Coset roundtrip failed at size " & $n & " index " & $i

  echo "  ✓ All Coset FFT/IFFT roundtrip tests PASSED"

proc testCosetFFTSpecificSizes*(F: typedesc[Fr]) =
  echo "Testing Coset FFT for specific PeerDAS sizes..."

  const CELLS_PER_EXT_BLOB = 128

  block:
    let n = 32
    let fftDesc = createFFTDescriptor(F, n)

    var shift_factor: F
    shift_factor.fromUint(7'u64)

    var data = newSeq[F](n)
    for i in 0 ..< n:
      data[i].fromUint(uint64(i + 1))

    var coset_freq = newSeq[F](n)
    let cosetFftOk = coset_fft_nn(fftDesc, coset_freq, data, shift_factor)
    doAssert cosetFftOk == FFT_Success

    var recovered = newSeq[F](n)
    let cosetIfftOk = coset_ifft_nn(fftDesc, recovered, coset_freq, shift_factor)
    doAssert cosetIfftOk == FFT_Success

    for i in 0 ..< n:
      doAssert (recovered[i] == data[i]).bool,
        "Coset roundtrip failed at size " & $n & " index " & $i

  block:
    let n = 32
    let fftDesc = createFFTDescriptor(F, n)
    var coset_shift = fftDesc.rootsOfUnity[1]
    coset_shift.pow_vartime(Fr[BLS12_381].fromUint(uint32(CELLS_PER_EXT_BLOB)))

    var data = newSeq[F](n)
    for i in 0 ..< n:
      data[i].fromUint(uint64(i + 1))

    var coset_freq = newSeq[F](n)
    let cosetFftOk = coset_fft_nn(fftDesc, coset_freq, data, coset_shift)
    doAssert cosetFftOk == FFT_Success

    var recovered = newSeq[F](n)
    let cosetIfftOk = coset_ifft_nn(fftDesc, recovered, coset_freq, coset_shift)
    doAssert cosetIfftOk == FFT_Success

    for i in 0 ..< n:
      doAssert (recovered[i] == data[i]).bool,
        "Coset roundtrip failed at size " & $n & " index " & $i & " with PeerDAS coset shift"

  echo "  ✓ Coset FFT PeerDAS-specific tests PASSED"

when isMainModule:
  echo "========================================"
  echo "    Coset FFT/IFFT Correctness Tests"
  echo "========================================\n"

  testCosetFFTRoundtrip(Fr[BLS12_381])
  echo ""
  testCosetFFTSpecificSizes(Fr[BLS12_381])

  echo "\n========================================"
  echo "    All Coset FFT tests PASSED ✓"
  echo "========================================"
