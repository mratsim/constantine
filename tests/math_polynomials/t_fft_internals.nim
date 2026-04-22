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

# Test wrappers: compose algorithms with bit-reversal for testing
proc fft_nn_via_iterative_dif_and_bitrev[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFTStatus =
  ## Natural → Natural via: Iterative DIF (NR) + BitRev
  let status = fft_nr_iterative_dif(desc, output, vals)
  if status != FFT_Success: return status
  bit_reversal_permutation(output)
  return FFT_Success

proc fft_nn_via_bitrev_and_iterative_dit[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFTStatus =
  ## Natural → Natural via: BitRev + Iterative DIT (RN)
  var br_vals = newSeq[F](vals.len)
  bit_reversal_permutation(br_vals, vals)
  let status = fft_rn_iterative_dit(desc, output, br_vals)
  return status

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

    # Verify all produce same natural order output
    for i in 0..<order:
      doAssert (output_nn_rec[i] == output_nn_dif_br[i]).bool,
        "NN Rec vs NN DIF+BitRev mismatch at index " & $i & " (order=" & $order & ")"
      doAssert (output_nn_rec[i] == output_nn_br_dit[i]).bool,
        "NN Rec vs NN BitRev+DIT mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ Fr FFT: All 3 implementations produce identical results"

proc testECFFTAlgorithmConsistency*() =
  echo "Testing EC FFT consistency between recursive and iterative..."

  for order in [4, 8, 16]:
    let fftDesc = createFFTDescriptor(EC_G1, F, order)

    var vals = newSeq[EC_G1](order)
    vals[0].setGenerator()
    let gen = EC_G1.F.Name.getGenerator("G1")
    for i in 1..<order:
      vals[i].mixedSum(vals[i-1], gen)

    # NN Recursive + bitrev (Natural → Bit-Reversed)
    var output_nn_rec = newSeq[EC_G1](order)
    discard ec_fft_nn_recursive(fftDesc, output_nn_rec, vals)
    bit_reversal_permutation(output_nn_rec)

    # NR Iterative DIF (Natural → Bit-Reversed)
    var output_nr_dif = newSeq[EC_G1](order)
    discard ec_fft_nr_iterative(fftDesc, output_nr_dif, vals)

    # Verify both produce same output
    for i in 0..<order:
      doAssert (output_nn_rec[i] == output_nr_dif[i]).bool,
        "EC NN_Rec+bitrev vs NR_DIF mismatch at index " & $i & " (order=" & $order & ")"

  echo "  ✓ EC FFT: Recursive+BitRev and Iterative DIF produce identical results"

when isMainModule:
  echo "========================================"
  echo "    Low-Level FFT Algorithm Tests"
  echo "========================================"
  echo ""

  testFrFFTAlgorithmConsistency()
  testECFFTAlgorithmConsistency()

  echo ""
  echo "========================================"
  echo "    All Low-Level FFT tests PASSED ✓"
  echo "========================================"