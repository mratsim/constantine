# Optimizations

This document lists the optimizations relevant to an elliptic curve or pairing-based cryptography library and whether Constantine has them implemented.

The optimizations can be of algebraic, algorithmic or "implementation details" nature. Using non-constant time code is always possible, it is listed if the speedup is significant.

## Big Integers

- Conditional copy
  - [x] Loop unrolling
  - [x] x86: Conditional Mov
  - [x] x86: Full Assembly implementation
  - [ ] SIMD instructions
- Add/Sub
  - [x] int128
  - [x] add-with-carry, sub-with-borrow intrinsics
  - [x] loop unrolling
  - [x] x86: Full Assembly implementation
- Multiplication
  - [x] int128
  - [x] loop unrolling
  - [x] Comba multiplication / product Scanning
  - [ ] Karatsuba
  - [ ] Karatsuba + Comba
  - [x] x86: Full Assembly implementation
  - [x] x86: MULX, ADCX, ADOX instructions
  - [x] Fused Multiply + Shift-right by word (for Barrett Reduction and approximating multiplication by fractional constant)
- Squaring
  - [x] Dedicated squaring functions
  - [x] int128
  - [x] loop unrolling
  - [x] x86: Full Assembly implementation
  - [x] x86: MULX, ADCX, ADOX instructions

## Finite Fields & Modular Arithmetic

- Representation
  - [x] Montgomery Representation
  - [ ] Barret Reduction
  - [ ] Unsaturated Representation
    - [ ] Mersenne Prime (2ᵏ - 1),
    - [ ] Generalized Mersenne Prime (NIST Prime P256: 2^256 - 2^224 + 2^192 + 2^96 - 1)
    - [ ] Pseudo-Mersenne Prime (2^m - k for example Edwards25519: 2^255 - 19)
    - [ ] Golden Primes (φ^2 - φ - 1 with φ = 2ᵏ for example Ed448-Goldilocks: 2^448 - 2^224 - 1)
    - [ ] any prime modulus (lazy carry)

- Montgomery Reduction
  - [x] int128
  - [x] loop unrolling
  - [x] x86: Full Assembly implementation
  - [x] x86: MULX, ADCX, ADOX instructions

- Addition/substraction
  - [x] int128
  - [x] add-with-carry, sub-with-borrow intrinsics
  - [x] loop unrolling
  - [x] x86: Full Assembly implementation
  - [x] Addition-chain for small constants

- Montgomery Multiplication
  - [x] Fused multiply + reduce
  - [x] int128
  - [x] loop unrolling
  - [x] x86: Full Assembly implementation
  - [x] x86: MULX, ADCX, ADOX instructions
  - [x] no-carry optimization for CIOS (Coarsely Integrated Operand Scanning)
  - [x] FIPS (Finely Integrated Operand Scanning)

- Montgomery Squaring
  - [x] Dedicated squaring functions
  - [x] Fused multiply + reduce
  - [x] int128
  - [x] loop unrolling
  - [x] x86: Full Assembly implementation
  - [x] x86: MULX, ADCX, ADOX instructions
  - [ ] no-carry optimization for CIOS (Coarsely Integrated Operand Scanning)

- Addition chains
  - [x] unreduced squarings/multiplications in addition chains

- Exponentiation
  - [x] variable-time exponentiation
  - [x] fixed window optimization _(sliding windows are not constant-time)_
  - [ ] NAF recoding
  - [ ] windowed-NAF recoding
  - [ ] SIMD vectorized select in window algorithm
  - [x] Montgomery Multiplication with no final substraction,
    - Bos and Montgomery, https://eprint.iacr.org/2017/1057.pdf
      - Colin D Walter, https://colinandmargaret.co.uk/Research/CDW_ELL_99.pdf
      - Hachez and Quisquater, https://link.springer.com/content/pdf/10.1007%2F3-540-44499-8_23.pdf
    - Gueron, https://eprint.iacr.org/2011/239.pdf
  - [ ] Pippenger multi-exponentiation (variable-time)
    - [ ] parallelized Pippenger

- Inversion (constant-time baseline, Little-Fermat inversion via a^(p-2))
  - [x] Constant-time binary GCD algorithm by Möller, algorithm 5 in https://link.springer.com/content/pdf/10.1007%2F978-3-642-40588-4_10.pdf
  - [x] Addition-chain for a^(p-2)
  - [x] Constant-time binary GCD algorithm by Bernstein-Yang, https://eprint.iacr.org/2019/266
  - [ ] Constant-time binary GCD algorithm by Pornin, https://eprint.iacr.org/2020/972
  - [x] Constant-time binary GCD algorithm by BY with half-delta optimization by libsecp256k1, formally verified, https://eprint.iacr.org/2021/549
  - [x] Simultaneous inversion

- Square Root (constant-time)
  - [x] baseline sqrt via Little-Fermat for `p ≡ 3 (mod 4)`
  - [x] baseline sqrt via Little-Fermat for `p ≡ 5 (mod 8)`
  - [ ] baseline sqrt via Little-Fermat for `p ≡ 9 (mod 16)`
  - [x] baseline sqrt via Tonelli-Shanks for any prime.
  - [x] sqrt via addition-chain
  - [x] Fused sqrt + testIfSquare (Euler Criterion or Legendre symbol or Kronecker symbol)
  - [x] Fused sqrt + 1/sqrt
  - [x] Fused sqrt + 1/sqrt + testIfSquare

## Extension Fields

- [x] Lazy reduction via double-precision base fields
- [x] Sparse multiplication
- Fp2
  - [x] complex multiplication
  - [x] complex squaring
  - [x] sqrt via the constant-time complex method (Adj et al)
  - [x] sqrt using addition chain
  - [x] fused complex method sqrt by rotating in complex plane
- Cubic extension fields
  - [x] Toom-Cook polynomial multiplication (Chung-Hasan)

## Elliptic curve

- Weierstrass curves:
  - [x] Affine coordinates
  - [x] Homogeneous projective coordinates
    - [x] Projective complete formulae
    - [x] Mixed addition
  - [x] Jacobian projective coordinates
    - [x] Jacobian complete formulae
    - [x] Mixed addition
    - [ ] Conjugate Mixed Addition
    - [ ] Composites Double-Add 2P+Q, tripling, quadrupling, quintupling, octupling

- [x] scalar multiplication
  - [x] fixed window optimization
  - [ ] constant-time NAF recoding
  - [ ] constant-time windowed-NAF recoding
    - [ ] SIMD vectorized select in window algorithm
  - [x] constant-time endomorphism acceleration
    - [ ] using NAF recoding
    - [x] using GLV-SAC recoding
  - [x] constant-time windowed-endomorphism acceleration
    - [ ] using wNAF recoding
    - [x] using windowed GLV-SAC recoding
    - [ ] SIMD vectorized select in window algorithm
  - [ ] Fixed-base scalar mul

- [ ] Multi-scalar-mul
  - [ ] Strauss multi-scalar-mul
  - [ ] Bos-Coster multi-scalar-mul
  - [ ] Pippenger multi-scalar-mul (variable-time)
    - [ ] parallelized Pippenger

## Pairings

- Frobenius maps
  - [x] Sparse Frobenius coefficients
  - [x] Coalesced Frobenius in towered Fields
  - [x] Coalesced Frobenius powers

- Line functions
  - [x] Homogeneous projective coordinates
    - [x] D-Twist
      - [x] Fused line add + elliptic curve add
      - [x] Fused line double + elliptic curve double
    - [x] M-Twist
      - [x] Fused line add + elliptic curve add
      - [x] Fused line double + elliptic curve double
    - [x] 6-way sparse multiplication line * Gₜ element
  - [ ] Jacobian projective coordinates
    - [ ] D-Twist
      - [ ] Fused line add + elliptic curve add
      - [ ] Fused line double + elliptic curve double
    - [ ] M-Twist
      - [ ] Fused line add + elliptic curve add
      - [ ] Fused line double + elliptic curve double
    - [x] 6-way sparse multiplication line * Gₜ element
  - [ ] Affine coordinates
    - [ ] 7-way sparse multiplication line * Gₜ element
    - [ ] Pseudo-8 sparse multiplication line * Gₜ element

- Miller Loop
  - [x] NAF recoding
  - [ ] Quadruple-and-add and Octuple-and-add
  - [x] addition chains

- Final exponentiation
  - [x] Cyclotomic squaring
    - [x] Karabina's compressed cyclotomic squarings
  - [x] Addition-chain for exponentiation by curve parameter
  - [x] BN curves: Fuentes-Castañeda
  - [ ] BN curves: Duquesne, Ghammam
  - [ ] BLS curves: Ghamman, Fouotsa
  - [x] BLS curves: Hayashida, Hayasaka, Teruya

- [x] Multi-pairing
  - [ ] Line accumulation
  - [ ] Parallel Multi-Pairing

## Hash-to-curve

- Clear cofactor
  - [x] BLS G1: Wahby-Boneh
  - [ ] BLS G2: Scott et al
  - [ ] BLS G2: Fuentes-Castañeda
  - [x] BLS G2: Budroni et al, endomorphism accelerated
  - [x] BN G2: Fuentes-Castañeda
  - [ ] BW6-761 G1
  - [ ] BW6-761 G2

- Subgroup check
  - [ ] BLS G1: Bowe, endomorphism accelerated
  - [ ] BLS G2: Bowe, endomorphism accelerated
  - [x] BLS G1: Scott, endomorphism accelerated
  - [x] BLS G2: Scott, endomorphism accelerated
