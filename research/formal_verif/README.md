# Formal verification

This folder will hold code related to formal verification.

## References

- Fiat Crypto: Synthesizing Correct-by-Construction Code for Cryptographic Primitives
  https://github.com/mit-plv/fiat-crypto
- CryptOpt: Verified Compilation with Randomized Program Search for Cryptographic Primitives
  https://github.com/0xADE1A1DE/CryptOpt

- [Andres Erbsen, Jade Philipoom, Jason Gross, Robert Sloan, Adam Chlipala. Simple High-Level Code For Cryptographic Arithmetic -- With Proofs, Without Compromises. To Appear in Proceedings of the IEEE Symposium on Security & Privacy 2019 (S&P'19). May 2019.](http://adam.chlipala.net/papers/FiatCryptoSP19/FiatCryptoSP19.pdf). This paper describes multiple field arithmetic implementations, and an older version of the compilation pipeline (preserved [here](https://github.com/mit-plv/fiat-crypto/tree/sp2019latest)). It is somewhat space-constrained, so some details are best read about in theses below.
- [Jade Philipoom. Correct-by-Construction Finite Field Arithmetic in Coq. MIT Master's Thesis. February 2018.](http://adam.chlipala.net/theses/jadep_meng.pdf) Chapters 3 and 4 contain a detailed walkthrough of the field arithmetic implementations (again, targeting the previous compilation pipeline).
- [Andres Erbsen. Crafting Certified Elliptic CurveCryptography Implementations in Coq. MIT Master's Thesis. June 2017.](
http://adam.chlipala.net/theses/andreser_meng.pdf) Section 3 contains a whirlwind introduction to synthesizing field arithmetic code using coq, without assuming Coq skills, but covering a tiny fraction of the overall library. Sections 5 and 6 contain the only write-up on the ellitpic-curve library in this repository.
- The newest compilation pipeline does not have a separate document yet, but this README does go over it in some detail.
