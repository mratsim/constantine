# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/algorithm,
  constantine/named/[algebras],
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/math/polynomials/[polynomials, fft_fields],
  constantine/platforms/allocs,
  constantine/platforms/views

## ############################################################
##
##          EIP-7594 PeerDAS - Generic Internal Implementation
##
## ############################################################
##
## This module contains the generic internal implementation of PeerDAS.
## It operates on validated inputs and does not deal with serialization.
## No EthereumKZGContext is used here - only raw polynomials, domains, FFTs.
##
## This module deals ONLY with cosets operations.
## Cell<->coset conversions and serialization are in eth_eip7594_peerdas.nim.
##
## NOTE: There is a similar but separate generic recovery implementation in
##       constantine/erasure_codes/recovery.nim (recoverPolyFromSamples).
##       These two implementations should be consolidated in future refactoring.
##
## Nomenclature (following kzg_multiprove.nim conventions):
## - N: Polynomial size (4096 for blobs)
## - L: Coset size (64 field elements per cell)
## - CDS: Circulant Domain Size = 2 * N/L (128 for extended blob)
##
## Relationship: CDS * L = 2 * N
## Given any two, the third can be derived.
##
## For EIP-7594 PeerDAS:
##   N = 4096, L = 64, CDS = 128

{.push checks:off, raises:[].}

# ============================================================
#
#           Vanishing Polynomial Helper
#
# ============================================================

func computeMissingCells[CDS: static int](
       cell_indices: openArray[uint64]): set[0 .. CDS-1] =
  ## Compute the set of missing cell indices.
  ## Use card(result) to get the count.

  var cell_present: set[0 .. CDS-1]
  for j in 0 ..< cell_indices.len:
    cell_present.incl(int(cell_indices[j]))

  # Build missing cells set as complement
  for i in 0 ..< CDS:
    if i notin cell_present:
      result.incl(i)

func fillMissingCellIndices[CDS: static int](
       missing_cell_indices: var openArray[uint64],
       missing_cells: set[0 .. CDS-1]) =
  ## Fill array with bit-reversed missing cell indices.
  ## @param missing_cell_indices: pre-allocated array of size card(missing_cells)

  let bitrev_bits = uint64(log2_vartime(uint32 CDS))
  var mci_idx = 0
  for i in missing_cells:
    missing_cell_indices[mci_idx] = reverseBits(uint64(i), bitrev_bits)
    inc mci_idx

template check(expression: FFT_Status) =
  let fft_status = expression
  doAssert fft_status == FFT_Success

func buildVanishingPolynomial[L, CDS: static int](
       output: var StridedView[Fr[BLS12_381]],
       missing_cell_indices: openArray[uint64],
       fft_desc: FrFFT_Descriptor[Fr[BLS12_381]],
       ext_size: int,
       num_cells_total: int) =
  ## Build vanishing polynomial Z(x) = ∏(x - r_i) for missing cells
  ## output: strided view with stride L into the full domain array
  ## output[0], output[1], ..., output[k] contain coefficients at positions 0, L, 2L, ...
  let missing_cell_count = missing_cell_indices.len

  # Strided view of roots at positions of missing cells
  let stride = ext_size div num_cells_total
  let roots_view = fft_desc.rootsOfUnity.toStridedView(ext_size).slice(0, ext_size - 1, stride)

  if missing_cell_count == 0:
    output[0].setOne()
    return

  # Build polynomial incrementally: Z(x) = ∏(x - r_i)
  # Start with Z(x) = (x - r_0) = -r_0 + x
  output[0].neg(roots_view[int(missing_cell_indices[0])])

  for i in 1 ..< missing_cell_count:
    # Multiply current polynomial by (x - r_i)
    # New coefficients: [c₀, c₁, ..., cᵢ₋₁, 0] * (x - r_i)
    # = [-r_i*c₀, c₀-r_i*c₁, c₁-r_i*c₂, ..., cᵢ₋₁]
    var neg_root {.noInit.}: Fr[BLS12_381]
    neg_root.neg(roots_view[int(missing_cell_indices[i])])

    # Set coefficient i = neg_root + output[i-1] (before inner loop modifies output[i-1])
    output[i] = neg_root
    output[i] += output[i-1]

    # Update coefficients in reverse to avoid overwriting
    for j in countdown(i - 1, 1):
      output[j] *= neg_root
      output[j] += output[j-1]
    output[0] *= neg_root

  # Leading coefficient is 1
  output[missing_cell_count].setOne()

# ============================================================
#
#           Polynomial Recovery
#
# ============================================================

func recoverPolynomialCoeff*[N, N2, L, CDS: static int](
       recoveredPoly: var PolynomialCoef[N2, Fr[BLS12_381]],
       cell_indices: openArray[uint64],
       cosets_evals: openArray[array[L, Fr[BLS12_381]]],
       fft_desc: FrFFT_Descriptor[Fr[BLS12_381]]) =
  ## Recover polynomial coefficient form from partial cell evaluations.
  ##
  ## Algorithm (FFT-based recovery):
  ## 1. Build extended_evaluation array with zeros for missing cells
  ## 2. Compute vanishing polynomial Z(x) for missing cells
  ## 3. Compute (E * Z)(x) in evaluation form
  ## 4. Convert to coefficient form via IFFT [Domain: 2*N roots of unity]
  ## 5. Evaluate both (E*Z) and Z on coset domain [Shift: SCALE_FACTOR = 5]
  ## 6. Pointwise divide: P_eval = (E*Z)_coset / Z_coset
  ## 7. Convert P to coefficient form via coset IFFT [Shift: SCALE_FACTOR = 5]
  ##
  ## @param cell_indices: Indices of available cells (sorted, no duplicates)
  ## @param cosets_evals: Cell evaluations (L field elements each)
  ## @param fft_desc: FFT descriptor for extended domain (contains roots of unity)

  static:
    doAssert CDS * L == 2 * N, "CDS * L must equal 2 * N"
    doAssert N2 == 2*N

  let num_cells = cell_indices.len
  const ext_size = 2 * N

  # Step 1: Build extended evaluation array in bit-reversed order
  let extended_evaluation_brp = alloc0HeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(extended_evaluation_brp)

  for k in 0 ..< num_cells:
    let cell_idx = int(cell_indices[k])
    let start = cell_idx * L
    for j in 0 ..< L:
      extended_evaluation_brp[start + j] = cosets_evals[k][j]

  # Compute missing cell indices (bit-reversed)
  let missing_cells = computeMissingCells[CDS](cell_indices)
  let missing_cell_count = card(missing_cells)

  let missing_cell_indices = allocHeapArrayAligned(uint64, missing_cell_count, alignment = 64)
  defer: missing_cell_indices.freeHeapAligned()

  fillMissingCellIndices[CDS](missing_cell_indices.toOpenArray(missing_cell_count), missing_cells)

  # Build vanishing polynomial directly into zero_poly_coeff using strided view
  let zero_poly_coeff = alloc0HeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(zero_poly_coeff)

  var vanishing_poly_view = zero_poly_coeff.toStridedView(missing_cell_count + 1).slice(0, missing_cell_count * L, L)
  buildVanishingPolynomial[L, CDS](vanishing_poly_view, missing_cell_indices.toOpenArray(missing_cell_count), fft_desc, ext_size, CDS)

  # Step 2: Convert Z(x) to evaluation form [Domain: 2*N roots of unity, natural to natural]
  let zero_poly_eval_fft = allocHeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(zero_poly_eval_fft)

  check fft_desc.fft_nr(zero_poly_eval_fft.toOpenArray(ext_size), zero_poly_coeff.toOpenArray(ext_size))

  # Step 3: Compute (E*Z)(x) in evaluation form
  let extended_times_zero = allocHeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(extended_times_zero)

  for i in 0 ..< ext_size:
    extended_times_zero[i].prod(extended_evaluation_brp[i], zero_poly_eval_fft[i])

  # Step 4: Convert (E*Z) to coefficient form via IFFT [Domain: 2*N roots of unity, natural to natural]
  let ext_times_zero_coeffs = allocHeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(ext_times_zero_coeffs)

  check fft_desc.ifft_rn(ext_times_zero_coeffs.toOpenArray(ext_size), extended_times_zero.toOpenArray(ext_size))

  # Step 5: Evaluate on coset domain
  # Coset shift = 5 (same as c-kzg-4844)
  let cosetShift {.noInit.} = Fr[BLS12_381].fromUint(5'u32)

  let ext_eval_over_coset = allocHeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(ext_eval_over_coset)

  check fft_desc.coset_fft_nr(ext_eval_over_coset.toOpenArray(ext_size), ext_times_zero_coeffs.toOpenArray(ext_size), cosetShift)

  let zero_poly_over_coset = allocHeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(zero_poly_over_coset)

  check fft_desc.coset_fft_nr(zero_poly_over_coset.toOpenArray(ext_size), zero_poly_coeff.toOpenArray(ext_size), cosetShift)

  # Step 6: Pointwise divide P_eval = (E*Z)_coset / Z_coset
  let reconstructed_over_coset = allocHeapArrayAligned(Fr[BLS12_381], ext_size, alignment = 64)
  defer: freeHeapAligned(reconstructed_over_coset)

  reconstructed_over_coset.batchInv_vartime(zero_poly_over_coset, ext_size)
  for i in 0 ..< ext_size:
    reconstructed_over_coset[i] *= ext_eval_over_coset[i]

  # Step 7: Convert P to coefficient form via coset IFFT
  check fft_desc.coset_ifft_rn(recoveredPoly.coefs, reconstructed_over_coset.toOpenArray(ext_size), cosetShift)
