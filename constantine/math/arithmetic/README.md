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
  https://hackmd.io/@gnark/modular_multiplication

### Square roots

- Probabilistic Primality Testing
  A. Oliver L. Atkin
  http://algo.inria.fr/seminars/sem91-92/atkin.pdf

- Square root computation over even extension fields
  Gora Adj, Francisco Rodríguez-Henríquez, 2012
  https://eprint.iacr.org/2012/685

- A Complete Generalization of Atkin’s Square Root Algorithm
  Armand Stefan Rotaru, Sorin Iftene, 2013
  https://profs.info.uaic.ro/~siftene/fi125(1)04.pdf

- Computing Square Roots Faster than the Tonelli-Shanks/Bernstein Algorithm
  Palash Sarkar, 2020
  https://eprint.iacr.org/2020/1407