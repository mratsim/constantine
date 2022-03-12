# Constantine-backed protocols

This folder stores protocol implemented on top of Constantine.

## Ethereum Virtual Machine

Constantine implements precompiles primitives for the Ethereum virtual machine

- ECADD on BN254_Snarks (called `alt_bn128` in Ethereum), address 0x6, spec [EIP-196](https://eips.ethereum.org/EIPS/eip-196) and pricing [EIP-1108](https://eips.ethereum.org/EIPS/eip-1108)
- ECMUL on BN254_Snarks (called `alt_bn128` in Ethereum), address 0x7, spec [EIP-196](https://eips.ethereum.org/EIPS/eip-196) and pricing [EIP-1108](https://eips.ethereum.org/EIPS/eip-1108)
- ECPAIRING on BN254_Snarks (called `alt_bn128` in Ethereum), address 0x8, spec [EIP-197](https://eips.ethereum.org/EIPS/eip-197) and pricing [EIP-1108](https://eips.ethereum.org/EIPS/eip-1108)

Their main use-case is for use zero-knowledge proofs and zkRollups and be compatible with work on Zcash

- Succinct Non-Interactive Zero Knowledge
for a von Neumann Architecture\
  Eli Ben-Sasson, Alessandro Chiesa, Eran Tromer, Madars Virza\
  https://eprint.iacr.org/2013/879.pdf

