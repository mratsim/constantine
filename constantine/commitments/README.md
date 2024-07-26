# Commitment schemes

https://en.wikipedia.org/wiki/Commitment_scheme

> A commitment scheme is a cryptographic primitive that allows one to commit to a chosen value (or chosen statement) while keeping it hidden to others, with the ability to reveal the committed value later. Commitment schemes are designed so that a party cannot change the value or statement after they have committed to it: that is, commitment schemes are binding.

## Use-cases

An important use-case missing from the Wikipedia article is:

"There exists a bundle of transactions that change the state of my database/ledger/blockchain to this state.". The whole bundle is not needed, only a short proof.

## KZG (Kate, Zaverucha, Goldberg)

- Constant-Size Commitments to Polynomials and Their Applications\
  Kate, Zaverucha, Goldberg, 2010\
  https://www.iacr.org/archive/asiacrypt2010/6477178/6477178.pdf\
  https://cacr.uwaterloo.ca/techreports/2010/cacr2010-10.pdf

- KZG commitments from the Lagrange basis without FFTs
  Drake, 2020
  https://ethresear.ch/t/kate-commitments-from-the-lagrange-basis-without-ffts/6950

- KZG Multiproofs
  Feist, Khovratovich, 2020
  https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html\
  https://github.com/khovratovich/Kate/blob/master/Kate_amortized.pdf

## Inner Product Arguments

- https://doc-internal.dalek.rs/bulletproofs/notes/inner_product_proof/index.html
- https://eprint.iacr.org/2019/1021
- https://zcash.github.io/halo2/background/pc-ipa.html
- https://raw.githubusercontent.com/daira/halographs/master/deepdive.pdf
- https://hackmd.io/yA9DlU5YQ3WtiFxC_2LAlg
- https://eprint.iacr.org/2020/499
- https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

> [!NOTE]
> Halo2-like IPA is slightly different from Bulletproofs
> (https://doc-internal.dalek.rs/bulletproofs/notes/inner_product_proof/index.html)
> see 2019/1021, 3.1, the vector b is fixed and part of the Common Reference String
> in our case it's instantiated to the Lagrange basis polynomial.
> Hence the vector H mentioned in
> https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html
> is not necessary as well.

## Transcripts

We take inspiration from

- https://merlin.cool/
  https://github.com/dalek-cryptography/merlin
- https://github.com/crate-crypto/verkle-trie-ref/blob/master/ipa/transcript.py
- https://github.com/zcash/halo2/blob/halo2_proofs-0.3.0/halo2_proofs/src/transcript.rs
- https://github.com/arkworks-rs/poly-commit/blob/12f5529/poly-commit/src/ipa_pc/mod.rs#L34-L44

We MUST be compatible with `verkle-trie-ref` to be used in Ethereum Verkle Tries.

In summary, a transcript acts like a Cryptographic Sponge with duplex construction that can absorb entropy and squeeze out challenges.

However, even if we generalize the transcript API,
unfortunately the labeling differ (if any) and the absorb/challenge sequences and what is absorbed in the transcript are very different.

So the commitments have to be protocol-specific.

Attacks on weak Fiat-Shamir challenges are described in-depth in
- https://eprint.iacr.org/2023/691

## Protocols

- quotient check
