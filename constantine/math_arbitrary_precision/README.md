# Arbitrary-precision math backend

While cryptographic protocols allow Constantine to focus on named elliptic curves
and so fixed precision arithmetic, some protocols might need arbitrary-precision.

For example, this can cover can cover:
- Modular exponentiation https://eips.ethereum.org/EIPS/eip-198
- RSA (though in practice RSA2048, RSA3072 and RSA 4096 are likely the only sizes needed)
- primality testing

And arbitrary precision elliptic curves would allow implementing the Lenstra elliptic curve factorization method
