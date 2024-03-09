# Proof systems

## Implementation "details"

For proof systems, we relax some requirements used in the rest of Constantine:
- Nim heap-allocated types like sequences and strings may be used.

Proof systems are not expected to run on resource-restricted devices
or trusted enclaves.
