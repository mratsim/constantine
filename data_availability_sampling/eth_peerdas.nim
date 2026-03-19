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
  constantine/math/polynomials/[polynomials, fft],
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
#           Coset Primitives
#
# ============================================================

func cosetShiftForIndex*[L, CDS: static int, Name: static Algebra](
       cell_index: uint64,
       fft_desc: CosetFFT_Descriptor[Fr[Name]]): Fr[Name] =
  ## Get the coset shift for a given cell index.
  ## Returns h_k = roots_of_unity_brp[L * cell_index]
  ## Domain: Extended domain of size CDS * L / 2
  let idx = int(cell_index) * L
  result = fft_desc.rootsOfUnity[idx]

func cosetForIndex*[L, CDS: static int, Name: static Algebra](
       cell_index: uint64,
       fft_desc: CosetFFT_Descriptor[Fr[Name]]): array[L, Fr[Name]] =
  ## Get the coset domain for a given cell index.
  ## Returns h_k * roots_of_unity[i] for i in 0..L-1
  ## Domain: Extended domain of size CDS * L / 2
  let start = int(cell_index) * L
  for i in 0 ..< L:
    result[i] = fft_desc.rootsOfUnity[start + i]

# ============================================================
#
#           Polynomial Recovery
#
# ============================================================

func recoverPolynomialCoeff*[N, L, CDS: static int, Name: static Algebra](
       cell_indices: seq[uint64],
       cosets_evals: seq[array[L, Fr[Name]]],
       fft_desc: CosetFFT_Descriptor[Fr[Name]]): PolynomialCoef[2 * N, Fr[Name]] =
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

  let num_cells = cell_indices.len
  let ext_size = 2 * N

  # Step 1: Build extended evaluation array in bit-reversed order
  var extended_evaluation_rbo: array[2 * N, Fr[Name]]
  for i in 0 ..< ext_size:
    extended_evaluation_rbo[i].setZero()

  for k in 0 ..< num_cells:
    let cell_idx = int(cell_indices[k])
    let start = cell_idx * L
    for j in 0 ..< L:
      extended_evaluation_rbo[start + j] = cosets_evals[k][j]

  # Step 2: Bit-reverse into extended_evaluation
  var extended_evaluation = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  bit_reversal_permutation(extended_evaluation.toOpenArray(0, ext_size-1), extended_evaluation_rbo.toOpenArray(0, ext_size-1))

  # Compute missing cell indices and vanishing polynomial
  var missing_cell_indices: seq[uint64]
  let num_cells_total = CDS
  for i in 0 ..< num_cells_total:
    var found = false
    for j in 0 ..< num_cells:
      if int(cell_indices[j]) == i:
        found = true
        break
    if not found:
      # The vanish polynomial requires missing cells in bit-reversed indices
      let brp_i = reverseBits(uint64(i), uint64(log2_vartime(uint32 num_cells_total)))
      missing_cell_indices.add(brp_i)

  # Compute vanishing polynomial on small domain (CELLS_PER_EXT_BLOB points)
  var short_roots = allocHeapArrayAligned(Fr[Name], missing_cell_indices.len, alignment = 64)
  let stride = ext_size div num_cells_total

  for i in 0 ..< missing_cell_indices.len:
    let root_idx = missing_cell_indices[i] * uint64(stride)
    short_roots[i] = fft_desc.rootsOfUnity[root_idx]

  var short_vanishing_poly = allocHeapArrayAligned(Fr[Name], missing_cell_indices.len + 1, alignment = 64)
  if missing_cell_indices.len > 0:
    short_vanishing_poly[0].neg(short_roots[0])
    for i in 1 ..< missing_cell_indices.len:
      var neg_root {.noInit.}: Fr[Name]
      neg_root.neg(short_roots[i])
      short_vanishing_poly[i] = neg_root
      short_vanishing_poly[i] += short_vanishing_poly[i-1]
      for j in countdown(i - 1, 1):
        short_vanishing_poly[j] *= neg_root
        short_vanishing_poly[j] += short_vanishing_poly[j-1]
      short_vanishing_poly[0] *= neg_root
  short_vanishing_poly[missing_cell_indices.len].setOne()

  # Extend vanishing polynomial to full domain
  var zero_poly_coeff = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  for i in 0 ..< ext_size:
    zero_poly_coeff[i].setZero()
  for i in 0 .. missing_cell_indices.len:
    zero_poly_coeff[i * L] = short_vanishing_poly[i]

  freeHeapAligned(short_roots)
  freeHeapAligned(short_vanishing_poly)

  # Step 3: Convert Z(x) to evaluation form [Domain: 2*N roots of unity, natural to bit-reversed]
  var zero_poly_eval = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  for i in 0 ..< ext_size:
    zero_poly_eval[i] = zero_poly_coeff[i]

  var zero_poly_eval_fft = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  let fft_status = fft_nr(fft_desc, zero_poly_eval_fft.toOpenArray(ext_size), zero_poly_eval.toOpenArray(ext_size))
  doAssert fft_status == FFT_Success
  freeHeapAligned(zero_poly_eval)

  # Step 4: Compute (E*Z)(x) in evaluation form
  var extended_times_zero = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  for i in 0 ..< ext_size:
    extended_times_zero[i].prod(extended_evaluation[i], zero_poly_eval_fft[i])

  freeHeapAligned(extended_evaluation)
  freeHeapAligned(zero_poly_eval_fft)

  # Step 5: Convert (E*Z) to coefficient form via IFFT [Domain: 2*N roots of unity, bit-reversed to natural]
  var ext_times_zero_coeffs = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  let ifft_status = ifft_rn(fft_desc, ext_times_zero_coeffs.toOpenArray(ext_size), extended_times_zero.toOpenArray(ext_size))
  doAssert ifft_status == FFT_Success

  # Step 6: Evaluate on coset domain using coset FFT descriptor
  var ext_eval_over_coset = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  let coset_fft_status = coset_fft_nr(fft_desc, ext_eval_over_coset.toOpenArray(ext_size), ext_times_zero_coeffs.toOpenArray(ext_size))
  doAssert coset_fft_status == FFT_Success

  var zero_poly_over_coset = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  let coset_fft_status2 = coset_fft_nr(fft_desc, zero_poly_over_coset.toOpenArray(ext_size), zero_poly_coeff.toOpenArray(ext_size))
  doAssert coset_fft_status2 == FFT_Success

  # Step 7: Pointwise divide P_eval = (E*Z)_coset / Z_coset
  var reconstructed_over_coset = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  for i in 0 ..< ext_size:
    var inv {.noInit.}: Fr[Name]
    inv.inv_vartime(zero_poly_over_coset[i])
    reconstructed_over_coset[i].prod(ext_eval_over_coset[i], inv)

  # Step 8: Convert P to coefficient form via coset IFFT [Shift: from descriptor]
  var reconstructed_coeff = allocHeapArrayAligned(Fr[Name], ext_size, alignment = 64)
  let coset_ifft_status = coset_ifft_rn(fft_desc, reconstructed_coeff.toOpenArray(ext_size), reconstructed_over_coset.toOpenArray(ext_size))
  doAssert coset_ifft_status == FFT_Success

  # Return coefficients
  for i in 0 ..< ext_size:
    result.coefs[i] = reconstructed_coeff[i]

  freeHeapAligned(reconstructed_coeff)
  freeHeapAligned(reconstructed_over_coset)
  freeHeapAligned(zero_poly_over_coset)
  freeHeapAligned(ext_eval_over_coset)
  freeHeapAligned(ext_times_zero_coeffs)
  freeHeapAligned(zero_poly_coeff)
