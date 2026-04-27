#!/usr/bin/env python3
"""
Test script to verify that skipping FFTs in compute_cells is equivalent to the spec.

This tests the optimization where we:
1. Start with blob in evaluation form (4096 points, bit-reversed)
2. Bit-reverse to natural order
3. IFFT to get monomial coefficients (4096)
4. Zero-pad to extended size (8192)
5. FFT to get extended evaluations (bit-reversed order)
6. Slice into cells

The spec does:
1. Blob → polynomial (evaluation form)
2. polynomial_eval_to_coeff (IFFT 4096)
3. For each cell, evaluate polynomial at coset points (O(n²) naive)

We verify that FFT-based approach matches the spec.

References:
- c-kzg-4844: src/eip7594/eip7594.c (lines 98-119)
- rust-kzg: kzg/src/das.rs (lines 241-253)
- ethereum-research: polynomial_reconstruction/fft.py

⚠️ For EIP-4844 and EIP-7594 the roots of unity are in bit-reversed order
"""

from typing import List, Tuple
import sys

# BLS12-381 scalar field modulus (Fr)
BLS_MODULUS = int(
    "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001",
    16,
)
# Generator for 2^32-th root of unity in Fr
PRIMITIVE_ROOT_OF_UNITY = 7

# PeerDAS constants
FIELD_ELEMENTS_PER_BLOB = 4096
FIELD_ELEMENTS_PER_EXT_BLOB = 2 * FIELD_ELEMENTS_PER_BLOB
FIELD_ELEMENTS_PER_CELL = 64
CELLS_PER_EXT_BLOB = FIELD_ELEMENTS_PER_EXT_BLOB // FIELD_ELEMENTS_PER_CELL


def is_power_of_two(value: int) -> bool:
    """Check if value is a power of two."""
    return (value > 0) and (value & (value - 1) == 0)


def reverse_bits(n: int, order: int) -> int:
    """Reverse the bit order of an integer n."""
    assert is_power_of_two(order)
    num_bits = order.bit_length() - 1
    return int(("{:0" + str(num_bits) + "b}").format(n)[::-1], 2)


def bit_reversal_permutation(sequence: List[int]) -> List[int]:
    """Return a copy with bit-reversed permutation. The permutation is an involution."""
    return [sequence[reverse_bits(i, len(sequence))] for i in range(len(sequence))]


def compute_roots_of_unity(n: int) -> List[int]:
    """Compute n roots of unity."""
    assert is_power_of_two(n)
    mult_generator = pow(PRIMITIVE_ROOT_OF_UNITY, (BLS_MODULUS - 1) // n, BLS_MODULUS)
    return [pow(mult_generator, i, BLS_MODULUS) for i in range(n)]


def _simple_ft(vals: List[int], roots_of_unity: List[int]) -> List[int]:
    """Simple O(n²) FFT for small sizes."""
    L = len(roots_of_unity)
    o = []
    for i in range(L):
        last = 0
        for j in range(L):
            last += vals[j] * roots_of_unity[(i * j) % L]
        o.append(last % BLS_MODULUS)
    return o


def _fft(vals: List[int], roots_of_unity: List[int]) -> List[int]:
    """Recursive FFT implementation."""
    if len(vals) <= 4:
        return _simple_ft(vals, roots_of_unity)
    L = _fft(vals[::2], roots_of_unity[::2])
    R = _fft(vals[1::2], roots_of_unity[::2])
    o = [0 for _ in vals]
    for i, (x, y) in enumerate(zip(L, R)):
        y_times_root = y * roots_of_unity[i] % BLS_MODULUS
        o[i] = (x + y_times_root) % BLS_MODULUS
        o[i + len(L)] = (x - y_times_root) % BLS_MODULUS
    return o


def fft(vals: List[int], roots_of_unity: List[int], inv: bool = False) -> List[int]:
    """FFT/IFFT."""
    if inv:
        # Inverse FFT
        invlen = pow(len(vals), BLS_MODULUS - 2, BLS_MODULUS)
        # Reverse roots for inverse
        reversed_roots = [roots_of_unity[0]] + roots_of_unity[:0:-1]
        result = _fft(vals, reversed_roots)
        return [(x * invlen) % BLS_MODULUS for x in result]
    else:
        # Regular FFT
        return _fft(vals, roots_of_unity)


def evaluate_polynomial_coeff(poly_coeff: List[int], z: int) -> int:
    """Evaluate a polynomial in coefficient form at z using Horner's method."""
    y = 0
    for coef in reversed(poly_coeff):
        y = (y * z + coef) % BLS_MODULUS
    return y


def polynomial_eval_to_coeff(
    polynomial: List[int], roots_of_unity: List[int]
) -> List[int]:
    """
    Convert polynomial from evaluation form to coefficient form.

    Args:
        polynomial: Polynomial in evaluation form (bit-reversed order)
        roots_of_unity: Precomputed roots of unity for the polynomial degree.
                       Must have length equal to len(polynomial).
                       In production, these are precomputed once and reused.

    Returns:
        Polynomial in coefficient (monomial) form
    """
    # Bit-reverse then IFFT
    brp = bit_reversal_permutation(polynomial)
    return fft(brp, roots_of_unity, inv=True)


def coset_for_cell(cell_index: int, roots_of_unity_8192: List[int]) -> List[int]:
    """
    Get the coset for a given cell index.

    Args:
        cell_index: Index of the cell (0-127)
        roots_of_unity_8192: Precomputed 8192nd roots of unity

    Returns:
        List of 64 field elements (the coset for this cell)
    """
    roots_of_unity_brp = bit_reversal_permutation(roots_of_unity_8192)
    start = FIELD_ELEMENTS_PER_CELL * cell_index
    end = start + FIELD_ELEMENTS_PER_CELL
    return roots_of_unity_brp[start:end]


def compute_cells_spec(
    blob: List[int], roots_of_unity_4096: List[int], roots_of_unity_8192: List[int]
) -> List[List[int]]:
    """
    Compute cells following the spec exactly (slow O(n²) method).

    This is the reference implementation from:
    https://github.com/ethereum/consensus-specs/blob/v1.6.1/specs/fulu/polynomial-commitments-sampling.md#compute_cells

    Args:
        blob: Blob in bit-reversed evaluation form (4096 field elements)
        roots_of_unity_4096: Precomputed 4096th roots of unity (for IFFT)
        roots_of_unity_8192: Precomputed 8192nd roots of unity (for coset_for_cell)

    Returns:
        List of cells, each containing FIELD_ELEMENTS_PER_CELL field elements
    """
    # blob is already in evaluation form, no conversion needed
    polynomial_coeff = polynomial_eval_to_coeff(blob, roots_of_unity_4096)

    cells = []
    for i in range(CELLS_PER_EXT_BLOB):
        coset = coset_for_cell(i, roots_of_unity_8192)
        # Evaluate polynomial at each point in the coset (O(n²) naive evaluation)
        ys = [evaluate_polynomial_coeff(polynomial_coeff, z) for z in coset]
        cells.append(ys)
    return cells


def compute_cells_fft(
    blob: List[int], roots_of_unity_4096: List[int], roots_of_unity_8192: List[int]
) -> List[List[int]]:
    """
    Compute cells using FFT optimization (fast O(n log n) method).

    This matches the implementation in:
    - c-kzg-4844: src/eip7594/eip7594.c (lines 98-119)
    - rust-kzg: kzg/src/das.rs (lines 241-253)
    - go-eth-kzg: api_eip7594.go (lines 12-58)

    Important: blob is in bit-reversed evaluation form.

    Flow (there are 2 bit-reversal that probably can be removed):
    1. Bit-reverse blob to natural order
    2. IFFT to get monomial coefficients
    3. Zero-pad to extended size
    4. FFT to get extended evaluations (bit-reversed)
    5. Bit-reverse the FFT output (to match spec's coset ordering)
    6. Slice into cells

    Args:
        blob: Blob in bit-reversed evaluation form (4096 field elements)
        roots_of_unity_4096: Precomputed 4096th roots of unity
        roots_of_unity_8192: Precomputed 8192nd roots of unity

    Returns:
        List of 128 cells, each containing 64 field elements
    """
    # Step 1: Blob is in bit-reversed evaluation form
    # Bit-reverse to get natural order evaluations
    poly_lagrange_natural = bit_reversal_permutation(blob)

    # Step 2: IFFT to get monomial coefficients (4096 coeffs)
    poly_monomial = fft(poly_lagrange_natural, roots_of_unity_4096, inv=True)

    # Step 3: Zero-pad to extended size (8192 coeffs)
    poly_monomial_ext = poly_monomial + [0] * FIELD_ELEMENTS_PER_BLOB

    # Step 4: FFT to get extended evaluations (8192 points, bit-reversed order)
    poly_eval_ext_brp = fft(poly_monomial_ext, roots_of_unity_8192, inv=False)

    # Step 5: Bit-reverse the FFT output to match spec's coset ordering
    # (c-kzg-4844 does this explicitly after FFT)
    poly_eval_ext = bit_reversal_permutation(poly_eval_ext_brp)

    # Step 6: Slice into cells (each cell is 64 consecutive field elements)
    cells = []
    for i in range(CELLS_PER_EXT_BLOB):
        start = i * FIELD_ELEMENTS_PER_CELL
        end = start + FIELD_ELEMENTS_PER_CELL
        cell = poly_eval_ext[start:end]
        cells.append(cell)

    return cells


def compute_cells_half_fft(
    blob: List[int], roots_of_unity_4096: List[int], w_8192: int
) -> List[List[int]]:
    """
    Compute cells using the half-FFT optimization.

    This is the MOST efficient known method for computing cells from a blob.

    Key insight: Due to the mathematical properties of bit-reversal permutation,
    the first half of the extended blob is IDENTICAL to the original blob.
    The second half only requires a single size-4096 FFT (not 8192).

    Mathematical background:
    ------------------------
    Consider the bit-reversal permutation of indices 0..8191 (for 8192 elements):
    - An index i in [0, 8191] has 13 bits (since 2^13 = 8192)
    - After bit-reversal, indices with LSB=0 map to the first half [0, 4095]
    - Indices with LSB=1 map to the second half [4096, 8191]

    The 8192 roots of unity are: w_8192^0, w_8192^1, ..., w_8192^8191
    After bit-reversal permutation:
    - First 4096 positions contain w_8192^(even powers) = w_4096^k for k=0..4095
    - Second 4096 positions contain w_8192^(odd powers) = w_8192 * w_4096^k

    Since the blob is a degree-4095 polynomial given in evaluation form at w_4096^k,
    the first half of the extended blob is EXACTLY the original blob evaluations!

    For the second half, we evaluate at w_8192 * w_4096^k, which is a coset shift.
    This can be computed by:
    1. Converting to coefficient form (IFFT)
    2. Multiplying coefficient k by w_8192^k (the shift)
    3. Evaluating at w_4096^k (FFT)

    Complexity comparison:
    --------------------
    - Spec (naive): 1 IFFT(4096) + 128 * 64 * 4096 ops = O(n²) ~ 33M ops
    - Full FFT: 1 IFFT(4096) + 1 FFT(8192) = O(n log n) ~ 180K ops
    - Half FFT (this): 1 IFFT(4096) + 1 FFT(4096) + O(n) copy = ~90K ops + free first half

    References:
    -----------
    - Similar optimization mentioned in ethereum/research repo
    - Used in production implementations for efficiency

    Args:
        blob: Blob in bit-reversed evaluation form (4096 field elements)
        roots_of_unity_4096: Precomputed 4096th roots of unity (for IFFT and FFT)
        w_8192: The primitive 8192nd root of unity (coset shift factor)
               This is roots_of_unity_8192[1], computed once at setup

    Returns:
        List of 128 cells, each containing 64 field elements
    """
    # =========================================================================
    # CONSTANTS AND SETUP
    # =========================================================================
    HALF_CELLS = CELLS_PER_EXT_BLOB // 2  # = 64

    # =========================================================================
    # PART 1: FIRST HALF - ZERO COMPUTATION!
    # =========================================================================
    # The first 64 cells (indices 0-63) contain the first 4096 field elements
    # of the extended blob. Due to bit-reversal properties, these are EXACTLY
    # the same as the original blob's 4096 field elements.
    #
    # Why this works:
    # ---------------
    # Let BR_8192 be the bit-reversal permutation for 8192 elements (13 bits).
    # For any index i in [0, 4095], BR_8192(i) has LSB = 0 (since we're in first half).
    # This means BR_8192(i) = 2 * BR_4096(i), where BR_4096 is 12-bit reversal.
    #
    # The 8192nd roots of unity at even indices are:
    #   w_8192^(2k) = (w_8192^2)^k = w_4096^k
    #
    # So the first 4096 positions of the bit-reversed extended domain are
    # evaluations at exactly the same points as the original blob!
    #
    # Implementation:
    # ---------------
    # Simply slice the blob bytes directly into cells. No FFT, no IFFT,
    # no polynomial evaluation - just memory copy!
    # =========================================================================

    cells: List[List[int]] = []

    # Copy first 64 cells directly from blob
    # Each cell is 64 consecutive field elements from the blob
    for i in range(HALF_CELLS):
        start_elem = i * FIELD_ELEMENTS_PER_CELL
        end_elem = start_elem + FIELD_ELEMENTS_PER_CELL
        # Direct slice - no computation needed!
        cell = blob[start_elem:end_elem]
        cells.append(cell)

    # =========================================================================
    # PART 2: SECOND HALF - SINGLE SIZE-4096 FFT
    # =========================================================================
    # The second 64 cells (indices 64-127) contain evaluations at the odd
    # powers of w_8192 after bit-reversal. These are:
    #   w_8192^(2k+1) = w_8192 * w_4096^k  for k = 0, ..., 4095
    #
    # This is a coset: the standard 4096th roots scaled by w_8192.
    #
    # To evaluate polynomial P(x) at {w_8192 * w_4096^k}:
    #   P(w_8192 * w_4096^k) = sum_{j=0}^{4095} c_j * (w_8192 * w_4096^k)^j
    #                        = sum_{j=0}^{4095} (c_j * w_8192^j) * w_4096^(kj)
    #
    # Define shifted coefficients: c'_j = c_j * w_8192^j
    # Then: P(w_8192 * w_4096^k) = sum_{j=0}^{4095} c'_j * w_4096^(kj)
    #
    # This is exactly the FFT of the shifted coefficients!
    #
    # Steps:
    # 1. Convert blob (eval form) to coefficients via IFFT
    # 2. Shift coefficients: c'_j = c_j * w_8192^j
    # 3. FFT of shifted coeffs gives evaluations at w_8192 * w_4096^k
    # 4. Bit-reverse to match cell ordering
    # 5. Slice into cells
    # =========================================================================

    # -------------------------------------------------------------------------
    # Step 2a: Convert blob to coefficient form (size-4096 IFFT)
    # -------------------------------------------------------------------------
    # The blob is in bit-reversed evaluation form.
    poly_monomial = polynomial_eval_to_coeff(blob, roots_of_unity_4096)
    # Now poly_monomial[k] = coefficient of x^k in the polynomial

    # -------------------------------------------------------------------------
    # Step 2b: Shift coefficients by powers of w_8192
    # -------------------------------------------------------------------------
    # We need to evaluate at w_8192 * w_4096^k, which requires multiplying
    # coefficient j by w_8192^j before the FFT.
    #
    # w_8192 is passed as parameter (the coset shift factor)
    # -------------------------------------------------------------------------
    # w_8192 already available as parameter

    # Compute shifted coefficients: c'_j = c_j * w_8192^j
    shifted_coeffs: List[int] = []
    shift_power = 1  # Starts at w_8192^0 = 1
    for coeff in poly_monomial:
        shifted_coeffs.append((coeff * shift_power) % BLS_MODULUS)
        shift_power = (shift_power * w_8192) % BLS_MODULUS
    # After loop: shifted_coeffs[j] = poly_monomial[j] * w_8192^j

    # -------------------------------------------------------------------------
    # Step 2c: FFT of shifted coefficients (size-4096 FFT)
    # -------------------------------------------------------------------------
    # This gives us evaluations at w_8192 * w_4096^k for k = 0, ..., 4095
    # in NATURAL order (k = 0, 1, 2, ..., 4095)
    # -------------------------------------------------------------------------
    odd_evals_natural = fft(shifted_coeffs, roots_of_unity_4096, inv=False)
    # odd_evals_natural[k] = P(w_8192 * w_4096^k)

    # -------------------------------------------------------------------------
    # Step 2d: Bit-reverse to match cell ordering
    # -------------------------------------------------------------------------
    # The cells expect evaluations in bit-reversed order (same as input blob).
    # After bit-reversal, odd_evals_brp[i] = odd_evals_natural[BR_4096(i)]
    # This matches the ordering of coset_for_cell for cells 64-127.
    # -------------------------------------------------------------------------
    odd_evals_brp = bit_reversal_permutation(odd_evals_natural)

    # -------------------------------------------------------------------------
    # Step 2e: Slice into cells 64-127
    # -------------------------------------------------------------------------
    # Each cell contains 64 consecutive field elements from the bit-reversed
    # odd evaluations.
    # -------------------------------------------------------------------------
    for i in range(HALF_CELLS):
        start_elem = i * FIELD_ELEMENTS_PER_CELL
        end_elem = start_elem + FIELD_ELEMENTS_PER_CELL
        cell = odd_evals_brp[start_elem:end_elem]
        cells.append(cell)

    return cells


def test_compute_cells():
    """
    Test that the half-FFT optimization produces correct results.

    This verifies that compute_cells_half_fft matches both:
    1. The spec (compute_cells_spec) - mathematical correctness
    2. The full FFT version (compute_cells_fft) - implementation consistency
    """
    print("=" * 80)
    print("Testing compute_cells_half_fft optimization")
    print("=" * 80)

    import random
    import time

    random.seed(42)

    # Local constant for test
    HALF_CELLS = CELLS_PER_EXT_BLOB // 2  # = 64

    print(f"\nGenerating random blob with {FIELD_ELEMENTS_PER_BLOB} field elements...")
    blob = [random.randint(0, BLS_MODULUS - 1) for _ in range(FIELD_ELEMENTS_PER_BLOB)]

    # Precompute roots of unity (as would be done in production)
    print("Precomputing roots of unity...")
    roots_of_unity_4096 = compute_roots_of_unity(FIELD_ELEMENTS_PER_BLOB)
    roots_of_unity_8192 = compute_roots_of_unity(FIELD_ELEMENTS_PER_EXT_BLOB)
    w_8192 = roots_of_unity_8192[1]  # Primitive 8192nd root of unity (coset shift)

    # -------------------------------------------------------------------------
    # Test 1: Compare with spec (ground truth)
    # -------------------------------------------------------------------------
    print("\n[Test 1] Comparing half-FFT with spec (O(n²) ground truth)...")

    start = time.time()
    cells_spec = compute_cells_spec(blob, roots_of_unity_4096, roots_of_unity_8192)
    time_spec = time.time() - start

    start = time.time()
    cells_half = compute_cells_half_fft(blob, roots_of_unity_4096, w_8192)
    time_half = time.time() - start

    print(f"  Spec method:      {time_spec:8.2f} seconds")
    print(f"  Half-FFT method:  {time_half:8.4f} seconds")
    print(f"  Speedup:          {time_spec / time_half:8.1f}x faster")

    all_match = True
    for i in range(CELLS_PER_EXT_BLOB):
        if cells_spec[i] != cells_half[i]:
            print(f"  ❌ Cell {i} does NOT match!")
            all_match = False
            for j in range(FIELD_ELEMENTS_PER_CELL):
                if cells_spec[i][j] != cells_half[i][j]:
                    print(f"    First mismatch at element {j}:")
                    print(f"      Spec:   {cells_spec[i][j]}")
                    print(f"      Half-FFT: {cells_half[i][j]}")
                    break
            break

    if all_match:
        print("  ✅ All 128 cells match the spec!")
    else:
        print("  ❌ MISMATCH with spec!")
        return False

    # -------------------------------------------------------------------------
    # Test 2: Compare with full FFT version
    # -------------------------------------------------------------------------
    print("\n[Test 2] Comparing half-FFT with full FFT version...")

    start = time.time()
    cells_full_fft = compute_cells_fft(blob, roots_of_unity_4096, roots_of_unity_8192)
    time_full = time.time() - start

    print(f"  Full FFT method:  {time_full:8.4f} seconds")
    print(f"  Half-FFT method:  {time_half:8.4f} seconds")
    print(f"  Speedup:          {time_full / time_half:8.2f}x faster")

    all_match = True
    for i in range(CELLS_PER_EXT_BLOB):
        if cells_full_fft[i] != cells_half[i]:
            print(f"  ❌ Cell {i} does NOT match!")
            all_match = False
            break

    if all_match:
        print("  ✅ All 128 cells match the full FFT version!")
    else:
        print("  ❌ MISMATCH with full FFT!")
        return False

    # -------------------------------------------------------------------------
    # Test 3: Verify first half is direct copy
    # -------------------------------------------------------------------------
    print("\n[Test 3] Verifying first half is direct copy (zero computation)...")

    first_half_correct = True
    for i in range(HALF_CELLS):
        start_elem = i * FIELD_ELEMENTS_PER_CELL
        end_elem = start_elem + FIELD_ELEMENTS_PER_CELL
        expected = blob[start_elem:end_elem]
        actual = cells_half[i]
        if expected != actual:
            print(f"  ❌ Cell {i} should be direct copy but isn't!")
            first_half_correct = False
            break

    if first_half_correct:
        print("  ✅ First 64 cells are direct copies from blob!")
        print("     (No FFT, IFFT, or polynomial evaluation performed)")
    else:
        print("  ❌ First half is NOT a direct copy!")
        return False

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    print("\n" + "=" * 80)
    print("✅ ALL TESTS PASSED!")
    print("=" * 80)
    print("\nOptimization summary:")
    print("  • First 64 cells:  Direct memory copy (O(n), no math)")
    print("  • Second 64 cells: Single IFFT(4096) + FFT(4096) + O(n) shift")

    return True


if __name__ == "__main__":
    success = test_compute_cells()
    sys.exit(0 if success else 1)
