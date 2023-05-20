# Commitment schemes

https://en.wikipedia.org/wiki/Commitment_scheme

> A commitment scheme is a cryptographic primitive that allows one to commit to a chosen value (or chosen statement) while keeping it hidden to others, with the ability to reveal the committed value later. Commitment schemes are designed so that a party cannot change the value or statement after they have committed to it: that is, commitment schemes are binding.

## Use-cases

An important use-case missing from the Wikipedia article is:

"There exists a bundle of transactions that change the state of my database/ledger/blockchain to this state.". The whole bundle is not needed, only a short proof.

## KZG Polynomial Commitments

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