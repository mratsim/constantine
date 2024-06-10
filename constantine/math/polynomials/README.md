# Polynomials

This implements primitives to work with polynomials
in coefficient form and in Lagrange form.

No currently implemented protocol requires constant-time operations or use a secret key with polynomials.
Hence the _vartime suffix is not used even for vartime operations.

This will be revisited when secret polynomials are needed
for example for Shamir Secret Sharing or hiding polynomials in ZK proof systems.
