# This file shows that
# the roots of unity for the 4096 domain
# are the first half of the roots of the 80192 domain
# if stored bit-reverse

MODULUS = int('0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab', 16)
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

for N in [4, 8, 4096, 8192]:
    MULT_GENERATOR = pow(PRIMITIVE_ROOT_OF_UNITY, (MODULUS - 1) // N, MODULUS)
    ROOTS_OF_UNITY = [pow(MULT_GENERATOR, i, MODULUS) for i in range(N)]
    print(f"N = {N}")
    top = min(N, 10)
    print(f"  >>> {top} first roots of unity")
    for i in range(top):
        print(f"      - {hex(ROOTS_OF_UNITY[i])}")

    BRP_ROOTS_OF_UNITY = bit_reversal_permutation(ROOTS_OF_UNITY)

    print(f"  >>> {top} first bit-reversed roots of unity")
    for i in range(top):
        print(f"      - {hex(BRP_ROOTS_OF_UNITY[i])}")