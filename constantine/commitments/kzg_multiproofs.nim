# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Test with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/commitments/t_kzg_multiproofs.nim

import
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, arithmetic, extension_fields],
  constantine/math/elliptic/ec_multi_scalar_mul,
  constantine/math/polynomials/[polynomials, fft],
  constantine/math/matrix/toeplitz,
  constantine/platforms/[abstractions, allocs, bithacks, views]

# ############################################################
#
#           FK20 - Fast amortized KZG proofs
#
# ############################################################
#
# Algorithm from FK20 paper (Feist, Khovratovich):
#  https://raw.githubusercontent.com/khovratovich/Kate/master/Kate_amortized.pdf
#
# Long eprint:
# https://eprint.iacr.org/2023/033
#
# Computes multiple KZG proofs simultaneously in O(n log n) time
# instead of O(n²) for individual proofs.
#
# Nomenclature
# ~~~~~~~~~~~~
#
# - N: Polynomial size
# - L: coset size
# - CDS (Circulant Domain Size): Extended domain size = 2 * N/L
#
# For EIP-7594 PeerDAS:
#   N = 4096 (FIELD_ELEMENTS_PER_BLOB),
#   L = 64 (FIELD_ELEMENTS_PER_CELL)
#   N/L = CELLS_PER_BLOB, 64 blobs with each 64 cells
#   CDS = 128

func getTauExtFft[N, CDS: static int, Name: static Algebra](
       tauExtFft: var array[CDS, EC_ShortW_Jac[Fp[Name], G1]],
       powers_of_tau: PolynomialCoef[N, EC_ShortW_Aff[Fp[Name], G1]],
       ecfft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]],
       domainRoot: Fr[Name],
       offset: int = 0) {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Convert powers_of_tau (SRS coefficients) to tauExtFft (FFT of kernel sequence).
  ##
  ## For EIP-7594 PeerDAS:
  ##   N = FIELD_ELEMENTS_PER_BLOB = 4096
  ##   L = FIELD_ELEMENTS_PER_CELL = 64
  ##   CDS = 2 * CELLS_PER_BLOB = 128
  ##
  ## Uses stride to handle smaller sizes from a larger descriptor (e.g., 8192 descriptor for 128-size FFT).
  ##
  ## @param tauExtFft: Output array for FFT of kernel sequence (length CDS)
  ## @param powers_of_tau: SRS in coefficient form [G, τG, τ²G, ...] (affine, length N)
  ## @param ecfft_desc: Precomputed EC FFT descriptor (order >= CDS, uses stride)
  ## @param domainRoot: Primitive CDS-th root of unity for FFT
  ## @param offset: Offset for kernel extraction (default 0, range 0..L-1)

  const CDSdiv2 = CDS shr 1
  const L = N div CDSdiv2

  static:
    doAssert CDS.isPowerOf2_vartime(), "CDS must be a power of two"
  doAssert ecfft_desc.order >= CDS, "EC FFT descriptor order must be >= CDS"

  let kernelSeq = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], CDS, alignment = 64)

  # Extract kernel with stride L and given offset (convert affine to projective for FFT)
  let start = if N >= L + 1 + offset: N - L - 1 - offset else: 0
  var j = start
  for i in 0 ..< CDSdiv2 - 1:
    kernelSeq[i].fromAffine(powers_of_tau.coefs[j])
    j -= L
  kernelSeq[CDSdiv2 - 1].setNeutral()
  for j in CDSdiv2 ..< CDS:
    kernelSeq[j].setNeutral()

  # FFT the kernel to get tauExtFft
  let status = ec_fft_nr(ecFftDesc, tauExtFft, kernelSeq.toOpenArray(CDS))
  if status != FFT_Success:
    freeHeapAligned(kernelSeq)
    return

  freeHeapAligned(kernelSeq)

func getTauExtFftArray*[N, L, CDS: static int, Name: static Algebra](
       tauExtFftArray: var array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]],
       powers_of_tau: PolynomialCoef[N, EC_ShortW_Aff[Fp[Name], G1]],
       ecfft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]],
       domainRoot: Fr[Name]) {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Compute tauExtFft for all L offsets.
  ##
  ## This is the complete FK20 preprocessing phase. It computes the FFT of
  ## the kernel sequence for each offset in 0..L-1.
  ##
  ## For EIP-7594 PeerDAS:
  ##   N = FIELD_ELEMENTS_PER_BLOB = 4096
  ##   L = FIELD_ELEMENTS_PER_CELL = 64
  ##   CDS = 2 * CELLS_PER_BLOB = 128
  ##
  ## This corresponds to:
  ##   - fk20_multi.py lines 46-49: xext_fft = [] for i in range(l)
  ##   - c-kzg-4844: s->x_ext_fft_columns (precomputed during setup)
  ##
  ## The result can be cached and reused for multiple polynomials.
  ##
  ## @param tauExtFftArray: Output array[L][CDS] for FFT of kernel sequences
  ## @param powers_of_tau: SRS in coefficient form [G, τG, τ²G, ..., τⁿ⁻¹G] (affine, length N)
  ## @param ecfft_desc: Precomputed EC FFT descriptor (order >= CDS, uses stride)
  ## @param domainRoot: Primitive CDS-th root of unity for FFT
  ##
  ## @see getTauExtFft for computing a single offset
  static: doAssert CDS * L == 2 * N
  doAssert ecfft_desc.order >= CDS, "EC FFT descriptor order must be >= CDS"

  for offset in 0 ..< L:
    getTauExtFft(tauExtFftArray[offset], powers_of_tau, ecfft_desc, domainRoot, offset)

func kzg_coset_prove*[N, L, CDS: static int, Name: static Algebra](
       tauExtFftArray: array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]],
       proofs: var array[CDS, EC_ShortW_Aff[Fp[Name], G1]],
       poly: PolynomialCoef[N, Fr[Name]],
       fr_fft_desc: FrFFT_Descriptor[Fr[Name]] | CosetFFT_Descriptor[Fr[Name]], # AnyFFT_Descriptor doesn't work when called through peerdas
       ec_fft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]]) {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Compute KZG multi-proofs for EIP-7594 cell proofs using FK20 algorithm.
  ##
  ## This implements the FK20 amortized KZG proofs from c-kzg-4844.
  ## Uses Toeplitz matrix-vector multiplication with FFT for O(n log n) performance.
  ##
  ## For EIP-7594 PeerDAS:
  ##   N = FIELD_ELEMENTS_PER_BLOB = 4096 (polynomial size)
  ##   L = FIELD_ELEMENTS_PER_CELL = 64 (stride/loop count, evaluations per cell)
  ##   CDS = 2 * CELLS_PER_BLOB = 128 (output proof count)
  ##
  ## Uses stride to handle smaller sizes from larger descriptors (e.g., 8192 descriptor for 128-size FFT).
  ##
  ## Algorithm (Phase 1 + Phase 2 from FK20):
  ##   For each stride offset in [0, L):
  ##     1. Extract toeplitz coefficients from poly
  ##     2. toeplitzMatVecMul: FFT coeffs + FFT kernel + pointwise multiply + IFFT
  ##     3. Accumulate result
  ##   Zero upper half
  ##   FFT → proofs
  ##
  ## Verification:
  ##   - If L == 1 (single evaluation per coset): Use regular `kzg_verify`
  ##   - If L > 1 (multiple evaluations per coset): Use `kzg_coset_verify`
  ##
  ## @param tauExtFft: Precomputed FFT of kernel sequence (length CDS)
  ## @param proofs: Output array for CDS proofs (affine form)
  ## @param poly: Polynomial to prove (length N, coefficient/monomial form)
  ## @param fr_fft_desc: Precomputed Fr FFT descriptor (order >= CDS, uses stride)
  ## @param ec_fft_desc: Precomputed EC FFT descriptor (order >= CDS, uses stride)

  const CDSdiv2 = CDS shr 1
  const N = L * CDSdiv2

  static:
    doAssert CDS.isPowerOf2_vartime(), "CDS must be a power of two"
  doAssert fr_fft_desc.order >= CDS, "Fr FFT descriptor order must be >= CDS"
  doAssert ec_fft_desc.order >= CDS, "EC FFT descriptor order must be >= CDS"

  let u = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], CDS, alignment = 64)
  for i in 0 ..< CDS:
    u[i].setNeutral()

  let circulant = allocHeapArrayAligned(Fr[Name], CDS, alignment = 64)

  for offset in 0 ..< L:
    makeCirculantMatrix(circulant.toOpenArray(CDS), poly.coefs, offset, L)

    # Use toeplitzMatVecMulPreFFT with accumulate=true
    # This does: FFT(toeplitzCoeffs) ⊙ kernelFft, then IFFT → result
    # Results are accumulated in time domain
    let status = toeplitzMatVecMulPreFFT(
      u.toOpenArray(CDS),
      circulant.toOpenArray(CDS),
      tauExtFftArray[offset],
      fr_fft_desc,
      ec_fft_desc,
      accumulate = (offset > 0)
    )
    if status != FFT_Success:
      freeHeapAligned(circulant)
      freeHeapAligned(u)
      return

  # u is already in time domain (toeplitzMatVecMulPreFFT did IFFT)
  # Zero upper half, degree is CDS/2 - 1
  for i in CDSdiv2 ..< CDS:
    u[i].setNeutral()

  # FFT to get proofs
  let proofsJac = allocHeapArrayAligned(EC_ShortW_Jac[Fp[Name], G1], CDS, alignment = 64)
  let status3 = ec_fft_desc.ec_fft_nr(proofsJac.toOpenArray(CDS), u.toOpenArray(CDS))
  if status3 != FFT_Success:
    freeHeapAligned(proofsJac)
    freeHeapAligned(circulant)
    freeHeapAligned(u)
    return

  proofs.asUnchecked().batchAffine(proofsJac, proofs.len)

  freeHeapAligned(proofsJac)
  freeHeapAligned(circulant)
  freeHeapAligned(u)
