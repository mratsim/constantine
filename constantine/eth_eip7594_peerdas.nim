# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, polynomials/polynomials, polynomials/fft],
  constantine/math/arithmetic/finite_fields,
  constantine/math/io/io_fields,
  constantine/platforms/[primitives, views],
  constantine/commitments_setups/ethereum_kzg_srs,
  constantine/ethereum_eip4844_kzg,
  constantine/serialization/[codecs_status_codes, codecs_bls12_381],
  constantine/data_availability_sampling/eth_peerdas,
  constantine/commitments/kzg_multiproofs

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
## - verify_cell_kzg_proof_batch (TODO)
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

const RANDOM_CHALLENGE_KZG_CELL_BATCH_DOMAIN* = asBytes"RCKZGCBATCH__V1_"

const FIELD_ELEMENTS_PER_CELL* = 64
const CELLS_PER_EXT_BLOB* = FIELD_ELEMENTS_PER_EXT_BLOB div FIELD_ELEMENTS_PER_CELL
const BYTES_PER_CELL* = FIELD_ELEMENTS_PER_CELL * 32
const CELLS_PER_BLOB* = FIELD_ELEMENTS_PER_BLOB div FIELD_ELEMENTS_PER_CELL

type
  Cell* = array[BYTES_PER_CELL, byte]
    ## A cell is the fundamental unit of data availability sampling.
    ## Each cell contains 64 field elements (2048 bytes) that can be verified
    ## with a single KZG proof.

  CellIndex* = distinct uint64
    ## Index of a cell in the extended blob.
    ## Valid range: [0, CELLS_PER_EXT_BLOB)

  CommitmentIndex* = distinct uint64
    ## Index of a commitment in a batch.
    ## Used when verifying cells from multiple blobs.

  CosetEvals* = array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    ## Evaluations of a polynomial over a coset (64 points).
    ## This is the internal representation of a cell's data.

  Coset* = array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    ## The evaluation domain for a cell (a coset of roots of unity).

func `==`*(a, b: CellIndex): bool {.borrow.}
func `<`*(a, b: CellIndex): bool = uint64(a) < uint64(b)
func `==`*(a, b: CommitmentIndex): bool {.borrow.}
func `<`*(a, b: CommitmentIndex): bool = uint64(a) < uint64(b)

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

func cellToCosetEvals*(
       cell: openArray[byte],
       evals: var array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]): cttEthKzgStatus =
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

func cosetEvalsToCell*(
       evals: array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]],
       cell: var openArray[byte]) =
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
       blob: Blob,
       cells: var array[CELLS_PER_EXT_BLOB, Cell]): cttEthKzgStatus =
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
  poly_coef_nat.computeCoefPoly(poly_eval_brp, ctx.fft_desc_ext)

  # Step 3b: Shift coefficients by w_8192^k
  # w_8192 = primitive 8192nd root of unity (coset shift factor)
  let w_8192 = ctx.fft_desc_ext.rootsOfUnity[1]
  poly_coef_nat.coefs.shift_vals(poly_coef_nat.coefs, w_8192)

  # Step 3d: FFT of shifted coefficients -> evaluations directly into cells 64-127
  # fft_nn: natural input -> natural output
  let pHalfCells = cast[ptr UncheckedArray[Fr[BLS12_381]]](cells_evals[HALF_CDS][0].addr)
  var odd_evals: array[N, Fr[BLS12_381]]
  let fft_status = ctx.fft_desc_ext.fft_nn(pHalfCells.toOpenArray(N), poly_coef_nat.coefs)
  doAssert fft_status == FFT_Success

  # ============================================================
  # Step 4: Serialize to bytes
  # ============================================================
  for i in 0 ..< CDS:
    cosetEvalsToCell(cells_evals[i], cells[i])

  return cttEthKzg_Success


func compute_cells_and_kzg_proofs*(
       ctx: ptr EthereumKZGContext,
       blob: Blob,
       cells: var array[CELLS_PER_EXT_BLOB, Cell],
       proofs: var array[CELLS_PER_EXT_BLOB, KZGProof]): cttEthKzgStatus =
  ## Compute all cells and proofs for an extended blob using FK20 algorithm.
  ##
  ## Algorithm (following c-kzg-4844):
  ## 1. Convert blob to polynomial (Lagrange form) [Serialization]
  ## 2. Convert to monomial form via IFFT [4096 roots of unity] (for FK20 proofs)
  ## 3. Compute cells via zero-padding (no FFT!) [stays in evaluation form]
  ## 4. Compute FK20 proofs from monomial polynomial [4096 coeffs] + bit-reverse
  ## 5. Serialize cells and proofs to bytes

  # Step 1: Deserialize blob to polynomial (Lagrange form)
  var poly_lagrange {.noInit.}: PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381], kBitReversed]
  let status = blob_to_field_polynomial(poly_lagrange.addr, blob)
  case status
  of cttCodecScalar_Success:
    discard
  of cttCodecScalar_Zero:
    return cttEthKzg_ScalarZero
  of cttCodecScalar_ScalarLargerThanCurveOrder:
    return cttEthKzg_ScalarLargerThanCurveOrder

  # Step 2: Convert to monomial form via IFFT (needed for FK20 proofs)
  var poly_monomial: PolynomialCoef[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]]
  poly_monomial.computeCoefPoly(poly_lagrange, ctx.fft_desc_ext)

  # Step 3: Compute cells using the optimized half-FFT algorithm
  let cells_status = compute_cells(ctx, blob, cells)
  if cells_status != cttEthKzg_Success:
    return cells_status

  # Step 4: Compute FK20 proofs
  # Precompute tauExtFftArray (X_ext FFT columns) for all offsets
  # This corresponds to s->x_ext_fft_columns in c-kzg-4844
  const N = FIELD_ELEMENTS_PER_BLOB
  const L = FIELD_ELEMENTS_PER_CELL
  const CDS = CELLS_PER_EXT_BLOB


  # Compute tauExtFftArray (precomputed setup FFT for FK20 Phase 1)
  var tauExtFftArray: array[L, array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
  # Domain root for CDS=128: get from extended FFT descriptor (no shift)
  let domainRoot = ctx.fft_desc_ext.rootsOfUnity[CDS div 2]

  getTauExtFftArray[N, L, CDS, BLS12_381](tauExtFftArray, ctx.srs_monomial_g1, ctx.ecfft_desc_ext, domainRoot)

  # Compute FK20 proofs (Phase 1 + Phase 2)
  var proofsAff: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  kzg_coset_prove[N, L, CDS, BLS12_381](
    tauExtFftArray, proofsAff, poly_monomial,
    ctx.fft_desc_ext, ctx.ecfft_desc_ext)

  # Bit-reverse permutation on proofs (FK20 convention, matching c-kzg-4844)
  proofsAff.bit_reversal_permutation()

  # Convert proofs to KZGProof format
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    proofs[i] = KZGProof(proofsAff[i])

  return cttEthKzg_Success

func recover_cells_and_kzg_proofs*(
       ctx: ptr EthereumKZGContext,
       cell_indices: seq[CellIndex],
       cells: seq[Cell],
       recovered_cells: var array[CELLS_PER_EXT_BLOB, Cell],
       recovered_proofs: var array[CELLS_PER_EXT_BLOB, KZGProof]): cttEthKzgStatus =
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
  var cosets_evals: seq[array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]
  for i in 0 ..< num_cells:
    var evals: array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    let status = cellToCosetEvals(cells[i], evals)
    if status != cttEthKzg_Success:
      return status
    cosets_evals.add(evals)

  # Convert CellIndex to uint64
  var indices_uint: seq[uint64]
  for idx in cell_indices:
    indices_uint.add(uint64(idx))

  # Step 3: Recover polynomial coefficient form
  let poly_coeff = recoverPolynomialCoeff[
    FIELD_ELEMENTS_PER_BLOB, FIELD_ELEMENTS_PER_CELL, CELLS_PER_EXT_BLOB, BLS12_381
  ](indices_uint, cosets_evals, ctx.fft_desc_ext)

  # Step 4: Recompute all cells from recovered polynomial
  # Convert coefficient form to evaluation form via FFT, then slice into cells
  var cells_evals: array[CELLS_PER_EXT_BLOB, array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]

  # FFT: coefficient form -> evaluation form (bit-reversed order)
  var poly_evals_brp: array[FIELD_ELEMENTS_PER_EXT_BLOB, Fr[BLS12_381]]
  let fft_status = fft_nr(
    ctx.fft_desc_ext,
    poly_evals_brp.toOpenArray(0, FIELD_ELEMENTS_PER_EXT_BLOB-1),
    poly_coeff.coefs.toOpenArray(0, FIELD_ELEMENTS_PER_EXT_BLOB-1)
  )
  doAssert fft_status == FFT_Success

  # Bit-reverse to match cell ordering
  var poly_evals: array[FIELD_ELEMENTS_PER_EXT_BLOB, Fr[BLS12_381]]
  bit_reversal_permutation(
    poly_evals.toOpenArray(0, FIELD_ELEMENTS_PER_EXT_BLOB-1),
    poly_evals_brp.toOpenArray(0, FIELD_ELEMENTS_PER_EXT_BLOB-1)
  )

  # Slice into cells
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    for j in 0 ..< FIELD_ELEMENTS_PER_CELL:
      cells_evals[i][j] = poly_evals[i * FIELD_ELEMENTS_PER_CELL + j]

  # Step 5: Convert cells to bytes [Serialization]
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    cosetEvalsToCell(cells_evals[i], recovered_cells[i])

  # Step 6: Compute FK20 proofs
  # Truncate recovered polynomial (8192 coeffs) to original size (4096 coeffs)
  var poly_coeff_N: PolynomialCoef[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]]
  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    poly_coeff_N.coefs[i] = poly_coeff.coefs[i]

  const N = FIELD_ELEMENTS_PER_BLOB
  const L = FIELD_ELEMENTS_PER_CELL
  const CDS = CELLS_PER_EXT_BLOB


  # Compute tauExtFftArray (precomputed setup FFT for FK20 Phase 1)
  var tauExtFftArray: array[L, array[CDS, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
  let domainRoot = ctx.fft_desc_ext.rootsOfUnity[CDS div 2]
  getTauExtFftArray[N, L, CDS, BLS12_381](tauExtFftArray, ctx.srs_monomial_g1, ctx.ecfft_desc_ext, domainRoot)

  # Compute FK20 proofs
  var proofsAff: array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  kzg_coset_prove[N, L, CDS, BLS12_381](
    tauExtFftArray, proofsAff, poly_coeff_N,
    ctx.fft_desc_ext, ctx.ecfft_desc_ext)

  # Bit-reverse permutation on proofs
  proofsAff.bit_reversal_permutation()

  for i in 0 ..< CELLS_PER_EXT_BLOB:
    recovered_proofs[i] = KZGProof(proofsAff[i])

  return cttEthKzg_Success
