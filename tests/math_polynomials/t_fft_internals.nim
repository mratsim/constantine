# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Low-Level FFT Algorithm Tests
#
# Tests consistency between different FFT algorithm implementations.

import
  ../../constantine/named/algebras,
  ../../constantine/named/zoo_generators,
  ../../constantine/math/[arithmetic, ec_shortweierstrass],
  ../../constantine/math/polynomials/fft_fields {.all.},
  ../../constantine/math/polynomials/fft_ec {.all.},
  ../../constantine/math/io/io_fields,
  ./fft_utils

type
  F = Fr[BLS12_381]
  EC_G1 = EC_ShortW_Prj[Fp[BLS12_381], G1]


proc testFrFFTAlgorithmConsistency*() =
  echo "Testing Fr FFT consistency between all implementations..."

  for order in [4, 8, 16, 32]:
    let fftDesc = createFFTDescriptor(F, order)

    var vals = newSeq[F](order)
    for i in 0..<order:
      vals[i].fromUint(uint64(i + 1))

    # Reference: Recursive NN (Natural → Natural)
    var output_nn_rec = newSeq[F](order)
    discard fft_nn_recursive(fftDesc, output_nn_rec, vals)

    # Method 1: Iterative DIF (NR) + BitRev (Natural → Natural)
    var output_nn_dif_br = newSeq[F](order)
    discard fft_nn_via_iterative_dif_and_bitrev(fftDesc, output_nn_dif_br, vals)

    # Method 2: BitRev + Iterative DIT (RN) (Natural → Natural)
    var output_nn_br_dit = newSeq[F](order)
    discard fft_nn_via_bitrev_and_iterative_dit(fftDesc, output_nn_br_dit, vals)

    # Method 3: Stockham (Natural → Natural)
    var output_nn_stockham = newSeq[F](order)
    discard fft_nn_stockham(fftDesc, output_nn_stockham, vals)

    # Verify all produce same natural order output
    for i in 0..<order:
      doAssert (output_nn_rec[i] == output_nn_dif_br[i]).bool,
        "NN Rec vs NN DIF+BitRev mismatch at index " & $i & " (order=" & $order & ")"
      doAssert (output_nn_rec[i] == output_nn_br_dit[i]).bool,
        "NN Rec vs NN BitRev+DIT mismatch at index " & $i & " (order=" & $order & ")"
      doAssert (output_nn_rec[i] == output_nn_stockham[i]).bool,
        "NN Rec vs NN Stockham mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ Fr FFT: All 4 implementations produce identical results"

proc testECFFTAlgorithmConsistency*() =
  echo "Testing EC FFT consistency between all implementations..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(EC_G1, F, order)

    var vals = newSeq[EC_G1](order)
    vals[0].setGenerator()
    let gen = EC_G1.F.Name.getGenerator("G1")
    for i in 1..<order:
      vals[i].mixedSum(vals[i-1], gen)

    # Reference: NN Recursive (Natural → Natural)
    var output_nn_rec = newSeq[EC_G1](order)
    discard ec_fft_nn_recursive(fftDesc, output_nn_rec, vals)

    # Method 1: Iterative DIF (NR) + BitRev (Natural → Natural)
    var output_nn_dif_br = newSeq[EC_G1](order)
    discard ec_fft_nn_via_iterative_dif_and_bitrev(fftDesc, output_nn_dif_br, vals)

    # Method 2: BitRev + Iterative DIT (RN) (Natural → Natural)
    var output_nn_br_dit = newSeq[EC_G1](order)
    discard ec_fft_nn_via_bitrev_and_iterative_dit(fftDesc, output_nn_br_dit, vals)

    # Verify all produce same natural order output
    for i in 0..<order:
      doAssert (output_nn_rec[i] == output_nn_dif_br[i]).bool,
        "EC NN Rec vs NN DIF+BitRev mismatch at index " & $i & " (order=" & $order & ")"
      doAssert (output_nn_rec[i] == output_nn_br_dit[i]).bool,
        "EC NN Rec vs NN BitRev+DIT mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ EC FFT: All implementations produce identical results"

proc testECIFFTAlgorithmConsistency*() =
  echo "Testing EC IFFT consistency between recursive and iterative..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(EC_G1, F, order)

    var vals = newSeq[EC_G1](order)
    vals[0].setGenerator()
    let gen = EC_G1.F.Name.getGenerator("G1")
    for i in 1..<order:
      vals[i].mixedSum(vals[i-1], gen)

    # Reference: Recursive IFFT NN (Natural → Natural)
    var output_nn_rec = newSeq[EC_G1](order)
    discard ec_ifft_nn_recursive(fftDesc, output_nn_rec, vals)

    # Method: BitRev + Iterative DIT (RN) (Natural → Natural)
    var output_nn_dit_br = newSeq[EC_G1](order)
    discard ec_ifft_nn_via_bitrev_and_iterative_dit(fftDesc, output_nn_dit_br, vals)

    # Verify both produce same natural order output
    for i in 0..<order:
      doAssert (output_nn_rec[i] == output_nn_dit_br[i]).bool,
        "EC NN Rec vs NN BitRev+DIT mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ EC IFFT: Recursive and Iterative DIT+BitRev produce identical results"

proc testECFFTNRConsistency*() =
  echo "Testing EC FFT NR (Natural → Bit-Reversed) output ordering..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(EC_G1, F, order)

    var vals = newSeq[EC_G1](order)
    vals[0].setGenerator()
    let gen = EC_G1.F.Name.getGenerator("G1")
    for i in 1..<order:
      vals[i].mixedSum(vals[i-1], gen)

    # Reference: NN Recursive (Natural → Natural)
    var output_nn = newSeq[EC_G1](order)
    discard ec_fft_nn_recursive(fftDesc, output_nn, vals)

    # NR Iterative DIF (Natural → Bit-Reversed)
    var output_nr = newSeq[EC_G1](order)
    discard ec_fft_nr_iterative(fftDesc, output_nr, vals)

    # Verify NR output is bit-reversed version of NN output
    for i in 0..<order:
      let br_i = reverseBits(uint(i), order.uint64.log2_vartime())
      doAssert (output_nr[i] == output_nn[br_i]).bool,
        "EC NR DIF should produce bit-reversed of NN Rec at index " & $i & " (order=" & $order & ")"

  echo "  ✓ EC FFT NR: Iterative DIF produces correct bit-reversed output"

proc testECFFTRNConsistency*() =
  echo "Testing EC FFT RN (Bit-Reversed → Natural) input/output..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(EC_G1, F, order)

    var vals = newSeq[EC_G1](order)
    vals[0].setGenerator()
    let gen = EC_G1.F.Name.getGenerator("G1")
    for i in 1..<order:
      vals[i].mixedSum(vals[i-1], gen)

    # Bit-reverse the input
    var vals_br = newSeq[EC_G1](order)
    bit_reversal_permutation(vals_br, vals)

    # Reference: NN Recursive (Natural → Natural)
    var output_nn = newSeq[EC_G1](order)
    discard ec_fft_nn_recursive(fftDesc, output_nn, vals)

    # RN Iterative DIT (Bit-Reversed → Natural)
    var output_rn = newSeq[EC_G1](order)
    discard ec_fft_rn_iterative_dit(fftDesc, output_rn, vals_br)

    # Verify RN output matches NN output (both natural order)
    for i in 0..<order:
      doAssert (output_rn[i] == output_nn[i]).bool,
        "EC RN DIT should match NN Rec at index " & $i & " (order=" & $order & ")"

  echo "  ✓ EC FFT RN: Iterative DIT produces correct natural order output"

proc testECIFFTRNConsistency*() =
  echo "Testing EC IFFT RN (Bit-Reversed → Natural) roundtrip..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(EC_G1, F, order)

    # Create time-domain data
    var time_data = newSeq[EC_G1](order)
    time_data[0].setGenerator()
    let gen = EC_G1.F.Name.getGenerator("G1")
    for i in 1..<order:
      time_data[i].mixedSum(time_data[i-1], gen)

    # FFT NR (Natural → Bit-Reversed)
    var freq_br = newSeq[EC_G1](order)
    discard ec_fft_nr_iterative(fftDesc, freq_br, time_data)

    # IFFT RN (Bit-Reversed → Natural) should recover original
    var recovered = newSeq[EC_G1](order)
    discard ec_ifft_rn_iterative_dit(fftDesc, recovered, freq_br)

    # Verify roundtrip: IFFT_RN(FFT_NR(x)) == x
    for i in 0..<order:
      doAssert (recovered[i] == time_data[i]).bool,
        "EC IFFT_RN(FFT_NR(x)) roundtrip failed at index " & $i & " (order=" & $order & ")"

  echo "  ✓ EC IFFT RN: IFFT_RN(FFT_NR(x)) roundtrip successful"

proc testFrIFFTAlgorithmConsistency*() =
  echo "Testing Fr IFFT consistency between recursive and iterative..."

  for order in [4, 8, 16, 32]:
    let fftDesc = createFFTDescriptor(F, order)

    var vals = newSeq[F](order)
    for i in 0..<order:
      vals[i].fromUint(uint64(i + 1))

    # Reference: Recursive IFFT NN (Natural → Natural)
    var output_nn_rec = newSeq[F](order)
    discard ifft_nn_recursive(fftDesc, output_nn_rec, vals)

    # Method: BitRev + Iterative DIT (RN) (Natural → Natural)
    var output_nn_dit_br = newSeq[F](order)
    discard ifft_nn_via_bitrev_and_iterative_dit(fftDesc, output_nn_dit_br, vals)

    # Verify both produce same natural order output
    for i in 0..<order:
      doAssert (output_nn_rec[i] == output_nn_dit_br[i]).bool,
        "NN Rec vs NN BitRev+DIT mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ Fr IFFT: Recursive and Iterative DIT+BitRev produce identical results"

proc testFrFFTNRConsistency*() =
  echo "Testing Fr FFT NR (Natural → Bit-Reversed) output ordering..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(F, order)

    var vals = newSeq[F](order)
    for i in 0..<order:
      vals[i].fromUint(uint64(i + 1))

    # Reference: NN Recursive (Natural → Natural)
    var output_nn = newSeq[F](order)
    discard fft_nn_recursive(fftDesc, output_nn, vals)

    # NR Iterative DIF (Natural → Bit-Reversed)
    var output_nr = newSeq[F](order)
    discard fft_nr_iterative_dif(fftDesc, output_nr, vals)

    # Verify NR output is bit-reversed version of NN output
    for i in 0..<order:
      let br_i = reverseBits(uint(i), order.uint64.log2_vartime())
      doAssert (output_nr[i] == output_nn[br_i]).bool,
        "NR DIF should produce bit-reversed of NN Rec at index " & $i & " (order=" & $order & ")"

  echo "  ✓ Fr FFT NR: Iterative DIF produces correct bit-reversed output"

proc testFrFFTRNConsistency*() =
  echo "Testing Fr FFT RN (Bit-Reversed → Natural) input/output..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(F, order)

    var vals = newSeq[F](order)
    for i in 0..<order:
      vals[i].fromUint(uint64(i + 1))

    # Bit-reverse the input
    var vals_br = newSeq[F](order)
    bit_reversal_permutation(vals_br, vals)

    # Reference: NN Recursive (Natural → Natural)
    var output_nn = newSeq[F](order)
    discard fft_nn_recursive(fftDesc, output_nn, vals)

    # RN Iterative DIT (Bit-Reversed → Natural)
    var output_rn = newSeq[F](order)
    discard fft_rn_iterative_dit(fftDesc, output_rn, vals_br)

    # Verify RN output matches NN output (both natural order)
    for i in 0..<order:
      doAssert (output_rn[i] == output_nn[i]).bool,
        "RN DIT should match NN Rec at index " & $i & " (order=" & $order & ")"

  echo "  ✓ Fr FFT RN: Iterative DIT produces correct natural order output"

proc testFrIFFTRNConsistency*() =
  echo "Testing Fr IFFT RN (Bit-Reversed → Natural) roundtrip..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(F, order)

    # Create time-domain data
    var time_data = newSeq[F](order)
    for i in 0..<order:
      time_data[i].fromUint(uint64(i + 1))

    # FFT NR (Natural → Bit-Reversed)
    var freq_br = newSeq[F](order)
    discard fft_nr_iterative_dif(fftDesc, freq_br, time_data)

    # IFFT RN (Bit-Reversed → Natural) should recover original
    var recovered = newSeq[F](order)
    discard ifft_rn_iterative_dit(fftDesc, recovered, freq_br)

    # Verify roundtrip: IFFT_RN(FFT_NR(x)) == x
    for i in 0..<order:
      doAssert (recovered[i] == time_data[i]).bool,
        "IFFT_RN(FFT_NR(x)) roundtrip failed at index " & $i & " (order=" & $order & ")"

  echo "  ✓ Fr IFFT RN: IFFT_RN(FFT_NR(x)) roundtrip successful"

when isMainModule:
  echo "========================================"
  echo "    Low-Level FFT Algorithm Tests"
  echo "========================================"
  echo ""

  testFrFFTAlgorithmConsistency()
  testECFFTAlgorithmConsistency()
  testECIFFTAlgorithmConsistency()
  testECFFTNRConsistency()
  testECFFTRNConsistency()
  testECIFFTRNConsistency()
  testFrIFFTAlgorithmConsistency()
  testFrFFTNRConsistency()
  testFrFFTRNConsistency()
  testFrIFFTRNConsistency()

  echo ""
  echo "========================================"
  echo "    All Low-Level FFT tests PASSED ✓"
  echo "========================================"