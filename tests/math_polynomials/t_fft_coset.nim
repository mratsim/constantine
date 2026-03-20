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
      let cosetDesc = CosetFFT_Descriptor[F].new(
        order = n, generatorRootOfUnity = fftDesc.rootsOfUnity[1], shift = shift_factor)
      let cosetFftOk = coset_fft_nr(cosetDesc, coset_freq, data)
      doAssert cosetFftOk == FFT_Success

      var recovered = newSeq[F](n)
      let cosetIfftOk = coset_ifft_rn(cosetDesc, recovered, coset_freq)
      doAssert cosetIfftOk == FFT_Success
      cosetDesc.delete()

      for i in 0 ..< n:
        doAssert (recovered[i] == data[i]).bool,
          "Coset roundtrip failed at size " & $n & " index " & $i

    fftDesc.delete()

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
    let cosetDesc = CosetFFT_Descriptor[F].new(
      order = n, generatorRootOfUnity = fftDesc.rootsOfUnity[1], shift = shift_factor)
    let cosetFftOk = coset_fft_nr(cosetDesc, coset_freq, data)
    doAssert cosetFftOk == FFT_Success

    var recovered = newSeq[F](n)
    let cosetIfftOk = coset_ifft_rn(cosetDesc, recovered, coset_freq)
    doAssert cosetIfftOk == FFT_Success
    cosetDesc.delete()

    for i in 0 ..< n:
      doAssert (recovered[i] == data[i]).bool,
        "Coset roundtrip failed at size " & $n & " index " & $i

    fftDesc.delete()

  block:
    let n = 32
    let fftDesc = createFFTDescriptor(F, n)
    let coset_shift = fftDesc.rootsOfUnity[1] ~^ uint32(CELLS_PER_EXT_BLOB)

    var data = newSeq[F](n)
    for i in 0 ..< n:
      data[i].fromUint(uint64(i + 1))

    var coset_freq = newSeq[F](n)
    let cosetDesc = CosetFFT_Descriptor[F].new(
      order = n, generatorRootOfUnity = fftDesc.rootsOfUnity[1], shift = coset_shift)
    let cosetFftOk = coset_fft_nr(cosetDesc, coset_freq, data)
    doAssert cosetFftOk == FFT_Success

    var recovered = newSeq[F](n)
    let cosetIfftOk = coset_ifft_rn(cosetDesc, recovered, coset_freq)
    doAssert cosetIfftOk == FFT_Success
    cosetDesc.delete()

    for i in 0 ..< n:
      doAssert (recovered[i] == data[i]).bool,
        "Coset roundtrip failed at size " & $n & " index " & $i & " with PeerDAS coset shift"

    fftDesc.delete()

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
