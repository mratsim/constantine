# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, extension_fields, polynomials/polynomials, polynomials/fft_fields],
  constantine/math/arithmetic/[finite_fields, limbs_montgomery],
  constantine/math/io/[io_bigints, io_fields],
  constantine/platforms/[primitives, views, allocs],
  constantine/commitments_setups/ethereum_kzg_srs,
  constantine/ethereum_eip4844_kzg,
  constantine/serialization/[codecs_status_codes, codecs_bls12_381, endians],
  constantine/data_availability_sampling/eth_peerdas,
  constantine/commitments/kzg_multiproofs,
  constantine/hashes

import
  # stdlib - compile-time only
  std/typetraits

## ############################################################
##
##          EIP-7594 PeerDAS - Data Availability Sampling
##
## ############################################################
##
## This module provides the Ethereum-specific serialization layer for PeerDAS.
## It handles Blob/Cell byte conversions and wraps the generic eth_peerdas implementation.
##
## Public API:
## - compute_cells
## - compute_cells_and_kzg_proofs
## - recover_cells_and_kzg_proofs
## - verify_cell_kzg_proof_batch
##
## Background on PeerDAS
## ~~~~~~~~~~~~~~~~~~~~~~
##
## In Ethereum's data sharding proposal, blobs are large (128KB) pieces of data
## that need to be verified for availability without downloading the entire blob.
## DAS allows nodes to sample random chunks (cells) of the blob and verify their
## availability with cryptographic proofs.
##
## Key concepts:
## - **Blob**: 4096 field elements (32 bytes each) = 128KB of data
## - **Cell**: 64 field elements = 2048 bytes (one unit of data with proof)
## - **Extended Blob**: 8192 field elements (Reed-Solomon encoding with 2x redundancy)
## - **Cells per Blob**: 64 (4096/64)
## - **Cells per Extended Blob**: 128 (8192/64)
##
## The process:
## 1. **Commit**: Convert blob to polynomial, commit to get KZG commitment
## 2. **Cell Computation**: Extend polynomial via FFT, compute cells with proofs
## 3. **Sampling**: DA samplers request random cells
## 4. **Verification**: Verify cell proofs against commitment
## 5. **Recovery**: If ≥50% of cells available, recover all cells
##
## References:
## - EIP-7594: https://eips.ethereum.org/EIPS/eip-7594
## - Spec: https://github.com/ethereum/consensus-specs/blob/v1.4.0-beta.1/specs/fulu/polynomial-commitments-sampling.md
## - FK20 Paper: https://eprint.iacr.org/2023/033

{.push raises:[].}  # No exceptions for crypto
{.push checks:off.} # We want unchecked int and array accesses

const RANDOM_CHALLENGE_KZG_CELL_BATCH_DOMAIN* = asBytes"RCKZGCBATCH__V1_"

# Re-export PeerDAS constants from canonical source (ethereum_kzg_srs.nim)
export ethereum_kzg_srs.FIELD_ELEMENTS_PER_CELL
export ethereum_kzg_srs.CELLS_PER_EXT_BLOB
export ethereum_kzg_srs.BYTES_PER_CELL
export ethereum_kzg_srs.CELLS_PER_BLOB

type
  Cell* = array[BYTES_PER_CELL, byte]
    ## A cell is the fundamental unit of data availability sampling.
    ## Each cell contains 64 field elements (2048 bytes) that can be verified
    ## with a single KZG proof.

  CellIndex* = uint64
    ## Index of a cell in the extended blob.
    ## Valid range: [0, CELLS_PER_EXT_BLOB)

  CosetEvals* = array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    ## Evaluations of a polynomial over a coset (64 points).
    ## This is the internal representation of a cell's data.

  Coset* = array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    ## The evaluation domain for a cell (a coset of roots of unity).

# ============================================================
#
#           Serialization (Bytes <-> Field Elements)
#
# ============================================================

func bytesToBlsField(dst: var Fr[BLS12_381], src: array[32, byte]): CttCodecScalarStatus =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  var scalar {.noInit.}: Fr[BLS12_381].getBigInt()
  let status = scalar.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  dst.fromBig(scalar)
  return cttCodecScalar_Success

func cellToCosetEvals(
       evals: var array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]],
       cell: openArray[byte]): cttEthKzgStatus =
  ## Convert cell bytes to coset evaluations (field elements).
  ## Input:  L * 32 bytes
  ## Output: L field elements in little-endian format
  ## Returns: cttEthKzg_Success on success, error status otherwise
  for i in 0 ..< FIELD_ELEMENTS_PER_CELL:
    let start = i * 32
    var chunk: array[32, byte]
    for j in 0 ..< 32:
      chunk[j] = cell[start + j]
    let status = bytesToBlsField(evals[i], chunk)
    if status != cttCodecScalar_Success:
      return cttEthKzg_ScalarLargerThanCurveOrder
  return cttEthKzg_Success

func cosetEvalsToCell(
       cell: var openArray[byte],
       evals: array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]) =
  ## Convert coset evaluations to cell bytes.
  ## Input:  L field elements
  ## Output: L * 32 bytes in big-endian format
  for i in 0 ..< FIELD_ELEMENTS_PER_CELL:
    let start = i * 32
    var chunk: array[32, byte]
    discard marshal(chunk, evals[i], bigEndian)
    for j in 0 ..< 32:
      cell[start + j] = chunk[j]

# ============================================================
#
#           Public API
#
# ============================================================

func compute_cells*(
       ctx: ptr EthereumKZGContext,
       cells: var array[CELLS_PER_EXT_BLOB, Cell],
       blob: Blob): cttEthKzgStatus =
  ## Compute all cells for an extended blob using the half-FFT optimization.
  ## This is the MOST efficient known method for computing cells.
  ##
  ## Key insight: Due to bit-reversal permutation properties, the first half
  ## of the extended blob is IDENTICAL to the original blob. The second half
  ## only requires a single size-4096 FFT (not 8192).
  ##
  ## Mathematical background:
  ## ------------------------
  ## Consider bit-reversal of indices 0..8191 (for 8192 elements, 13 bits):
  ## - After bit-reversal, indices with LSB=0 map to first half [0, 4095]
  ## - Indices with LSB=1 map to second half [4096, 8191]
  ##
  ## The 8192 roots of unity: w_8192^0, w_8192^1, ..., w_8192^8191
  ## After bit-reversal:
  ## - First 4096 positions: w_8192^(even) = w_4096^k  (same as original blob!)
  ## - Second 4096 positions: w_8192^(odd) = w_8192 * w_4096^k (coset shift)
  ##
  ## Since blob is degree-4095 polynomial in evaluation form at w_4096^k,
  ## the first half of extended blob equals original blob evaluations!
  ##
  ## For second half, evaluate at w_8192 * w_4096^k:
  ## 1. Convert to coefficient form (IFFT size 4096)
  ## 2. Multiply coeff k by w_8192^k (shift)
  ## 3. Evaluate at w_4096^k (FFT size 4096)
  ##
  ## Complexity:
  ## - First 64 cells: O(1) - direct copy (zero computation!)
  ## - Second 64 cells: 1 IFFT(4096) + 1 FFT(4096) + O(4096) shift
  ##
  ## Total: ~2x faster than full FFT, ~370x faster than naive O(n²)
  ##
  ## Algorithm:
  ## 1. Deserialize blob to polynomial (evaluation form, bit-reversed) [Serialization]
  ## 2. First 64 cells: Direct copy from blob
  ## 3. Second 64 cells:
  ##    a. Bit-reverse to natural order
  ##    b. IFFT to coefficient form
  ##    c. Shift coefficients by w_8192^k
  ##    d. FFT to get evaluations
  ##    e. Bit-reverse to match cell ordering
  ## 4. Convert cells to bytes [Serialization]

  const
    N = FIELD_ELEMENTS_PER_BLOB       # 4096
    L = FIELD_ELEMENTS_PER_CELL       # 64
    CDS = CELLS_PER_EXT_BLOB          # 128
    HALF_CDS = CDS div 2              # 64

  # ============================================================
  # Step 1: Deserialize blob to polynomial (evaluation form, bit-reversed)
  # ============================================================
  var poly_eval_brp {.noInit.}: PolynomialEval[N, Fr[BLS12_381], kBitReversed]
  let status = blob_to_field_polynomial(poly_eval_brp.addr, blob)
  case status
  of cttCodecScalar_Success:
    discard
  of cttCodecScalar_Zero:
    return cttEthKzg_ScalarZero
  of cttCodecScalar_ScalarLargerThanCurveOrder:
    return cttEthKzg_ScalarLargerThanCurveOrder

  # ============================================================
  # Step 2: First 64 cells - DIRECT COPY (zero computation!)
  # ============================================================
  # The first half of the bit-reversed extended domain equals the original blob
  var cells_evals {.noInit.}: array[CDS, array[L, Fr[BLS12_381]]]
  copyMem(cells_evals[0][0].addr, poly_eval_brp.evals[0].addr, N*sizeof(Fr[BLS12_381]))

  # ============================================================
  # Step 3: Second 64 cells - IFFT + shift + FFT
  # ============================================================
  # Following the Python reference implementation exactly:
  # 1. Bit-reverse blob (bit-reversed eval form -> natural eval form)
  # 2. IFFT (natural eval -> coefficients)
  # 3. Shift coefficients by w_8192^k
  # 4. FFT (coefficients -> natural eval form)
  # 5. Bit-reverse output (natural eval -> bit-reversed eval for cells)

  # Step 3a: Lagrange -> Monomial form
  var poly_coef_nat: PolynomialCoef[N, Fr[BLS12_381]]
  poly_coef_nat.lagrangeInterpolate(poly_eval_brp, ctx.fft_desc_ext)

  # Step 3b: Shift coefficients by w_8192^k
  # w_8192 = primitive 8192nd root of unity (coset shift factor)
  let w_8192 = ctx.fft_desc_ext.rootsOfUnity[1]
  poly_coef_nat.coefs.shift_vals(poly_coef_nat.coefs, w_8192)

  # Step 3d: FFT of shifted coefficients -> evaluations directly into cells 64-127
  let pHalfCells = cells_evals[HALF_CDS].asUnchecked()
  var odd_evals: array[N, Fr[BLS12_381]]
  let fft_status = ctx.fft_desc_ext.fft_nr(pHalfCells.toOpenArray(N), poly_coef_nat.coefs)
  doAssert fft_status == FFT_Success

  # ============================================================
  # Step 4: Serialize to bytes
  # ============================================================
  for i in 0 ..< CDS:
    cosetEvalsToCell(cells[i], cells_evals[i])

  return cttEthKzg_Success

func compute_cells_and_kzg_proofs*(
       ctx: ptr EthereumKZGContext,
       cells: var array[CELLS_PER_EXT_BLOB, Cell],
       proofs: var array[CELLS_PER_EXT_BLOB, KZGProof],
       blob: Blob): cttEthKzgStatus {.raises: [].} =
  ## Compute all cells and proofs for an extended blob using FK20 algorithm.
  ##
  ## Algorithm:
  ## 1. Convert blob to polynomial (Lagrange form) [Serialization]
  ## 2. Convert to monomial form via IFFT [4096 roots of unity] (for FK20 proofs)
  ## 3. Compute cells via zero-padding (no FFT!) [stays in evaluation form]
  ## 4. Compute FK20 proofs from monomial polynomial [4096 coeffs] + bit-reverse
  ## 5. Serialize cells and proofs to bytes

  # Step 1: Deserialize blob to polynomial (Lagrange form)
  let poly_lagrange = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381], kBitReversed], 64)
  defer: freeHeapAligned(poly_lagrange)

  let status = blob_to_field_polynomial(poly_lagrange, blob)
  case status
  of cttCodecScalar_Success:
    discard
  of cttCodecScalar_Zero:
    return cttEthKzg_ScalarZero
  of cttCodecScalar_ScalarLargerThanCurveOrder:
    return cttEthKzg_ScalarLargerThanCurveOrder

  # Step 2: Convert to monomial form via IFFT (needed for FK20 proofs)
  let poly_monomial = allocHeapAligned(PolynomialCoef[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)
  defer: freeHeapAligned(poly_monomial)

  poly_monomial[].lagrangeInterpolate(poly_lagrange[], ctx.fft_desc_ext)

  # Step 3: Compute cells using the optimized half-FFT algorithm
  let cells_status = compute_cells(ctx, cells, blob)
  if cells_status != cttEthKzg_Success:
    return cells_status

  # Step 4: Compute FK20 proofs
  const N = FIELD_ELEMENTS_PER_BLOB
  const L = FIELD_ELEMENTS_PER_CELL
  const CDS = CELLS_PER_EXT_BLOB

  # Compute FK20 proofs (Phase 1 + Phase 2) using precomputed SRS polyphase spectrum bank
  let proofsAff = allocHeapAligned(array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]], 64)
  defer: freeHeapAligned(proofsAff)

  kzg_coset_prove(
    proofsAff[], poly_monomial[].coefs.toOpenArray(0, N-1),
    ctx.fft_desc_ext, ctx.ecfft_desc_ext, ctx.polyphaseSpectrumBank)

  # Bit-reverse permutation on proofs (Ethereum PeerDAS convention)
  proofsAff[].bit_reversal_permutation()

  # Convert proofs to KZGProof format
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    proofs[i] = KZGProof(proofsAff[i])

  return cttEthKzg_Success

func deduplicateCommitments*(
       commitmentIdx: var openArray[int],
       commitments: openArray[EC_ShortW_Aff[Fp[BLS12_381], G1]]): int =
  ## Deduplicate commitments and return the number of unique commitments.
  ## commitmentIdx[i] stores the index of the unique commitment for cell i.
  ## This function will be optimized in a future refactoring.
  debug:
    doAssert commitmentIdx.len == commitments.len

  var numUniqueCommitments = 0
  for i in 0 ..< commitments.len:
    var found = false
    for j in 0 ..< numUniqueCommitments:
      if bool(commitments[j] == commitments[i]):
        commitmentIdx[i] = j
        found = true
        break

    if not found:
      commitmentIdx[i] = numUniqueCommitments
      inc numUniqueCommitments

  return numUniqueCommitments

func compute_verify_cell_kzg_proof_batch_challenge*(
       commitments: openArray[array[BYTES_PER_COMMITMENT, byte]],
       commitment_indices: openArray[int],
       cell_indices: openArray[int],
       cosets_evals: openArray[array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]],
       proofs: openArray[array[BYTES_PER_PROOF, byte]]): Fr[BLS12_381] =
  ## Compute the Fiat-Shamir challenge r for batch verification.
  ## Follows the spec: hash all inputs with domain separator to get random field element.
  var transcript {.noInit.}: sha256
  transcript.init()

  transcript.update(RANDOM_CHALLENGE_KZG_CELL_BATCH_DOMAIN)

  let numCommitments = len(commitments)
  let numCellIndices = len(cell_indices)

  transcript.update(toBytes(uint64(FIELD_ELEMENTS_PER_BLOB), bigEndian))
  transcript.update(toBytes(uint64(FIELD_ELEMENTS_PER_CELL), bigEndian))
  transcript.update(toBytes(uint64(numCommitments), bigEndian))
  transcript.update(toBytes(uint64(numCellIndices), bigEndian))

  for commitment in commitments:
    transcript.update(commitment)

  for k in 0 ..< numCellIndices:
    transcript.update(toBytes(uint64 commitment_indices[k], bigEndian))
    transcript.update(toBytes(uint64 cell_indices[k], bigEndian))
    for eval in cosets_evals[k]:
      var evalBytes: array[32, byte]
      discard bls_field_to_bytes(evalBytes, eval)
      transcript.update(evalBytes)
    transcript.update(proofs[k])

  var hashTmp: array[32, byte]
  transcript.finish(hashTmp)
  result.fromDigest(hashTmp)

func verify_cell_kzg_proof_batch*(
       ctx: ptr EthereumKZGContext,
       commitments_bytes: openArray[array[BYTES_PER_COMMITMENT, byte]],
       cell_indices: openArray[int],
       cells: openArray[Cell],
       proofs_bytes: openArray[array[BYTES_PER_PROOF, byte]],
       secureRandomBytes: array[32, byte]): bool =
  ## Verify that a set of cells belong to their corresponding commitments.
  ##
  ## This implements the universal verification equation from:
  ## https://ethresear.ch/t/a-universal-verification-equation-for-data-availability-sampling/13240
  ##
  ## Public method following the EIP-7594 spec.

  # Validate input lengths
  if len(commitments_bytes) != len(cells) or
     len(commitments_bytes) != len(proofs_bytes) or
     len(commitments_bytes) != len(cell_indices):
    return false

  # Validate cell indices are in bounds
  for cell_idx in cell_indices:
    if cell_idx >= CELLS_PER_EXT_BLOB:
      return false

  # Edge case: zero cells is trivially valid
  if len(cell_indices) == 0:
    return true

  let numCells = len(cell_indices)

  let cosets_evals = allocHeapArrayAligned(
    array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]], numCells, alignment = 64)
  let commitments = allocHeapArrayAligned(
    EC_ShortW_Aff[Fp[BLS12_381], G1], numCells, alignment = 64)
  let proofs = allocHeapArrayAligned(
    EC_ShortW_Aff[Fp[BLS12_381], G1], numCells, alignment = 64)
  let commitmentIdx = allocHeapArrayAligned(int, numCells, alignment = 64)
  let evalsCols = allocHeapArrayAligned(int, numCells, alignment = 64)
  let rPowers = allocHeapArrayAligned(Fr[BLS12_381], numCells, alignment = 64)

  block HappyPath:
    # Deserialize cells to coset evaluations
    for i in 0 ..< numCells:
      let status = cellToCosetEvals(cosets_evals[i], cells[i])
      if status != cttEthKzg_Success:
        result = false
        break HappyPath
      evalsCols[i] = int(cell_indices[i])

    # Deserialize commitments
    for i in 0 ..< numCells:
      let status = commitments[i].deserialize_g1_compressed(commitments_bytes[i])
      if status notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
        result = false
        break HappyPath

    # Deserialize proofs
    for i in 0 ..< numCells:
      let status = proofs[i].deserialize_g1_compressed(proofs_bytes[i])
      if status notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
        result = false
        break HappyPath

    # Deduplicate commitments
    let numUniqueCommitments = deduplicateCommitments(
      commitmentIdx.toOpenArray(numCells),
      commitments.toOpenArray(numCells)
    )

    # Create compacted unique commitments array
    # commitmentIdx[i] gives the index into unique commitments for cell i
    # Since deduplication preserves order, the first cell with each unique index
    # contains the actual unique commitment
    let uniqueCommitments = allocHeapArrayAligned(
      EC_ShortW_Aff[Fp[BLS12_381], G1], numUniqueCommitments, alignment = 64)
    for i in 0 ..< numCells:
      uniqueCommitments[commitmentIdx[i]] = commitments[i]

    var r: Fr[BLS12_381]
    if not r.getBatchBlindingFactor(secureRandomBytes):
      # Compute challenge r via Fiat-Shamir

      # Allocate unique commitments bytes for Fiat-Shamir challenge
      let uniqueCommitmentsBytes = allocHeapArrayAligned(
        array[BYTES_PER_COMMITMENT, byte], numUniqueCommitments, alignment = 64)
      for i in 0 ..< numCells:
        uniqueCommitmentsBytes[commitmentIdx[i]] = commitments_bytes[i]

      r = compute_verify_cell_kzg_proof_batch_challenge(
        uniqueCommitmentsBytes.toOpenArray(numUniqueCommitments),
        commitmentIdx.toOpenArray(numCells),
        cell_indices,
        cosets_evals.toOpenArray(numCells),
        proofs_bytes)

      freeHeapAligned(uniqueCommitmentsBytes)

    # Compute powers of r: [r^1, r^2, ..., r^{numCells}]
    rPowers.computePowers(r, numCells, skipOne = true)

    result = kzg_coset_verify_batch(
      uniqueCommitments = uniqueCommitments.toOpenArray(numUniqueCommitments),
      commitmentIdx = commitmentIdx.toOpenArray(numCells),
      proofs = proofs.toOpenArray(numCells),
      evals = cosets_evals.toOpenArray(numCells),
      evalsCols = evalsCols.toOpenArray(numCells),
      domain = ctx.fft_desc_ext,
      linearIndepRandNumbers = rPowers.toOpenArray(numCells),
      powers_of_tau = ctx.srs_monomial_g1.coefs,
      tau_pow_L_g2 = ctx.srs_monomial_g2.coefs[FIELD_ELEMENTS_PER_CELL],
      N = FIELD_ELEMENTS_PER_EXT_BLOB
    )

    freeHeapAligned(uniqueCommitments)


  freeHeapAligned(rPowers)
  freeHeapAligned(evalsCols)
  freeHeapAligned(commitmentIdx)
  freeHeapAligned(proofs)
  freeHeapAligned(commitments)
  freeHeapAligned(cosets_evals)

  return result

func recover_cells_and_kzg_proofs*(
       ctx: ptr EthereumKZGContext,
       recovered_proofs: var array[CELLS_PER_EXT_BLOB, KZGProof],
       recovered_cells: var array[CELLS_PER_EXT_BLOB, Cell],
       cells: openArray[Cell],
       cell_indices: openArray[CellIndex]): cttEthKzgStatus {.raises: [].} =
  ## Given at least 50% of cells for a blob, recover all cells/proofs.
  ## This is the main entry point for recovery with serialization.
  ##
  ## Algorithm:
  ## 1. Validate inputs (length, duplicates, bounds)
  ## 2. Convert cells to coset evaluations [Deserialization]
  ## 3. Recover polynomial coefficient form via FFT-based recovery
  ##    [Domain: 2*N roots of unity, Coset shift: SCALE_FACTOR=5]
  ## 4. Recompute all cells from recovered polynomial
  ## 5. Convert cells to bytes [Serialization]

  let num_cells = cell_indices.len

  # Step 1: Validation
  if num_cells != cells.len:
    return cttEthKzg_InputsLengthsMismatch

  if num_cells < CELLS_PER_EXT_BLOB div 2:
    return cttEthKzg_InputsLengthsMismatch

  if num_cells > CELLS_PER_EXT_BLOB:
    return cttEthKzg_InputsLengthsMismatch

  # Check that input is sorted and has no duplicates
  for i in 1 ..< num_cells:
    if uint64(cell_indices[i-1]) >= uint64(cell_indices[i]):
      return cttEthKzg_InputsLengthsMismatch

  # Step 2: Convert cells to coset evaluations [Deserialization]
  var cosets_evals = allocHeapArrayAligned(array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]], num_cells, alignment = 64)
  defer: freeHeapAligned(cosets_evals)
  for i in 0 ..< num_cells:
    let status = cellToCosetEvals(cosets_evals[i], cells[i])
    if status != cttEthKzg_Success:
      return status

  # Step 3: Recover polynomial coefficient form
  let poly_coeff = allocHeapAligned(PolynomialCoef[FIELD_ELEMENTS_PER_EXT_BLOB, Fr[BLS12_381]], alignment=64)
  defer: freeHeapAligned(poly_coeff)
  recoverPolynomialCoeff[
    FIELD_ELEMENTS_PER_BLOB, FIELD_ELEMENTS_PER_EXT_BLOB, FIELD_ELEMENTS_PER_CELL, CELLS_PER_EXT_BLOB
  ](poly_coeff[], cell_indices, cosets_evals.toOpenArray(num_cells), ctx.fft_desc_ext)

  # Step 4: Recompute all cells from recovered polynomial
  # FFT: coefficient form -> evaluation form (bit-reversed order)
  # cells_evals has identical memory layout to array[FIELD_ELEMENTS_PER_EXT_BLOB, Fr]
  # so we can FFT directly into it, avoiding intermediate allocations and copies
  let cells_evals = allocHeapAligned(array[CELLS_PER_EXT_BLOB, array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]], 64)
  defer: freeHeapAligned(cells_evals)
  let fft_status = ctx.fft_desc_ext.fft_nr(
    cells_evals[0].asUnchecked().toOpenArray(FIELD_ELEMENTS_PER_EXT_BLOB), # Flatten 2D -> 1D
    poly_coeff.coefs
  )
  doAssert fft_status == FFT_Success

  # Step 5: Convert cells to bytes [Serialization]
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    cosetEvalsToCell(recovered_cells[i], cells_evals[i])

  # Step 6: Compute FK20 proofs
  # Truncate recovered polynomial (8192 coeffs) to original size (4096 coeffs) via slicing
  const N = FIELD_ELEMENTS_PER_BLOB
  const CDS = CELLS_PER_EXT_BLOB

  # Compute FK20 proofs using precomputed SRS polyphase spectrum bank
  kzg_coset_prove(
    cast[var array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]](
      # KZGProof is distinct EC_ShortW_Aff[Fp[BLS12_381], G1]
      recovered_proofs.addr
    ),
    poly_coeff.coefs.toOpenArray(0, N-1),
    ctx.fft_desc_ext,
    ctx.ecfft_desc_ext,
    ctx.polyphaseSpectrumBank)

  # Bit-reverse permutation on proofs
  recovered_proofs.bit_reversal_permutation()

  return cttEthKzg_Success
