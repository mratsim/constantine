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
  constantine/ethereum_eip4844_kzg {.all.},
  constantine/serialization/[codecs_status_codes, codecs_bls12_381, endians],
  constantine/data_availability_sampling/eth_peerdas,
  constantine/commitments/kzg_multiproofs,
  constantine/hashes

import
  # stdlib - compile-time only
  std/typetraits

const prefix_eth_kzg = "ctt_eth_kzg_"
import ./zoo_exports

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

  KZGProofBytes* = array[BYTES_PER_PROOF, byte]
      ## Serialized KZG proof as 48 compressed G1 bytes.
      ## Use for I/O and FFI boundaries; convert to/from `KZGProof` (96 bytes)
      ## using `serialize_g1_compressed` / `deserialize_g1_compressed`.


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
  ## Output: L field elements in big-endian format
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

template `?`(status: cttEthKzgStatus): untyped {.dirty.} =
  ## Check KZG operation status and return early on error
  if status != cttEthKzg_Success:
    return status

func compute_cells_impl(
      ctx: ptr EthereumKZGContext,
      cells: var array[CELLS_PER_EXT_BLOB, Cell],
      poly_eval_brp: PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381], kBitReversed],
      poly_coef_nat: PolynomialCoef[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]]): cttEthKzgStatus =
  ## Compute all cells for an extended blob.
  ## poly_eval_brp: evaluation form (for first 64 cells)
  ## poly_coef_nat: coefficient form (for second 64 cells, no IFFT needed)
  const
    N = FIELD_ELEMENTS_PER_BLOB       # 4096
    L = FIELD_ELEMENTS_PER_CELL       # 64
    CDS = CELLS_PER_EXT_BLOB          # 128
    HALF_CDS = CDS div 2              # 64

  # ============================================================
  # Step 1: First 64 cells - DIRECT COPY (zero computation!)
  # ============================================================

  # The first half of the bit-reversed extended domain equals the original blob
  let cells_evals = allocHeapAligned(array[CDS, array[L, Fr[BLS12_381]]], alignment=64)
  defer: freeHeapAligned(cells_evals)
  copyMem(cells_evals[0][0].addr, poly_eval_brp.evals[0].addr, N*sizeof(Fr[BLS12_381]))

  # ============================================================
  # Step 2: Second 64 cells - shift + FFT (no IFFT needed!)
  # ============================================================

  # Shift coefficients by w_8192^k
  # w_8192 = primitive 8192nd root of unity (coset shift factor)
  var poly_coef_shifted = poly_coef_nat
  let w_8192 = ctx.fft_desc_ext.rootsOfUnity[1]
  poly_coef_shifted.coefs.shift_vals(poly_coef_shifted.coefs, w_8192)

  # FFT of shifted coefficients -> evaluations directly into cells 64-127
  let pHalfCells = cells_evals[HALF_CDS].asUnchecked()
  let fft_status = ctx.fft_desc_ext.fft_nr(pHalfCells.toOpenArray(N), poly_coef_shifted.coefs)
  doAssert fft_status == FFT_Success

  # ============================================================
  # Step 3: Serialize to bytes
  # ============================================================
  for i in 0 ..< CDS:
    cosetEvalsToCell(cells[i], cells_evals[i])

  return cttEthKzg_Success

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

  const N = FIELD_ELEMENTS_PER_BLOB

  # Deserialize blob to polynomial (evaluation form, bit-reversed)
  # Heap allocation to avoid 128KB stack usage (10% of Windows default 1MB stack)
  let poly_eval_brp = allocHeapAligned(PolynomialEval[N, Fr[BLS12_381], kBitReversed], 64)
  defer: freeHeapAligned(poly_eval_brp)

  ?blob_to_field_polynomial(poly_eval_brp, blob)

  # Convert to monomial form for compute_cells_impl
  let poly_coef_nat = allocHeapAligned(PolynomialCoef[N, Fr[BLS12_381]], 64)
  defer: freeHeapAligned(poly_coef_nat)
  poly_coef_nat[].lagrangeInterpolate(poly_eval_brp[], ctx.fft_desc_ext)

  return compute_cells_impl(ctx, cells, poly_eval_brp[], poly_coef_nat[])

func compute_cells_and_kzg_proofs*(
       ctx: ptr EthereumKZGContext,
       cells: ptr UncheckedArray[Cell],
       proofs: ptr UncheckedArray[KZGProofBytes],
       blob: Blob): cttEthKzgStatus {.libPrefix: prefix_eth_kzg, raises: [].} =
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

  ?blob_to_field_polynomial(poly_lagrange, blob)

  # Step 2: Convert to monomial form via IFFT (needed for FK20 proofs AND cells)
  let poly_monomial = allocHeapAligned(PolynomialCoef[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)
  defer: freeHeapAligned(poly_monomial)

  poly_monomial[].lagrangeInterpolate(poly_lagrange[], ctx.fft_desc_ext)

  # Step 3: Compute cells using the optimized half-FFT algorithm (reuses poly_monomial)
  ?compute_cells_impl(ctx, cast[ptr array[CELLS_PER_EXT_BLOB, Cell]](cells)[], poly_lagrange[], poly_monomial[])

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

  # Serialize proofs to compressed G1 format
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    ?serialize_g1_compressed(proofs[i], proofsAff[i])


  return cttEthKzg_Success

func deduplicateCommitments(
     commitmentIdx: var openArray[int],
     commitments: openArray[array[BYTES_PER_COMMITMENT, byte]]): int =
  ## Deduplicate commitments and return the number of unique commitments.
  ## commitmentIdx[i] stores the index of the unique commitment for cell i.
  ##
  ## ## Algorithm Complexity
  ##
  ## This implementation is **O(N × M)** where:
  ## - N = number of input commitments (cells in batch)
  ## - M = number of unique commitments (blobs, max 64 per EIP-7594)
  ##
  ## The Ethereum spec reference uses `list.index()` which scans the entire
  ## input list for each element, resulting in **O(N²)** complexity.
  ##
  ## ### Example: [A, A, B, B] (N=4, M=2)
  ##
  ## **Spec approach** (two passes):
  ## ```python
  ## # Pass 1: deduplicated = [c for i,c in enumerate(commitments)
  ## #                        if commitments.index(c) == i]
  ## # - i=0: scan all 4 items to find first A → 4 comparisons
  ## # - i=1: scan all 4 items to find first A → 4 comparisons
  ## # - i=2: scan all 4 items to find first B → 4 comparisons
  ## # - i=3: scan all 4 items to find first B → 4 comparisons
  ## # Total: 16 comparisons (N²)
  ##
  ## # Pass 2: indices = [deduplicated.index(c) for c in commitments]
  ## # - Each scans unique list (size M=2) → 2 comparisons each
  ## # Total: 8 comparisons (N×M)
  ## ```
  ##
  ## **Our approach** (single pass):
  ## ```nim
  ## # Scan only the growing unique buffer (size 0→M):
  ## # - i=0: scan 0 uniques → add A
  ## # - i=1: scan 1 unique (A) → found at index 0
  ## # - i=2: scan 1 unique (A) → add B
  ## # - i=3: scan 2 uniques (A,B) → found at index 1
  ## # Total: ~4 comparisons (N×M/2 average)
  ## ```
  ##
  ## ### Performance Impact
  ##
  ## For typical PeerDAS batch (N=1000 cells, M=64 blobs):
  ## - Spec: ~1,064,000 comparisons (N² + N×M)
  ## - Ours: ~32,000 comparisons (N×M/2)
  ## - **Speedup: ~33× fewer comparisons**
  ##
  ## ## Optimization: Byte-Level Comparison
  ##
  ## This function operates on **raw 48-byte commitments** instead of deserialized
  ## EC points for several reasons:
  ##
  ## 1. **Cache efficiency**: 48 bytes vs ~96 bytes for deserialized G1Affine
  ## 2. **Early exit**: memcmp exits on first differing byte
  ## 3. **No deserialization overhead**: Skip EC point validation for duplicates
  ## 4. **Random data**: Cryptographic commitments have uniform byte distribution,
  ##    so P(byte match) = 1/256, making early exit highly likely
  ##
  ## ### Birthday Paradox Consideration
  ##
  ## For byte-level comparison, the probability of two different commitments
  ## sharing the first k bytes is (1/256)^k. Even with the birthday paradox,
  ## for 48-byte cryptographic commitments:
  ## - P(first byte collision) = 1/256 ≈ 0.4%
  ## - P(first 2 bytes collision) = 1/65536 ≈ 0.0015%
  ##
  ## This means memcmp will exit after ~1-2 bytes on average for non-matching
  ## commitments, making byte comparison significantly faster than full EC point
  ## comparison.
  ##
  ## ## Example Usage
  ##
  ## ```nim
  ## Input:  [A, A, B, B]  (each is array[48, byte])
  ## Output: numUnique=2, commitmentIdx=[0, 0, 1, 1]
  ## Unique commitments: [A, B] (stored in uniqueBuffer[0..numUnique-1])
  ## ```
  ##
  ## ## Invariants
  ##
  ## - Order preserved: first occurrence of each commitment wins
  ## - commitmentIdx[i] ∈ [0, numUniqueCommitments-1]
  ## - uniqueBuffer[0..numUniqueCommitments-1] contains all distinct commitments
  ## - Semantically equivalent to Ethereum spec, but O(N×M) instead of O(N²)
  ##
  ## ## Other approaches considered
  ##
  ## - Open-Adressing Map -- O(N)
  ## - Red-Black Tree from BLST (rb_tree.c) -- O(N log N)
  ## - Sorting -- O(N log N)
  ##
  ## While asymptotic complexity looks much better our linear scan approach:
  ## - is cache friendly, buffers are processed linearly
  ## - due to KZGCommitment cryptographic property, only 1 byte is usually enough per commitment
  ##   scanned in the array if we use variable-time comparison
  ## - No large memory copies vs sorting
  ## - No complex rebalancing vs Red-Black Trees
  ## - No slots/modulos bookkeeping vs Open-Addressing Map
  debug:
    doAssert commitmentIdx.len == commitments.len

  var numUniqueCommitments = 0
  # Allocate buffer for unique commitments - size matches input (all could be unique)
  # Uses heap allocation like the rest of verify_cell_kzg_proof_batch
  let uniqueBuffer = allocHeapArrayAligned(array[BYTES_PER_COMMITMENT, byte], commitments.len, alignment = 64)
  defer: freeHeapAligned(uniqueBuffer)

  for i in 0 ..< commitments.len:
    var found = false
    for j in 0 ..< numUniqueCommitments:
      # Byte-level comparison: memcmp exits early on first differing byte
      # For cryptographic commitments, P(byte match) = 1/256, so ~1-2 bytes checked on average
      if uniqueBuffer[j] == commitments[i]:
        commitmentIdx[i] = j
        found = true
        break

    if not found:
      uniqueBuffer[numUniqueCommitments] = commitments[i]
      commitmentIdx[i] = numUniqueCommitments
      inc numUniqueCommitments

  return numUniqueCommitments

func compute_verify_cell_kzg_proof_batch_challenge(
       commitments: openArray[array[BYTES_PER_COMMITMENT, byte]],
       commitment_indices: openArray[int],
       cell_indices: openArray[CellIndex],
       cosets_evals: openArray[array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]],
       proofs: openArray[KZGProofBytes]): Fr[BLS12_381] =
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
      bls_field_to_bytes(evalBytes, eval)
      transcript.update(evalBytes)
    transcript.update(proofs[k])

  var hashTmp: array[32, byte]
  transcript.finish(hashTmp)
  result.fromDigest(hashTmp)

func verify_cell_kzg_proof_batch*(
       ctx: ptr EthereumKZGContext,
       commitments_bytes: ptr UncheckedArray[array[BYTES_PER_COMMITMENT, byte]],
       cell_indices: ptr UncheckedArray[CellIndex],
       cells: ptr UncheckedArray[Cell],
       proofs_bytes: ptr UncheckedArray[KZGProofBytes],
       n: int,
       secureRandomBytes: array[32, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg, raises: [].} =
  ## Verify that a set of cells belong to their corresponding commitments.
  ##
  ## This implements the universal verification equation from:
  ## https://ethresear.ch/t/a-universal-verification-equation-for-data-availability-sampling/13240
  ##
  ## Public method following the EIP-7594 spec.

  # Edge case: n < 0 is verification failure, n == 0 is trivially valid
  if n < 0:
    return cttEthKzg_VerificationFailure
  if n == 0:
    return cttEthKzg_Success

  # Validate cell indices are in bounds
  for i in 0 ..< n:
    if cell_indices[i] >= CELLS_PER_EXT_BLOB:
      return cttEthKzg_InputsLengthsMismatch
  # Deduplicate commitments FIRST (on raw bytes, before deserialization)
  # This is faster: byte comparison exits early, and we only deserialize uniques
  let commitmentIdx = allocHeapArrayAligned(int, n, alignment = 64)
  defer: freeHeapAligned(commitmentIdx)
  let numUniqueCommitments = deduplicateCommitments(
    commitmentIdx.toOpenArray(n),
    commitments_bytes.toOpenArray(0, n-1)
  )

  # Allocate and deserialize only unique commitments
  let uniqueCommitments = allocHeapArrayAligned(
    EC_ShortW_Aff[Fp[BLS12_381], G1], numUniqueCommitments, alignment = 64)
  defer: freeHeapAligned(uniqueCommitments)
  for i in 0 ..< numUniqueCommitments:
    # Find first occurrence of this unique commitment
    for j in 0 ..< n:
      if commitmentIdx[j] == i:
        ?uniqueCommitments[i].deserialize_g1_compressed(commitments_bytes[j])
        break

  let cosets_evals = allocHeapArrayAligned(
    array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]], n, alignment = 64)
  defer: freeHeapAligned(cosets_evals)
  let proofs = allocHeapArrayAligned(
    EC_ShortW_Aff[Fp[BLS12_381], G1], n, alignment = 64)
  defer: freeHeapAligned(proofs)
  let evalsCols = allocHeapArrayAligned(int, n, alignment = 64)
  defer: freeHeapAligned(evalsCols)
  let rPowers = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
  defer: freeHeapAligned(rPowers)


  block HappyPath:
    # Deserialize cells to coset evaluations
    for i in 0 ..< n:
      ?cellToCosetEvals(cosets_evals[i], cells[i])
      evalsCols[i] = int(cell_indices[i])

    # Deserialize proofs
    for i in 0 ..< n:
      ?proofs[i].deserialize_g1_compressed(proofs_bytes[i])
    var r: Fr[BLS12_381]
    if not r.getBatchBlindingFactor(secureRandomBytes):
      # Compute challenge r via Fiat-Shamir

      # Allocate unique commitments bytes for Fiat-Shamir challenge
      let uniqueCommitmentsBytes = allocHeapArrayAligned(
        array[BYTES_PER_COMMITMENT, byte], numUniqueCommitments, alignment = 64)
      for i in 0 ..< n:
        uniqueCommitmentsBytes[commitmentIdx[i]] = commitments_bytes[i]

      r = compute_verify_cell_kzg_proof_batch_challenge(
        uniqueCommitmentsBytes.toOpenArray(numUniqueCommitments),
        commitmentIdx.toOpenArray(n),
        cell_indices.toOpenArray(0, n-1),
        cosets_evals.toOpenArray(n),
        proofs_bytes.toOpenArray(0, n-1))

      freeHeapAligned(uniqueCommitmentsBytes)

    # Compute powers of r: [r^1, r^2, ..., r^{n}]
    rPowers.computePowers(r, n, skipOne = true)

    let verifyStatus = kzg_coset_verify_batch(
      uniqueCommitments = uniqueCommitments.toOpenArray(numUniqueCommitments),
      commitmentIdx = commitmentIdx.toOpenArray(n),
      proofs = proofs.toOpenArray(n),
      evals = cosets_evals.toOpenArray(n),
      evalsCols = evalsCols.toOpenArray(n),
      domain = ctx.fft_desc_ext,
      linearIndepRandNumbers = rPowers.toOpenArray(n),
      powers_of_tau = ctx.srs_monomial_g1.coefs,
      tau_pow_L_g2 = ctx.srs_monomial_g2.coefs[FIELD_ELEMENTS_PER_CELL],
      N = FIELD_ELEMENTS_PER_EXT_BLOB
    )
    result = if verifyStatus: cttEthKzg_Success else: cttEthKzg_VerificationFailure

  return result

func recover_cells_and_kzg_proofs*(
       ctx: ptr EthereumKZGContext,
       recovered_proofs: ptr UncheckedArray[KZGProofBytes],
       recovered_cells: ptr UncheckedArray[Cell],
       cell_indices: ptr UncheckedArray[CellIndex],
       cells: ptr UncheckedArray[Cell],
       n: int): cttEthKzgStatus {.libPrefix: prefix_eth_kzg, raises: [].} =
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

  # Step 1: Validation
  if n < CELLS_PER_EXT_BLOB div 2:
    return cttEthKzg_InputsLengthsMismatch

  if n > CELLS_PER_EXT_BLOB:
    return cttEthKzg_InputsLengthsMismatch

  # Validate bounds and uniqueness (strict ordering enforces both)
  for i in 0 ..< n:
    if uint64(cell_indices[i]) >= uint64(CELLS_PER_EXT_BLOB):
      return cttEthKzg_InputsLengthsMismatch
  for i in 1 ..< n:
    if uint64(cell_indices[i-1]) >= uint64(cell_indices[i]):
      return cttEthKzg_CellIndicesNotAscending

  # Step 2: Convert cells to coset evaluations [Deserialization]
  var cosets_evals = allocHeapArrayAligned(array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]], n, alignment = 64)
  defer: freeHeapAligned(cosets_evals)
  for i in 0 ..< n:
    let status = cellToCosetEvals(cosets_evals[i], cells[i])
    if status != cttEthKzg_Success:
      return status

  # Step 3: Recover polynomial coefficient form
  let poly_coeff = allocHeapAligned(PolynomialCoef[FIELD_ELEMENTS_PER_EXT_BLOB, Fr[BLS12_381]], alignment=64)
  defer: freeHeapAligned(poly_coeff)
  recoverPolynomialCoeff[
    FIELD_ELEMENTS_PER_BLOB, FIELD_ELEMENTS_PER_EXT_BLOB, FIELD_ELEMENTS_PER_CELL, CELLS_PER_EXT_BLOB
  ](poly_coeff[], cell_indices.toOpenArray(0, n-1), cosets_evals.toOpenArray(n), ctx.fft_desc_ext)

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
  let proofsAff = allocHeapAligned(array[CDS, EC_ShortW_Aff[Fp[BLS12_381], G1]], 64)
  defer: freeHeapAligned(proofsAff)

  kzg_coset_prove(
    proofsAff[],
    poly_coeff.coefs.toOpenArray(0, N-1),
    ctx.fft_desc_ext,
    ctx.ecfft_desc_ext,
    ctx.polyphaseSpectrumBank)

  # Bit-reverse permutation on proofs
  proofsAff[].bit_reversal_permutation()

  # Serialize proofs to compressed G1 format
  for i in 0 ..< CELLS_PER_EXT_BLOB:
    ?serialize_g1_compressed(recovered_proofs[i], proofsAff[i])

  return cttEthKzg_Success
