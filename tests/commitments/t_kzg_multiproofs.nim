# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Compile and run with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/commitments/t_kzg_multiproofs.nim

## Run with
##   nim c -r -d:release --hints:off --warnings:off --outdir:build/wip --nimcache:nimcache/wip tests/commitments/t_kzg_multiproofs.nim

import
  constantine/named/algebras,
  constantine/named/zoo_generators,
  constantine/math/[ec_shortweierstrass, extension_fields],
  constantine/math/polynomials/[polynomials, fft_fields, fft_ec],
  constantine/math/arithmetic/finite_fields,
  constantine/math/matrix/toeplitz,
  constantine/commitments/kzg_multiproofs,
  constantine/commitments/kzg,
  constantine/math/io/[io_fields, io_bigints],
  constantine/platforms/[primitives, views, bithacks], # For asUnchecked, reverseBits
  ./trusted_setup_generator

from trusted_setup_generator import
  BLS12_381_G1_Aff, BLS12_381_G1_Jac

type FK20PolyphaseSpectrumBank[N, L, CDS: static int, Name: static Algebra] = array[L, array[CDS, EC_ShortW_Aff[Fp[Name], G1]]]

func pow(omegaMax: Fr[BLS12_381], domainPos: uint32): Fr[BLS12_381] =
  var exp: Fr[BLS12_381]
  exp.fromUint(uint64(domainPos))
  result = omegaMax
  result.pow_vartime(exp)

proc testFK20SingleProofs() =
  ## Test FK20 single-proof DA matching c-kzg's fk_single test
  echo "Testing FK20 single proofs (c-kzg fk_single pattern)..."

  const N = 16
  const CDS = 32  # 2*N for DA extension
  const maxWidth = CDS  # For single proof, maxWidth = CDS
  const L = 1
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  # Create FFT descriptors sized to CDS (= 2 * N).
  # Production code uses a single larger descriptor (ctx.fft_desc_ext) with strides;
  # this test isolates the FK20 path with descriptors sized exactly to the test.
  let ecfft_desc = ECFFT_Descriptor[BLS12_381_G1_Jac].new(order = CDS, setup.omegaForFFT)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

  var polyphaseSpectrumBank: array[L, array[CDS, BLS12_381_G1_Aff]]
  computePolyphaseDecompositionFourier(polyphaseSpectrumBank, setup.powers_of_tau_G1, ecfft_desc)

  var fk20Proofs: array[CDS, BLS12_381_G1_Aff]
  kzg_coset_prove(fk20Proofs, setup.testPoly.coefs, fr_fft_desc, ecfft_desc, polyphaseSpectrumBank)

  # Compute commitment using pre-generated BigInt polynomial
  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  # Verify each proof using kzg_verify (single proof case)
  var verified = 0
  for i in 0 ..< CDS:
    let z = fr_fft_desc.rootsOfUnity[i]
    var y: Fr[BLS12_381]
    evalPolyAt(y, setup.testPoly, z)

    let ok = kzg_verify(
      commitmentAff, z.toBig(), y.toBig(),
      fk20Proofs[i], setup.powers_of_tau_G2.coefs[1])

    if ok:
      inc verified
    else:
      echo "  FAILED at i=", i

  echo "  Verified ", verified, "/", CDS, " proofs"
  doAssert verified == CDS, "Not all FK20 proofs verified"
  echo "✓ FK20 single proofs test PASSED"

proc testFK20MultiProofs(L: static int) =
  ## Test FK20 multi-proof with L > 1 (EIP-7594 pattern)
  ## Uses c-kzg convention: domain of order 2*N for proof gen, bit-reversed proofs/ys
  ## Constraint: N == L * (CDS/2), so for given L we need appropriate N and CDS
  echo "Testing FK20 multi-proofs (L = ", L, ")..."

  when L == 2:
    const N = 16
    const CDS = 16
    const maxWidth = 32
  elif L == 4:
    const N = 32
    const CDS = 16
    const maxWidth = 64
  else:
    {.error: "testFK20MultiProofs only supports L in {2, 4}".}
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  # Create FFT descriptors for CDS=16
  let ecfft_desc = ECFFT_Descriptor[BLS12_381_G1_Jac].new(order = CDS, setup.omegaForFFT)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

  var polyphaseSpectrumBank: array[L, array[CDS, BLS12_381_G1_Aff]]
  computePolyphaseDecompositionFourier(polyphaseSpectrumBank, setup.powers_of_tau_G1, ecfft_desc)

  var fk20Proofs: array[CDS, BLS12_381_G1_Aff]
  kzg_coset_prove(
    fk20Proofs, setup.testPoly.coefs, fr_fft_desc, ecfft_desc, polyphaseSpectrumBank)

  fk20Proofs.bit_reversal_permutation()

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  const chunkCount = N div L  # 8
  const numProofs = 2 * chunkCount  # 16
  const nBits = 4  # log2(16) = 4 (for bit-reversing position)
  var verified = 0
  for pos in 0'u32 ..< numProofs:
    let domainPos = reverseBits(pos, nBits)
    let h = setup.rootsOfUnity.rootsOfUnity[domainPos] # coset shift

    doAssert bool(h ~^ uint32(L) == setup.rootsOfUnity.rootsOfUnity[domainPos*L])

    var ys: array[L, Fr[BLS12_381]]
    ys.computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    ys.bit_reversal_permutation() # EIP-7594 convention, blobs are bit-reversed evaluations

    let ok = fr_fft_desc.kzg_coset_verify(
      commitmentAff,
      proof = fk20Proofs[pos],
      ys,
      cosetShift = h,
      setup.powers_of_tau_G1.coefs,
      setup.powers_of_tau_G2.coefs[L])

    if ok:
      inc verified
    else:
      echo "  FAILED at pos=", pos

  echo "  Verified ", verified, "/", numProofs, " proofs"
  doAssert verified == numProofs, "Not all FK20 multi-proofs verified"
  echo "✓ FK20 multi-proofs test PASSED"


proc testNonOptimizedCosetProofs*(L: static int) =
  ## Test the non-optimized (schoolbook) KZG coset proof function
  ## and verify it produces the same results as FK20
  echo "Testing non-optimized KZG coset proofs (L = ", L, ")..."

  when L == 2:
    const N = 16
    const CDS = 16
    const maxWidth = 32
  elif L == 4:
    const N = 32
    const CDS = 16
    const maxWidth = 64
  else:
    {.error: "testNonOptimizedCosetProofs only supports L in {2, 4}".}
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  # Create FFT descriptors for CDS=16
  let ecfft_desc = ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]].new(order = CDS, setup.omegaForFFT)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

  var polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]]
  computePolyphaseDecompositionFourier(polyphaseSpectrumBank, setup.powers_of_tau_G1, ecfft_desc)

  var fk20Proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  kzg_coset_prove(
    fk20Proofs, setup.testPoly.coefs, fr_fft_desc, ecfft_desc, polyphaseSpectrumBank)

  fk20Proofs.bit_reversal_permutation()

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  const chunkCount = N div L
  const numProofs = 2 * chunkCount
  const nBits = 4

  var matching = 0
  var naiveVerified = 0
  var fk20Verified = 0
  for pos in 0'u32 ..< numProofs:
    let domainPos = reverseBits(pos, nBits)
    let h = setup.rootsOfUnity.rootsOfUnity[domainPos] # coset shift

    doAssert bool(h ~^ uint32(L) == setup.rootsOfUnity.rootsOfUnity[domainPos*L])

    var ys: array[L, Fr[BLS12_381]]
    ys.computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    ys.bit_reversal_permutation() # EIP-7594 convention, blobs are bit-reversed evaluations

    let fk20Proof = fk20Proofs[pos]

    var nonOptProof: EC_ShortW_Aff[Fp[BLS12_381], G1]
    kzg_coset_prove_naive(
      nonOptProof, setup.testPoly, h, L, setup.powers_of_tau_G1)

    if (fk20Proof == nonOptProof).bool:
      inc matching
    else:
      echo "  MISMATCH at pos=", pos

    let okNaive = fr_fft_desc.kzg_coset_verify(
      commitmentAff,
      proof = nonOptProof,
      ys,
      cosetShift = h,
      setup.powers_of_tau_G1.coefs,
      setup.powers_of_tau_G2.coefs[L])
    if okNaive:
      inc naiveVerified

    let okFK20 = fr_fft_desc.kzg_coset_verify(
      commitmentAff,
      proof = fk20Proof,
      ys,
      cosetShift = h,
      setup.powers_of_tau_G1.coefs,
      setup.powers_of_tau_G2.coefs[L])
    if okFK20:
      inc fk20Verified

  echo "  Matching FK20 proofs: ", matching, "/", numProofs
  echo "  Naive verified: ", naiveVerified, "/", numProofs
  echo "  FK20 verified: ", fk20Verified, "/", numProofs
  doAssert matching == numProofs, "Non-optimized proofs don't match FK20"
  doAssert naiveVerified == numProofs, "Naive proofs don't verify"
  doAssert fk20Verified == numProofs, "FK20 proofs don't verify"
  echo "✓ Non-optimized KZG coset proofs test PASSED"

proc testKzgCosetVerifyBatch*(numTestCells: int) =
  ## Test kzg_coset_verify_batch with configurable number of cells
  ## Uses the new API with openArray and FrFFT_Descriptor
  ## Uses kzg_coset_prove_naive for simple proof generation (not FK20)

  const
    N = 4096  # Polynomial size (coefficient count)
    L = 64    # FIELD_ELEMENTS_PER_CELL (coset size)
    maxWidth = 8192  # Full domain size = CDS * L = 2 * N
    nBits = 7  # log2(128)
    numCols = maxWidth div L
  doAssert numTestCells <= numCols, "numTestCells exceeds available columns"

  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = maxWidth, setup.rootsOfUnity.rootsOfUnity[1])

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  var uniqueCommitments = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](1)
  uniqueCommitments[0] = commitmentAff

  var commitmentIdx = newSeq[int](numTestCells)
  var evalsCols = newSeq[int](numTestCells)
  var evals = newSeq[array[L, Fr[BLS12_381]]](numTestCells)
  var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numTestCells)
  var cosetShifts = newSeq[Fr[BLS12_381]](numTestCells)

  # Generate proofs and evals for the cells we want to test
  # Use the same coset shift computation as batch verification: reverseBits(c) without *L
  # because the FFT descriptor has roots in natural order
  for i in 0 ..< numTestCells:
    let cellIdx = uint64(i)
    # Batch verification computes coset shift at index reverseBits(evalsCols[i])
    let cosetIdx = reverseBits(uint32(cellIdx), uint32(nBits))
    let h = setup.rootsOfUnity.rootsOfUnity[cosetIdx]

    evalsCols[i] = int(cellIdx)
    commitmentIdx[i] = 0  # index into uniqueCommitments
    cosetShifts[i] = h

    # Generate evals and bit-reverse per EIP-7594 convention
    evals[i].computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    evals[i].bit_reversal_permutation() # EIP-7594 convention, blobs are bit-reversed evaluations

    # Generate proof using naive polynomial division
    # Note: naive proof gen doesn't bit-reverse, but batch verification expects
    # proofs in the same order as evalsCols, so no bit-reversal needed here
    kzg_coset_prove_naive(
      proofs[i], setup.testPoly, h, L, setup.powers_of_tau_G1)

  # PRE-TEST: Verify each cell individually with kzg_coset_verify
  echo "    Pre-testing individual cells with kzg_coset_verify..."
  for i in 0 ..< numTestCells:
    let ok = fr_fft_desc.kzg_coset_verify(
      commitmentAff,
      proofs[i],
      evals[i],
      cosetShifts[i],
      setup.powers_of_tau_G1.coefs,
      setup.powers_of_tau_G2.coefs[L]
    )
    if not ok:
      echo "    ✗ FAILED individual verification for cell ", i
      echo "      cosetShift = ", cosetShifts[i].toHex()
    else:
      echo "    ✓ Cell ", i, " verified individually"
    doAssert ok, "Individual cell verification failed for cell " & $i

  var r: Fr[BLS12_381]
  r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
  var linearIndepRandNumbers = newSeq[Fr[BLS12_381]](numTestCells)
  linearIndepRandNumbers.asUnchecked().computePowers(r, numTestCells, skipOne = true)

  let tau_pow_L_g2 = setup.powers_of_tau_G2.coefs[L]

  let verified = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size, not polynomial degree
  )

  doAssert verified, "Batch verification failed for " & $numTestCells & " cells"
  echo "  ✓ Verified ", numTestCells, " cells"

proc testKzgCosetVerifyBatch*() =
  ## Test kzg_coset_verify_batch with multiple cell counts
  echo "Testing kzg_coset_verify_batch (EIP-7594)..."

  const testCases = [1, 2, 3, 4, 5, 10, 16]
  for numCells in testCases:
    echo "  Testing with ", numCells, " cells..."
    testKzgCosetVerifyBatch(numCells)

  echo "✓ kzg_coset_verify_batch all tests PASSED"

proc testKzgCosetVerifyBatchSmallSizes*(numTestCells: int) =
  ## Test batch verification with small polynomial sizes to ensure generic behavior
  ## Uses N=64, L=4 for faster testing while maintaining correctness
  const
    N = 64    # Small polynomial size
    L = 4     # Small coset size
    maxWidth = 128  # Extended domain
    nBits = 5  # log2(32)
    numCols = maxWidth div L
  doAssert numTestCells <= numCols, "numTestCells exceeds available columns"

  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = maxWidth, setup.rootsOfUnity.rootsOfUnity[1])

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  var uniqueCommitments = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](1)
  uniqueCommitments[0] = commitmentAff

  var commitmentIdx = newSeq[int](numTestCells)
  var evalsCols = newSeq[int](numTestCells)
  var evals = newSeq[array[L, Fr[BLS12_381]]](numTestCells)
  var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numTestCells)
  var cosetShifts = newSeq[Fr[BLS12_381]](numTestCells)

  for i in 0 ..< numTestCells:
    let cellIdx = uint64(i)
    # Use same coset shift computation as batch verification
    let cosetIdx = reverseBits(uint32(cellIdx), uint32(nBits))
    let h = setup.rootsOfUnity.rootsOfUnity[cosetIdx]

    evalsCols[i] = int(cellIdx)
    commitmentIdx[i] = 0
    cosetShifts[i] = h

    evals[i].computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    evals[i].bit_reversal_permutation()

    kzg_coset_prove_naive(
      proofs[i], setup.testPoly, h, L, setup.powers_of_tau_G1)

  var r: Fr[BLS12_381]
  r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
  var linearIndepRandNumbers = newSeq[Fr[BLS12_381]](numTestCells)
  linearIndepRandNumbers.asUnchecked().computePowers(r, numTestCells, skipOne = true)

  let tau_pow_L_g2 = setup.powers_of_tau_G2.coefs[L]
  let verified = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size, not polynomial degree
  )

  doAssert verified, "Batch verification failed for " & $numTestCells & " cells (small sizes)"
  echo "  ✓ Verified ", numTestCells, " cells (N=64, L=4)"

proc testKzgCosetVerifyBatchSmallSizes*() =
  ## Test batch verification with various small sizes
  echo "Testing kzg_coset_verify_batch with small sizes..."

  const testCases = [1, 2, 3, 4, 5, 8, 10, 16, 32]
  for numCells in testCases:
    echo "  Testing with ", numCells, " cells..."
    testKzgCosetVerifyBatchSmallSizes(numCells)

  echo "✓ kzg_coset_verify_batch small sizes all tests PASSED"

proc testKzgCosetVerifyBatchNegative_SwitchProofs*(numTestCells: int) =
  ## Negative test: corrupt one proof to verify batch verification catches it
  ## This tests that batch verification detects invalid proofs
  const
    N = 64
    L = 4
    maxWidth = 128
    nBits = 5

  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = maxWidth, setup.rootsOfUnity.rootsOfUnity[1])

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  var uniqueCommitments = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](1)
  uniqueCommitments[0] = commitmentAff

  var commitmentIdx = newSeq[int](numTestCells)
  var evalsCols = newSeq[int](numTestCells)
  var evals = newSeq[array[L, Fr[BLS12_381]]](numTestCells)
  var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numTestCells)
  var cosetShifts = newSeq[Fr[BLS12_381]](numTestCells)

  for i in 0 ..< numTestCells:
    let cellIdx = uint64(i)
    let cosetIdx = reverseBits(uint32(cellIdx), uint32(nBits))
    let h = setup.rootsOfUnity.rootsOfUnity[cosetIdx]

    evalsCols[i] = int(cellIdx)
    commitmentIdx[i] = 0
    cosetShifts[i] = h

    evals[i].computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    evals[i].bit_reversal_permutation()

    kzg_coset_prove_naive(
      proofs[i], setup.testPoly, h, L, setup.powers_of_tau_G1)


  var r: Fr[BLS12_381]
  r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
  var linearIndepRandNumbers = newSeq[Fr[BLS12_381]](numTestCells)
  linearIndepRandNumbers.asUnchecked().computePowers(r, numTestCells, skipOne = true)

  let tau_pow_L_g2 = setup.powers_of_tau_G2.coefs[L]
  # BASELINE: Verify clean batch passes before corruption
  let verified_clean = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size
  )
  doAssert verified_clean, "Clean batch verification must succeed before corruption test!"
  echo "  ✓ Clean batch verification passed (", numTestCells, " cells)"

  # NEGATIVE TEST: Corrupt one proof by using evals from a different cell
  # This creates a provable mismatch that should be detected
  if numTestCells >= 2:
    # Use evals from cell 1 for proof 0 (mismatch!)
    evals[0] = evals[1]
    evalsCols[0] = evalsCols[1]
    cosetShifts[0] = cosetShifts[1]

  let verified = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size
  )

  doAssert not verified, "Batch verification should FAIL with corrupted proof/eval mismatch but passed!"
  echo "  ✓ Correctly detected corrupted proof/eval mismatch (", numTestCells, " cells)"

proc testKzgCosetVerifyBatchNegative_SwitchProofs*() =
  ## Test negative case with switched proofs for various sizes
  echo "Testing batch verification with switched proofs (negative tests)..."

  const testCases = [2, 3, 4, 5, 8, 10]
  for numCells in testCases:
    echo "  Testing with ", numCells, " cells..."
    testKzgCosetVerifyBatchNegative_SwitchProofs(numCells)

  echo "✓ Switched proofs negative tests all PASSED"

proc testKzgCosetVerifyBatchNegative_SwitchEvals*(numTestCells: int) =
  ## Negative test: switch evals around to verify batch catches mismatched evals
  ## This tests that batch verification detects when evals don't match proofs
  const
    N = 64
    L = 4
    maxWidth = 128
    nBits = 5
    numCols = maxWidth div L
  doAssert numTestCells <= numCols, "numTestCells exceeds available columns"

  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = maxWidth, setup.rootsOfUnity.rootsOfUnity[1])

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  var uniqueCommitments = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](1)
  uniqueCommitments[0] = commitmentAff

  var commitmentIdx = newSeq[int](numTestCells)
  var evalsCols = newSeq[int](numTestCells)
  var evals = newSeq[array[L, Fr[BLS12_381]]](numTestCells)
  var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numTestCells)
  var cosetShifts = newSeq[Fr[BLS12_381]](numTestCells)

  for i in 0 ..< numTestCells:
    let cellIdx = uint64(i)
    let cosetIdx = reverseBits(uint32(cellIdx), uint32(nBits))
    let h = setup.rootsOfUnity.rootsOfUnity[cosetIdx]

    evalsCols[i] = int(cellIdx)
    commitmentIdx[i] = 0
    cosetShifts[i] = h

    evals[i].computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    evals[i].bit_reversal_permutation()

    kzg_coset_prove_naive(
      proofs[i], setup.testPoly, h, L, setup.powers_of_tau_G1)

  var r: Fr[BLS12_381]
  r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
  var linearIndepRandNumbers = newSeq[Fr[BLS12_381]](numTestCells)
  linearIndepRandNumbers.asUnchecked().computePowers(r, numTestCells, skipOne = true)

  let tau_pow_L_g2 = setup.powers_of_tau_G2.coefs[L]

  # PRE-TEST: Verify clean batch before corruption
  let verified_clean = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments, commitmentIdx, proofs, evals, evalsCols,
    fr_fft_desc, linearIndepRandNumbers, setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2, maxWidth
  )
  doAssert verified_clean, "Clean batch verification must succeed before corruption test!"

  # NEGATIVE TEST: Switch evals AND their metadata (but not proofs)

  # NEGATIVE TEST: Switch evals AND their metadata (but not proofs)
  # This creates a mismatch between proofs and evals
  if numTestCells >= 2:
    let tempEvals = evals[0]
    evals[0] = evals[1]
    evals[1] = tempEvals
    let tempCol = evalsCols[0]
    evalsCols[0] = evalsCols[1]
    evalsCols[1] = tempCol
    let tempShift = cosetShifts[0]
    cosetShifts[0] = cosetShifts[1]
    cosetShifts[1] = tempShift

  let verified = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size
  )

  doAssert not verified, "Batch verification should FAIL with switched evals but passed!"
  echo "  ✓ Correctly detected switched evals (", numTestCells, " cells)"

proc testKzgCosetVerifyBatchNegative_SwitchEvals*() =
  ## Test negative case with switched evals for various sizes
  echo "Testing batch verification with switched evals (negative tests)..."

  const testCases = [2, 3, 4, 5, 8, 10]
  for numCells in testCases:
    echo "  Testing with ", numCells, " cells..."
    testKzgCosetVerifyBatchNegative_SwitchEvals(numCells)

  echo "✓ Switched evals negative tests all PASSED"

proc testKzgCosetVerifyBatchNegative_FakeProof*(numTestCells: int) =
  ## Negative test: create a fake proof by modifying a valid proof
  ## This tests that batch verification catches invalid proofs
  const
    N = 64
    L = 4
    maxWidth = 128
    nBits = 5
    numCols = maxWidth div L
  doAssert numTestCells <= numCols, "numTestCells exceeds available columns"

  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = maxWidth, setup.rootsOfUnity.rootsOfUnity[1])

  var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

  var uniqueCommitments = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](1)
  uniqueCommitments[0] = commitmentAff

  var commitmentIdx = newSeq[int](numTestCells)
  var evalsCols = newSeq[int](numTestCells)
  var evals = newSeq[array[L, Fr[BLS12_381]]](numTestCells)
  var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numTestCells)
  var cosetShifts = newSeq[Fr[BLS12_381]](numTestCells)

  for i in 0 ..< numTestCells:
    let cellIdx = uint64(i)
    let cosetIdx = reverseBits(uint32(cellIdx), uint32(nBits))
    let h = setup.rootsOfUnity.rootsOfUnity[cosetIdx]

    evalsCols[i] = int(cellIdx)
    commitmentIdx[i] = 0
    cosetShifts[i] = h

    evals[i].computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)
    evals[i].bit_reversal_permutation()

    kzg_coset_prove_naive(
      proofs[i], setup.testPoly, h, L, setup.powers_of_tau_G1)

  var r: Fr[BLS12_381]
  r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
  var linearIndepRandNumbers = newSeq[Fr[BLS12_381]](numTestCells)
  linearIndepRandNumbers.asUnchecked().computePowers(r, numTestCells, skipOne = true)

  let tau_pow_L_g2 = setup.powers_of_tau_G2.coefs[L]

  # PRE-TEST: Verify clean batch before corruption
  let verified_clean = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments, commitmentIdx, proofs, evals, evalsCols,
    fr_fft_desc, linearIndepRandNumbers, setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2, maxWidth
  )
  doAssert verified_clean, "Clean batch verification must succeed before corruption test!"

  # NEGATIVE TEST: Create a fake proof by modifying the first proof
  # NEGATIVE TEST: Create a fake proof by modifying the first proof
  if numTestCells >= 1:
    # Modify the proof by adding a random point to it
    var fakeProofJac: EC_ShortW_Jac[Fp[BLS12_381], G1]
    fakeProofJac.fromAffine(proofs[0])

    # Add generator to make it invalid
    var generatorJac: EC_ShortW_Jac[Fp[BLS12_381], G1]
    generatorJac.fromAffine(BLS12_381.getGenerator("G1"))
    fakeProofJac += generatorJac

    var fakeProofAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
    fakeProofAff.affine(fakeProofJac)
    proofs[0] = fakeProofAff

  let verified = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size
  )

  doAssert not verified, "Batch verification should FAIL with fake proof but passed!"
  echo "  ✓ Correctly detected fake proof (", numTestCells, " cells)"

proc testKzgCosetVerifyBatchNegative_FakeProof*() =
  ## Test negative case with fake proofs for various sizes
  echo "Testing batch verification with fake proofs (negative tests)..."

  const testCases = [1, 2, 3, 4, 5, 8]
  for numCells in testCases:
    echo "  Testing with ", numCells, " cells..."
    testKzgCosetVerifyBatchNegative_FakeProof(numCells)

  echo "✓ Fake proof negative tests all PASSED"

proc testKzgCosetVerifyBatchMultipleCommitments*(numCommitments: int, cellsPerCommitment: int) =
  ## Test batch verification with multiple different commitments
  ## This tests the row aggregation logic with multiple polynomials
  const
    N = 64
    L = 4
    maxWidth = 128
    nBits = 5
    numCols = maxWidth div L
  doAssert cellsPerCommitment <= numCols, "cellsPerCommitment exceeds available columns"

  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = maxWidth, setup.rootsOfUnity.rootsOfUnity[1])

  # Create multiple commitments with different test polynomials
  var uniqueCommitments = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numCommitments)
  var testPolys = newSeq[PolynomialCoef[N, Fr[BLS12_381]]](numCommitments)
  var testPolysBig = newSeq[PolynomialCoef[N, BigInt[255]]](numCommitments)

  for i in 0 ..< numCommitments:
    # Create a different polynomial for each commitment
    for j in 0 ..< N:
      testPolys[i].coefs[j].fromUint(uint64(i * N + j + 1))
      testPolysBig[i].coefs[j].fromUint(uint64(i * N + j + 1))

    var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
    kzg_commit(setup.powers_of_tau_G1, commitmentAff, testPolysBig[i])
    uniqueCommitments[i] = commitmentAff

  let totalCells = numCommitments * cellsPerCommitment
  var commitmentIdx = newSeq[int](totalCells)
  var evalsCols = newSeq[int](totalCells)
  var evals = newSeq[array[L, Fr[BLS12_381]]](totalCells)
  var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](totalCells)
  var cosetShifts = newSeq[Fr[BLS12_381]](totalCells)

  for i in 0 ..< totalCells:
    let commitIdx = i div cellsPerCommitment
    let cellIdx = uint64(i mod cellsPerCommitment)
    # Use same coset shift computation as batch verification
    let cosetIdx = reverseBits(uint32(cellIdx), uint32(nBits))
    let h = setup.rootsOfUnity.rootsOfUnity[cosetIdx]

    evalsCols[i] = int(cellIdx)
    commitmentIdx[i] = commitIdx
    cosetShifts[i] = h

    evals[i].computeEvalsAtCoset(testPolys[commitIdx], h, setup.rootsOfUnity)
    evals[i].bit_reversal_permutation()

    kzg_coset_prove_naive(
      proofs[i], testPolys[commitIdx], h, L, setup.powers_of_tau_G1)

  var r: Fr[BLS12_381]
  r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
  var linearIndepRandNumbers = newSeq[Fr[BLS12_381]](totalCells)
  linearIndepRandNumbers.asUnchecked().computePowers(r, totalCells, skipOne = true)

  let tau_pow_L_g2 = setup.powers_of_tau_G2.coefs[L]
  let verified = kzg_coset_verify_batch[L, BLS12_381](
    uniqueCommitments,
    commitmentIdx,
    proofs,
    evals,
    evalsCols,
    fr_fft_desc,
    linearIndepRandNumbers,
    setup.powers_of_tau_G1.coefs,
    tau_pow_L_g2,
    maxWidth  # Use extended domain size
  )

  doAssert verified, "Batch verification failed for " & $numCommitments & " commitments with " & $cellsPerCommitment & " cells each"
  echo "  ✓ Verified ", numCommitments, " commitments × ", cellsPerCommitment, " cells = ", totalCells, " total"

proc testKzgCosetVerifyBatchMultipleCommitments*() =
  ## Test batch verification with multiple commitments
  echo "Testing batch verification with multiple commitments..."

  const testCases = [(2, 2), (2, 4), (3, 3), (4, 2), (5, 3)]
  for (numCommits, cellsPerCommit) in testCases:
    echo "  Testing with ", numCommits, " commitments × ", cellsPerCommit, " cells..."
    testKzgCosetVerifyBatchMultipleCommitments(numCommits, cellsPerCommit)

  echo "✓ Multiple commitments tests all PASSED"

when isMainModule:
  echo "========================================"
  echo "    KZG Multi-Proof Tests"
  echo "========================================\n"

  echo "Single proof per coset ... "
  testFK20SingleProofs()

  echo "---------------------------"

  echo "Multiple proofs per coset (L=2) ... "
  testFK20MultiProofs(2)

  echo "---------------------------"

  echo "Multiple proofs per coset (L=4) ... "
  testFK20MultiProofs(4)

  echo "---------------------------"

  echo "Non-optimized coset proofs (L=2) ... "
  testNonOptimizedCosetProofs(2)

  echo "---------------------------"

  echo "Non-optimized coset proofs (L=4) ... "
  testNonOptimizedCosetProofs(4)

  echo "---------------------------"

  echo "EIP-7594 batch verification ... "
  testKzgCosetVerifyBatch()

  echo "---------------------------"

  echo "EIP-7594 batch verification (small sizes) ... "
  testKzgCosetVerifyBatchSmallSizes()

  echo "---------------------------"

  echo "EIP-7594 batch verification (multiple commitments) ... "
  testKzgCosetVerifyBatchMultipleCommitments()

  echo "---------------------------"

  echo "Negative tests: switched proofs ... "
  testKzgCosetVerifyBatchNegative_SwitchProofs()

  echo "---------------------------"

  echo "Negative tests: switched evals ... "
  testKzgCosetVerifyBatchNegative_SwitchEvals()

  echo "---------------------------"

  echo "Negative tests: fake proofs ... "
  testKzgCosetVerifyBatchNegative_FakeProof()

  echo "\n========================================"
  echo "    All KZG multiproofs tests PASSED ✓"
  echo "========================================"
