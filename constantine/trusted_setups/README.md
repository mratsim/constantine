# Trusted Setup Interchange Format

## Table of contents

<!-- TOC -->

- [Trusted Setup Interchange Format](#trusted-setup-interchange-format)
    - [Table of contents](#table-of-contents)
    - [Overview](#overview)
    - [Metadata](#metadata)
    - [Schema items descriptors](#schema-items-descriptors)
        - [Quick algebra refresher](#quick-algebra-refresher)
        - [Notation](#notation)
        - [Schema items](#schema-items)
            - [Recommendation](#recommendation)
    - [Data](#data)
        - [𝔾1 and 𝔾2: Elliptic curve serialization](#%F0%9D%94%BE1-and-%F0%9D%94%BE2-elliptic-curve-serialization)
        - [𝔽r and 𝔽p: Finite Fields serialization](#%F0%9D%94%BDr-and-%F0%9D%94%BDp-finite-fields-serialization)
            - [Representation](#representation)
                - [Montgomery 32-bit vs 64-bit](#montgomery-32-bit-vs-64-bit)
                - [Special-form primes [unspecified]](#special-form-primes-unspecified)
        - [𝔽p² serialization](#%F0%9D%94%BDp%C2%B2-serialization)
        - [Larger extension field serialization [unspecified]](#larger-extension-field-serialization-unspecified)
            - [𝔽p⁴](#%F0%9D%94%BDp%E2%81%B4)
            - [𝔽p¹² / 𝔾t](#%F0%9D%94%BDp%C2%B9%C2%B2--%F0%9D%94%BEt)
    - [Copyright](#copyright)
    - [Citation](#citation)

<!-- /TOC -->

## Overview

- Format name: `Trusted setup interchange format`
- Format extension: `.tsif`

The format is chosen to allow:
- efficient copying,
- using the trusted setups as mmap-ed files on little-endian 64-bit machines,
- parallel processing

Hence the metadata should be separated from data and data should appear at precise computable positions
without needing to scan the file first.

As little-endian 64-bit systems are significantly more likely to use trusted setups, this format optimize operations for those machines.

This covers:
- x86-64 (Intel and AMD CPUs after 2003)
- ARM64  (i.e. Apple Macs after 2020, phones after 2014)
- RISC-V
- Nvidia, AMD, Intel GPUs

Furthermore, besides word-level (int32, int64) endianness,
most (all?) big integer backends cryptographic or not (GMP, LLVM APint, Go bigints, Java bigints, ...) use a little-endian ordering of limbs.

## Metadata

We described the format with `n` schema items and `i` an integer in the range `[0, n)`

| Offset (byte) | Name         | Description                               | Size (in bytes) | Syntax                                                      | Example                                                                                                                                 | Rationale                                                                                                                                      |
|---------------|--------------|-------------------------------------------|-----------------|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| 0             | Magic number | Fixed bytes at the beginning of each file | 12              | Hex E28883 E28B83 E28888 E2888E                             | Unicode string "∃⋃∈∎". Read as "There exists an union of elements of proofs" Unicode: [U+2203, U+222A, U+2208, U+220E] encoded in UTF-8 | Distinguish the file format even with incorrect extension.                                                                                     |
| 12            | version      | format version                            | 4               | v{major}.{minor}                                            | `v1.0`                                                                                                                                  | Compatibility and graceful decoding failures.                                                                                                  |
| 16            | protocol     | a protocol name                           | 32              | any lowercase a-z 0-9 and underscore, padded with NUL bytes | `ethereum_deneb_kzg`                                                                                                                    | Graceful errors. For namespacing it is recommended to use `{application}_{fork/version/proposal that introduced the trusted setup}_{protocol}` |
| 48            | Curve | Elliptic curve name | 15 | any lowercase a-z 0-9 and underscore, padded with NUL bytes | `bls12_381` or `bn254_snarks` or `bandersnatch` or `edwards25519` or `montgomery25519` | Size chosen to fit long curve names like `bandersnatch` or `edwards25519`. Ideally the name uniquely identify the curve, for example there are multiple BN254 curves in the litterature (but only one used in trusted setups) and there are multiple representations of Curve25519 (Montgomery or Twisted Edwards)
| 63            | fields  | number of data fields `n`       | 1               | {n}, `n` is encoded as a 8-bit integer | `3` | Compute byte offsets and buffer(s) size |
| 64            | 1ˢᵗ schema item | Metadata | 32 | see dedicated section | see dedicated section | |
| 64 + i*32     | iᵗʰ schema item | Metadata | 32 | see dedicated section | see dedicated section | |
| 64 + n*32     | Padding | Padding | `n*32 mod 64`: 0 or 32 | Either nothing or 0x00 repeated 32 times | | Ensure the data starts at 64-byte boundary for SIMD processing (can help for bit-reversal permutation, coordinates copy between serialized and memory representation, big-endian/little-endian conversion) |
| 64 + n\*32 + (n\*32 mod 64) | Data | Data | see dedicated section | see dedicated section | | |

## Schema items descriptors

### Quick algebra refresher

- A group is a set of elements:
  - with a binary operation to combine them called the group law
  - with a neutral element
  - with an inverse, applying the group law on an element and its inverse results in the neutral element.

  - the group order or cardinality is the number of elements in the set.
  - the group can use the additive or multiplicative notation.
  - the group can be cyclic. i.e. all elements of the group can be generated
    by repeatedly applying the group law.

  The additive/multiplicative notation is chosen by social consensus,
  hence confusion of scalar multiplication \[a\]P or exponentiation Pᵃ for elliptic curves.

- A field is a set of elements
  - with two group laws, named addition and multiplication
  - and the corresponding group properties (additive/multiplicative inverse and neutral elements)

  - A field can be finite (modular arithmetic modulo a prime) or infinite (the real numbers)

### Notation

- 𝔽r is a finite-field of prime order r with laws: modular addition and modular multiplication (modulo `r`)
- 𝔾1 is an additive group of prime order r with law: elliptic curve addition
- 𝔾2 is an additive group of prime order r with law: elliptic curve addition

For an additive group, we use the notation:
  [a]P to represent P+P+...+P\
  applying the group law `a` times, i.e. the scalar multiplication.

For a multiplicative group, we use the notation:
  Pᵃ to represent P\*P\*...\*P\
  applying the group law `a` times, i.e. the exponentiation

Furthermore we use the notation
- [a]₁ for the scalar multiplication of the 𝔾1 generator by a, a ∈ 𝔽r
- [b]₂ for the scalar multiplication of the 𝔾2 generator by b, b ∈ 𝔽r

### Schema items

Each schema item is described by 32 bytes of metadata, either
- `srs_monomial` + {`g1` or `g2`} + {`asc` or `brp`} + {sizeof(element)} + {number of elements}
- `srs_lagrange` + {`g1` or `g2`} + {`asc` or `brp`} + {sizeof(element)} + {number of elements}
- `roots_unity` + `fr`           + {`asc` or `brp`} + {sizeof(element)} + {number of elements}

i.e.
- 15 bytes for the field description in lower-case \[a-z\], numbers and underscore. Padded right with NUL bytes.
- 2 bytes for the group or field of each element
- a 3-byte tag indicating if the srs or roots of unity are stored
  - in ascending order of powers of tau (τ), the trusted setup secret.
  i.e.
    - for monomial storage: `[[1]₁, [τ]₁, [τ²]₁, ... [τⁿ⁻¹]₁]`
    - for lagrange storage: `[[𝐿ₜₐᵤ(ω⁰)]₁, [𝐿ₜₐᵤ(ω¹)]₁, [𝐿ₜₐᵤ(ω²)]₁, ... [𝐿ₜₐᵤ(ωⁿ⁻¹)]₁]`
    - for roots of unity: `[ω⁰, ω¹, ..., ωⁿ⁻¹]`
  - or in [bit-reversal permutation](https://en.wikipedia.org/wiki/Bit-reversal_permutation)
- 4 bytes for the size of a single element, serialized as a little-endian 32-bit integer.
- 8 bytes for the number of elements, serialized as a little-endian 64-bit integer.

#### Recommendation

Some protocols use the same curves but different generators `[1]₁` (𝔾1 generator)  and `[1]₂` (𝔾2 generator),
also most libraries hard code the generator as a constant.

For example for the Pasta curves:
- Pallas
  - Arkworks and Zcash: (-1, 2)
  - Mina: (1,12418654782883325593414442427049395787963493412651469444558597405572177144507)
- Vesta
  - Arkworks and Zcash: (-1, 2)
  - Mina: (1,11426906929455361843568202299992114520848200991084027513389447476559454104162)

Check that the first element of the deserialized SRS match the library generator.

## Data

Data sections are guaranteed to start at 64-byte boundaries. Padding is done with NUL bytes (0x00)
Data is stored in little-endian for words and limbs and in ascending order of prime power for extension fields.

Each item is stored adjacent to each other, item size and number of items are described in the schema items.

Beyond 𝔽r, 𝔾1, 𝔾2 introduced in the metadata section, we introduce:
- p, the prime modulus of the curve
  p is distinct from the curve order r
- 𝔽p a finite field with prime modulus p
- 𝔽pⁿ, an extension field of characteristic p, with n coordinates, each element of 𝔽p

### 𝔾1 and 𝔾2: Elliptic curve serialization

Elliptic curve points coordinates for:
- a short Weierstrass curve with equation `y² = x³ + ax + b` are stored in order (x, y).
- a twisted Edwards curve with equation `ax² + y² = 1+dx²y²` are stored in order (x, y).

x and y are elements of 𝔽p or 𝔽pⁿ

It is possible to store only x and recover y from the curve equation.
However:
- this prevents memory copying or memory mapping
- recovery involves a square root which is extremely slow.
  - Deserialization of a compressed BLS12 381 𝔾1 point (without subgroup check) is in the order of 40000 cycles.
    A memcpy would take ~1.5 cycles so about 26666x faster.
  - Deserialization of a compressed BLS12 381 𝔾2 point (without subgroup check) is in the order of 70000 cycles.
    A memcpy would take ~3 cycles so about 23333x faster.
- Some trusted setups have hundreds of millions of points (e.g. Filecoin 2²⁷ = 134 217 728 BLS12-381 𝔾1 points)
  - A compressed representation would need on a 4GHz CPU: 2²⁷ points * 40000 cycles / 4.10⁹ cycles/s = 1352 seconds to decompress, without post-processing like bit-reversal permutation, compared to 5us uncompressed.
  - The doubled size (12.88GB instead of 6.44GB with 96 bytes BLS12-381 𝔾1 points)
    is a reasonable price as it is not even stored in the blockchain.
    Furthermore, memory-constrained devices can use memory-mapping instead of spending their RAM.

### 𝔽r and 𝔽p: Finite Fields serialization

Each element of 𝔽r or 𝔽p is stored:
- in little-endian for limb-endianness, i.e. least significant word first.
- in little-endian for word-endianness, i.e. within a word, least significant bit first.
- rounded to 8-byte boundary, padded with NUL byte.

This ensures that on little-endian machines, the bit representation is the same whether it is 32 or 64 bits:
- word₀, word₁, word₂, word₃ for 64-bit words.
- word₀, word₁, word₂, word₃, word₄, word₅, word₆, word₇ for 32-bit words.

Example, a 224-bit modulus (for P224 curve), would need 7 uint32 = 28 bytes or 4 uint64 = 32 bytes for in-memory representation.

#### Representation

For fields defined over generic primes, fields elements are stored in `Montgomery representation`.
i.e. for all a ∈ 𝔽p, we store a' = aR (mod p), with:
- `R = (2^WordBitWidth)^numWords`
- WordBitWidth = 64
- numWords = ceil_division(log₂(p), WordBitWidth) = (log₂(p) + 63)/64. `log₂(p)` is the number of bits in the prime p

Rationale:
  All libraries are using the Montgomery representation for general primes for efficiency of modular reduction without division.

  Storing directly in Montgomery representation allows as-is memory copies or memory mapping on little-endian 64-bit CPUs.

##### Montgomery 32-bit vs 64-bit

Note that the Montgomery representation may differ between 32-bit and 64-bit if the number of words in 32-bit is not double the number of words in 64-bit, i.e. if `32*numWords₃₂ != 64*numWords₆₄`.

This is the case for P224, but not for any curves used in zero-knowledge proofs at the time of writing (May 2023)

##### Special-form primes [unspecified]

Fields defined over pseudo-Mersenne primes (Crandall primes) in the form 2ᵏ-c like 2²⁵⁵-19
or generalized Mersenne primes (Solinas primes) in the form of a polynomial p(x) with x = 2ᵐ like secp256k1, P256, ...
can use a fast modular reduction and do not need the Montgomery representation.

So serializing them in Montgomery form is unnecessary.

However, at the time of writing (May 2023), no special-form primes are used in trusted setups as trusted setups are quite costly to create hence they need to provide significant benefits, short fixed size proofs with sublinear verification time for example which requires pairing-friendly curves.

### 𝔽p² serialization

Field-endianness is little-endian.

When 𝔾1 and/or 𝔾2 are defined over 𝔽p² with p the prime modulus of the curve,
A field element a = (x, y) ∈ 𝔽p², is represented x+𝘫y with 𝘫 a quadratic non-residue in 𝔽p
and serialized `[a, b]`

### Larger extension field serialization [unspecified]

For now, this is unspecified. Here are relevant comments.

####  𝔽p⁴

This is relevant for BLS24 curves as 𝔾2 is defined over 𝔽p⁴.

The efficient in-memory storage is as a tower of extension fields
with 𝘶 a quadratic non-residue of 𝔽p to define 𝔽p² over 𝔽p (i.e. 𝘶 is not a square in 𝔽p)
and 𝘷 a quadratic non-residue of 𝔽p² to define 𝔽p⁴ over 𝔽p² (i.e. 𝘷 is not a square in 𝔽p)

i.e. x ∈ 𝔽p⁴ = (a + 𝘶b) + (c + 𝘶d)𝘷 = a + 𝘶b + 𝘷c + 𝘶𝘷d

And the canonical representation would use
μ ∈ 𝔽p a quartic non-residue of 𝔽p to define 𝔽p⁴ over 𝔽p (i.e. μ⁴ = x has no solution x ∈ 𝔽p)

with x ∈ 𝔽p⁴ = a' + μb' + μ²c' + μ³d'

For 𝔽p⁴, the efficient in-memory storage and the canonical representation match.

#### 𝔽p¹² / 𝔾t

For common curves of embedding degree 12 (BN254_Snarks, BLS12_381, BLS12_377),
are there situations which need to serialize 𝔾t elements, defined over 𝔽p¹²?

Given a sextic twist, we can express all elements in terms of z = SNR¹ᐟ⁶ (sextic non-residue)

The canonical direct sextic representation uses coefficients

   c₀ + c₁ z + c₂ z² + c₃ z³ + c₄ z⁴ + c₅ z⁵

with z = SNR¹ᐟ⁶

__The cubic over quadratic towering__

  (a₀ + a₁ u) + (a₂ + a₃u) v + (a₄ + a₅u) v²

with u = (SNR)¹ᐟ² and v = z = u¹ᐟ³ = (SNR)¹ᐟ⁶

__The quadratic over cubic towering__

  (b₀ + b₁x + b₂x²) + (b₃ + b₄x + b₅x²)y

with x = (SNR)¹ᐟ³ and y = z = x¹ᐟ² = (SNR)¹ᐟ⁶

__Mapping between towering schemes__

```
canonical <=> cubic over quadratic <=> quadratic over cubic
   c₀     <=>        a₀            <=>            b₀
   c₁     <=>        a₂            <=>            b₃
   c₂     <=>        a₄            <=>            b₁
   c₃     <=>        a₁            <=>            b₄
   c₄     <=>        a₃            <=>            b₂
   c₅     <=>        a₅            <=>            b₅
```

In that scheme, all coordinates are defined as 𝔽p² elements.

Hence specifying 𝔽p¹² extension field representation requires to agree on:
- Towering serialization (cube over quad or quad over cube) vs direct sextic representation
- For direct representation, ascending or descending in powers of the sextic non-residue?

Furthermore 𝔾t have special properties and can be stored in compressed form using trace-based compression or torus-based compression, with compression ratio from 1/3 to 4/6 with varying decompression cost (from not decompressible but usable for pairings computations to decompressible at the cost of an inversion to decompressible at the cost of tens of 𝔽p multiplications).

## Copyright

Copyright and related rights waived via CC0.

## Citation

Please cite this document as:

Mamy Ratsimbazafy, "Trusted Setup Interchange Format [DRAFT]", May 2023, Available: https://github.com/mratsim/constantine/tree/master/constantine/trusted_setups/README.md