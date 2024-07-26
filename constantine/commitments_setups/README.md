# Reference Strings & Trusted Setups

This folder holds code and data related to Common Reference Strings, Structured Reference Strings and trusted setups necessary
for implemented protocols.

It also holds a spec proposal for an efficient trusted setup format,
to limit memory and deserialization cost for very large trusted setups.

[Trusted Setup Interchange Format](./spec_trusted_setup_interchange_format.md)

## Protocols

- The Ethereum KZG EIP-4844 protocol is implemented. \
  As the trusted setup is small, it is stored directly in the repo.\
  The trusted setup is available from the KZG ceremony at https://github.com/CarlBeek/kzg-ceremony-verifier/blob/master/output_setups/trusted_setup_4096.json \
  To avoid vulnerabilities in json parsers (no formally-verified ones exist), we use the plaintext setup from the audited and fuzzed reference implementation at https://github.com/ethereum/c-kzg-4844/blob/main/src/trusted_setup.txt
