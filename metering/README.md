# Metering

## Overview

This folder allows measuring an accurate cost of high-level primitives in terms of basic operations (Field mul, add, inv, ...)

### For optimization

Metering allows choosing the best algorithm or representation when multiple are available, for example choosing elliptic curve coordinates between affine projective or jacobian? Also some might be faster for certain fields (Fp or Fp2) or certain curves.

It also allows to focus tuning operations that underlie the high-level building blocks. This is not a replacement for profiling but a complement.
Metering allows reasoning at the complexity and algorithmic level while profiling allows reasoning at the hardware and timing level.

### For blockchains

Important for blockchain to correctly price the VM opcodes. Pricing too low would allow denial-of-service attacks, too high will  disincentivize their use.

Note: this only takes into account the number of operations
but does not take into account stack usage for temporaries.

## Measuring cost

```Nim
var costs_BLS12_381: Table[string, int]

costs_BLS12_381.meter(
  pairing_bls12(
    Fp12[BLS12_381],
    ECP_ShortW_Proj[Fp[BLS12_381, NotOnTwist]],
    ECP_ShortW_Proj[Fp2[BLS12_381, OnTwist]],
  )
)
```
