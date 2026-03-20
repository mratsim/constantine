# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Compile and run with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/commitments/t_kzg_multiproofs.nim

import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, extension_fields],
  constantine/math/polynomials/[polynomials, fft],
  constantine/math/arithmetic/finite_fields,
  constantine/commitments/kzg_multiproofs,
  constantine/commitments/kzg,
  constantine/math/io/io_fields,
  constantine/platforms/[primitives, views], # For asUnchecked
  ./trusted_setup_generator

from trusted_setup_generator import
  EC_G1_Aff, EC_G1_Jac, EC_G2_Aff

type FK20TauExt[N, L, CDS: static int, Name: static Algebra] = array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]]

func pow*(omegaMax: Fr[BLS12_381], domainPos: uint32): Fr[BLS12_381] =
  var exp: Fr[BLS12_381]
  exp.fromUint(uint64(domainPos))
  result = omegaMax
  result.pow(exp)

proc testFK20SingleProofs() =
  ## Test FK20 single-proof DA matching c-kzg's fk_single test
  echo "Testing FK20 single proofs (c-kzg fk_single pattern)..."

  const N = 16
  const CDS = 32  # 2*N for DA extension
  const maxWidth = CDS  # For single proof, maxWidth = CDS
  const L = 1
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  # TODO: we switched to CDS, wrong comment
  # Create FFT descriptors using stride from maxWidth descriptor
  # This matches production code which uses ctx.fft_desc_ext (8192-order) for all sizes
  let ecfft_desc = ECFFT_Descriptor[EC_G1_Jac].new(order = CDS, setup.omegaForFFT)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

  var tauExtFftArray: array[L, array[CDS, EC_G1_Jac]]
  getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, ecfft_desc)

  var fk20Proofs: array[CDS, EC_G1_Aff]
  kzg_coset_prove(tauExtFftArray, fk20Proofs, setup.testPoly, fr_fft_desc, ecfft_desc)

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
  when L == 4:
    const N = 32
    const CDS = 16
    const maxWidth = 64
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  # Create FFT descriptors for CDS=16
  let ecfft_desc = ECFFT_Descriptor[EC_G1_Jac].new(order = CDS, setup.omegaForFFT)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

  var tauExtFftArray: array[L, array[CDS, EC_G1_Jac]]
  getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, ecfft_desc)

  var fk20Proofs: array[CDS, EC_G1_Aff]
  kzg_coset_prove(
    tauExtFftArray, fk20Proofs, setup.testPoly, fr_fft_desc, ecfft_desc)

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

    var ys: array[L, Fr[BLS12_381]]
    ys.computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)

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
  when L == 4:
    const N = 32
    const CDS = 16
    const maxWidth = 64
  const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

  let setup = gen_setup(N, L, maxWidth, tauHex)

  # Create FFT descriptors for CDS=16
  let ecfft_desc = ECFFT_Descriptor[EC_ShortW_Jac[Fp[BLS12_381], G1]].new(order = CDS, setup.omegaForFFT)
  let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

  var tauExtFftArray: array[L, array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
  getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, ecfft_desc)

  var fk20Proofs: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  kzg_coset_prove(
    tauExtFftArray, fk20Proofs, setup.testPoly, fr_fft_desc, ecfft_desc)

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

    var ys: array[L, Fr[BLS12_381]]
    ys.computeEvalsAtCoset(setup.testPoly, h, setup.rootsOfUnity)

    var fk20Proof: EC_ShortW_Aff[Fp[BLS12_381], G1]
    fk20Proof = fk20Proofs[pos]

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

# proc testKzgCosetVerifyBatch(numTestCells: int) =
#   ## Test kzg_coset_verify_batch with configurable number of cells

#   const
#     N = 4096  # FIELD_ELEMENTS_PER_BLOB
#     L = 64    # FIELD_ELEMENTS_PER_CELL (coset size)
#     CDS = 128 # CELLS_PER_EXT_BLOB
#     maxWidth = 8192  # Full domain size = CDS * (N / L)
#     nBits = 7  # log2(128)

#   const tauHex = "0xa473319528c8b6ea4d08cc531800000000000000000000000000000000000000"

#   let setup = gen_setup(N, L, maxWidth, tauHex)

#   let ecfft_desc = ECFFT_Descriptor[EC_G1_Jac].new(order = CDS, setup.omegaForFFT)
#   let fr_fft_desc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = CDS, setup.omegaForFFT)

#   var tauExtFftArray: array[L, array[CDS, EC_G1_Jac]]
#   getTauExtFftArray(tauExtFftArray, setup.powers_of_tau_G1, ecfft_desc)

#   var fk20Proofs: array[CDS, EC_G1_Aff]
#   kzg_coset_prove(tauExtFftArray, fk20Proofs, setup.testPoly, fr_fft_desc, ecfft_desc)
#   fk20Proofs.bit_reversal_permutation()

#   var commitmentAff: EC_ShortW_Aff[Fp[BLS12_381], G1]
#   kzg_commit(setup.powers_of_tau_G1, commitmentAff, setup.testPolyBig)

#   # Compute roots of unity using fft_utils
#   let rootsOfUnity = computeRootsOfUnityBitReversed(Fr[BLS12_381], 8192)

#   # Get omegaD (D-th root of unity)
#   let omegaD = getRootOfUnityForScale(Fr[BLS12_381], 6)  # 2^6 = 64

#   let lthRoot = setup.omegaMax ~^ uint64(setup.maxWidth div L)

#   # Use seq for dynamic data
#   var cellIndices = newSeq[uint64](numTestCells)
#   var cosetsEvals = newSeq[array[L, Fr[BLS12_381]]](numTestCells)
#   var proofs = newSeq[EC_ShortW_Aff[Fp[BLS12_381], G1]](numTestCells)
#   var commitmentIndices = newSeq[uint64](numTestCells)

#   for i in 0 ..< numTestCells:
#     let cellIdx = uint64(i)
#     let domainPos = cellIdx * uint64(L)
#     let x = setup.omegaMax ~^ domainPos
#     let proofPos = reverseBits(uint32(cellIdx), uint32(nBits))

#     cellIndices[i] = cellIdx
#     commitmentIndices[i] = 0

#     computeYsAtCoset(cosetsEvals[i], setup.testPoly, x, lthRoot)
#     proofs[i] = fk20Proofs[proofPos]

#   # Compute powers of random challenge r
#   # FOR DEBUGGING: Hardcoded challenge (MUST MATCH PYTHON)
#   var r: Fr[BLS12_381]
#   r.fromHex("0x0a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20212223242526272829")
#   var rPowers = newSeq[Fr[BLS12_381]](numTestCells)
#   rPowers.asUnchecked().computePowers(r, numTestCells)

#   # Debug output
#   if numTestCells > 1:
#     echo "  [DEBUG] Challenge r = ", r.toHex()

#   type G1AffArray = ptr UncheckedArray[EC_ShortW_Aff[Fp[BLS12_381], G1]]
#   type G2AffArray = ptr UncheckedArray[EC_ShortW_Aff[Fp2[BLS12_381], G2]]

#   let srs_g1_ptr = cast[G1AffArray](unsafeAddr setup.powers_of_tau_G1.coefs[0])
#   let srs_g2_ptr = cast[G2AffArray](unsafeAddr setup.powers_of_tau_G2.coefs[0])

#   let verified = kzg_coset_verify_batch[BLS12_381, L](
#     cast[G1AffArray](commitmentAff.addr),
#     1,
#     commitmentIndices.asUnchecked(),
#     cellIndices.asUnchecked(),
#     cosetsEvals.asUnchecked(),
#     proofs.asUnchecked(),
#     numTestCells,
#     rPowers.asUnchecked(),
#     omegaD,
#     rootsOfUnity.asUnchecked(),
#     rootsOfUnity.len,
#     srs_g1_ptr,
#     srs_g2_ptr
#   )

#   doAssert verified, "Batch verification failed for " & $numTestCells & " cells"
#   echo "  ✓ Verified ", numTestCells, " cells"

# proc testKzgCosetVerifyBatch() =
#   ## Test kzg_coset_verify_batch with multiple cell counts
#   echo "Testing kzg_coset_verify_batch (EIP-7594)..."

#   const testCases = [1, 2, 3, 4, 5, 10, 16, 64]
#   for numCells in testCases:
#     echo "  Testing with ", numCells, " cells..."
#     testKzgCosetVerifyBatch(numCells)

#   echo "✓ kzg_coset_verify_batch all tests PASSED"

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

  # echo "---------------------------"

  # echo "EIP-7594 batch verification ... "
  # testKzgCosetVerifyBatch()

  echo "\n========================================"
  echo "    All KZG multiproofs tests PASSED ✓"
  echo "========================================"
