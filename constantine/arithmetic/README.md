# BigInt and Finite Field Arithmetic

This folder contains the implementation of
- big integers
- finite field arithmetic (i.e. modular arithmetic)

As a tradeoff between speed, code size and compiler-enforced dependent type checking, the library is structured the following way:
- Finite Field: statically parametrized by an elliptic curve
- Big Integers: statically parametrized by the bit width of the field modulus
- Limbs: statically parametrized by the number of words to handle the bitwidth

This allows to reuse the same implementation at the limbs-level for
curves that required the same number of words to save on code size,
for example secp256k1 and BN254.
It also enables compiler unrolling, inlining and register optimization,
where code size is not an issue for example for multi-precision addition.

## Algorithms

### Finite field multiplication

- Analyzing and Comparing Montgomery Multiplication Algorithms
  Cetin Kaya Koc and Tolga Acar and Burton S. Kaliski Jr.
  http://pdfs.semanticscholar.org/5e39/41ff482ec3ee41dc53c3298f0be085c69483.pdf

- Montgomery Arithmetic from a Software Perspective\
  Joppe W. Bos and Peter L. Montgomery, 2017\
  https://eprint.iacr.org/2017/1057

- Arithmetic of Finite Fields\
  Chapter 5 of Guide to Pairing-Based Cryptography\
  Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017\
  https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields

- Faster big-integer modular multiplication for most moduli\
  Gautam Botrel, Gus Gutoski, and Thomas Piellard, 2020\
  https://hackmd.io/@zkteam/modular_multiplication
