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

The file m_pairings has a minimal example for the current state.

```Nim
var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactor()

proc pairingBLS12Meter*(C: static Curve) =
  let
    P = rng.random_point(ECP_ShortW_Prj[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])

  var f: Fp12[C]

  resetMetering()
  f.pairing_bls12(P, Q)

resetMetering()
pairingBLS12Meter(BLS12_381)
const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
reportCli(Metrics, flags)
```

After compiling with
```
nim c -r --hints:off --warnings:off --verbosity:0 -d:danger -d:CTT_METER --outdir:build metering/m_pairings.nim
```

We get

```
bench xoshiro512** seed: 1611954740

CPU: Intel(R) Core(TM) i9-9980XE CPU @ 3.00GHz
The CPU Cycle Count is indicative only. It cannot be used to compare across systems, works at your CPU nominal frequency and is sensitive to overclocking, throttling and frequency scaling (powersaving and Turbo Boost).


|--------------------------------------------------|--------------|--------------------|---------------|-----------------|--------------------------|--------------------------|
|                    Procedures                    |  # of Calls  | Throughput (ops/s) |   Time (µs)   |  Avg Time (µs)  | CPU cycles (in billions) | Avg cycles (in billions) |
|                   UseAssembly                    |              |                    |               |                 |     indicative only      |     indicative only      |
|--------------------------------------------------|--------------|--------------------|---------------|-----------------|--------------------------|--------------------------|
|`+=`*                                             |         11473|                 inf|          0.000|            0.000|
|`-=`*                                             |         18603|   2067000000000.000|          0.009|            0.000|
|double*                                           |          7212|   2404000000000.000|          0.003|            0.000|
|sum*                                              |         21058|   7019333333333.333|          0.003|            0.000|
|diff*                                             |          8884|   2961333333333.333|          0.003|            0.000|
|diff*                                        |            10|                 inf|          0.000|            0.000|
|double*                                           |          4186|                 inf|          0.000|            0.000|
|prod*                                             |         14486|   1609555555555.555|          0.009|            0.000|
|square*                                           |            16|                 inf|          0.000|            0.000|
|neg*                                              |          2093|                 inf|          0.000|            0.000|
|neg*                                              |          2050|                 inf|          0.000|            0.000|
|div2*                                             |           512|                 inf|          0.000|            0.000|
|`*=`*                                             |          5584|    620444444444.444|          0.009|            0.000|
|square*                                           |          1116|                 inf|          0.000|            0.000|
|square_repeated*                                  |           126|      1235294117.647|          0.102|            0.001|
|finalExpEasy*                                     |             1|         5555555.556|          0.180|            0.180|
|cyclotomic_inv*                                   |             5|      1000000000.000|          0.005|            0.001|
|cyclotomic_inv*                                   |             1|                 inf|          0.000|            0.000|
|cyclotomic_square*                                |             6|        70588235.294|          0.085|            0.014|
|cyclotomic_square*                                |           309|        70499657.769|          4.383|            0.014|
|cycl_sqr_repeated*                                |            25|         5556790.398|          4.499|            0.180|
|millerLoopGenericBLS12*                           |             1|          279251.606|          3.581|            3.581|
|finalExpHard_BLS12*                               |             1|          178475.817|          5.603|            5.603|
|pairing_bls12*                                    |             1|          105196.718|          9.506|            9.506|
|--------------------------------------------------|--------------|--------------------|---------------|-----------------|--------------------------|--------------------------|
```

The reporting and tracing will be improved to collect the fields and curves
It's already useful to know how many base field operations are necessary.
