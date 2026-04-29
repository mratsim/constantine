# This file shows that
# the roots of unity for the 4096 domain
# are the first half of the roots of the 8192 domain
# if stored bit-reverse
#
# All operations are in the BLS12-381 scalar field Fr (not base field Fp)

# BLS12-381 scalar field (Fr) modulus
MODULUS = int("0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001", 16)

# Primitive 2^32-root-of-unity in Fr (research uses 7; production uses 5)
PRIMITIVE_ROOT_OF_UNITY = 7


def is_power_of_two(value: int) -> bool:
    """
    Check if ``value`` is a power of two integer.
    """
    return (value > 0) and (value & (value - 1) == 0)


def reverse_bits(n: int, order: int) -> int:
    """
    Reverse the bit order of an integer ``n``.
    """
    assert is_power_of_two(order)
    # Convert n to binary with the same number of bits as "order" - 1, then reverse its bit order
    return int(("{:0" + str(order.bit_length() - 1) + "b}").format(n)[::-1], 2)


def bit_reversal_permutation(sequence):
    """
    Return a copy with bit-reversed permutation. The permutation is an involution (inverts itself).

    The input and output are a sequence of generic type ``T`` objects.
    """
    return [sequence[reverse_bits(i, len(sequence))] for i in range(len(sequence))]


# Store results for 4096 and 8192 to verify the subset property
brp_roots_4096 = None
brp_roots_8192 = None

for N in [4, 8, 4096, 8192]:
    MULT_GENERATOR = pow(PRIMITIVE_ROOT_OF_UNITY, (MODULUS - 1) // N, MODULUS)
    # Validate that MULT_GENERATOR is a primitive N-th root of unity
    if MULT_GENERATOR == 1:
        raise ValueError(f"PRIMITIVE_ROOT_OF_UNITY^{(MODULUS - 1) // N} ≡ 1 mod MODULUS for N={N}; not a primitive root")
    if pow(MULT_GENERATOR, N, MODULUS) != 1:
        raise ValueError(f"PRIMITIVE_ROOT_OF_UNITY does not yield order-{N} subgroup: MULT_GENERATOR^{N} ≢ 1 mod MODULUS")
    if N > 1 and pow(MULT_GENERATOR, N // 2, MODULUS) == 1:
        raise ValueError(f"PRIMITIVE_ROOT_OF_UNITY yields degenerate subgroup for N={N}: MULT_GENERATOR^{N//2} ≡ 1 mod MODULUS")
    ROOTS_OF_UNITY = [pow(MULT_GENERATOR, i, MODULUS) for i in range(N)]
    # Verify all roots are distinct
    if len(set(ROOTS_OF_UNITY)) != N:
        raise ValueError(f"Generated roots of unity for N={N} are not distinct; PRIMITIVE_ROOT_OF_UNITY is invalid")
    print(f"N = {N}")
    top = min(N, 10)
    print(f"  >>> {top} first roots of unity")
    for i in range(top):
        print(f"      - {hex(ROOTS_OF_UNITY[i])}")

    BRP_ROOTS_OF_UNITY = bit_reversal_permutation(ROOTS_OF_UNITY)

    print(f"  >>> {top} first bit-reversed roots of unity")
    for i in range(top):
        print(f"      - {hex(BRP_ROOTS_OF_UNITY[i])}")

    # Store for later comparison
    if N == 4096:
        brp_roots_4096 = BRP_ROOTS_OF_UNITY
    elif N == 8192:
        brp_roots_8192 = BRP_ROOTS_OF_UNITY

# Assert the 4096⊂8192 bit-reversed-domain property
assert brp_roots_4096 is not None and brp_roots_8192 is not None, "Failed to generate both root sets"
assert brp_roots_4096 == brp_roots_8192[:4096], "4096 bit-reversed roots must equal first half of 8192 bit-reversed roots"
print("\n✓ Verified: 4096 bit-reversed roots == first 4096 of 8192 bit-reversed roots")
