# KZG Polynomial Commitment research

Research for Ethereum 2.0 phase 1
to implement the Data Availability Sampling protocol

See

- https://dankradfeist.de/ethereum/2020/06/16/kate-polynomial-commitments.html
- https://github.com/protolambda/go-kate
- FK20: https://github.com/khovratovich/Kate/blob/master/Kate_amortized.pdf
- https://github.com/ethereum/research/tree/master/polynomial_reconstruction
- https://github.com/ethereum/research/tree/master/kzg_data_availability

# A note on EIP-7594 / Data Availability Sampling

PeerDAS requires the use of roots of unity `FIELD_ELEMENTS_PER_EXT_BLOB` == `2 * FIELD_ELEMENTS_PER_BLOB`

When generating roots of unity of degree `2^{n+1}`, the roots unique to degree 2^{n+1} are interspersed with roots common to 2^n and 2^{n+1}

However in actual implementation both KZG blobs and PeerDAS use bit-reversal permuted (brp) SRS.
`brp` values are reordered and conveniently they are reordered so that slicing the first half of roots of unity of 2^{n+1} we get the bit-reversed permuted roots of unity of 2^n

This can be checked with the following script

```python
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
```