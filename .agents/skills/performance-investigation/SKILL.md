---
name: performance-investigation
description: Profile and identify performance bottlenecks in Constantine cryptographic code using metering and benchmarking tools
license: MIT
compatibility: opencode
metadata:
  audience: developers
  language: nim
  domain: cryptography
---

## What I do

Help identify and analyze performance bottlenecks in Constantine cryptographic implementations through:

- **Metering**: Count operations (field mul, add, EC ops, scalar muls) with `-d:CTT_METER` flag
- **Benchmarking**: Measure ops/s, ns/op, CPU cycles with `-d:danger` flag
- **Profiling**: Create small test binaries for detailed analysis with perf or similar tools
- **Comparison**: Compare implementations against reference (e.g., C-kzg-4844)

## When to use me

Use this skill when:

1. **Implementation is slower than expected** (e.g., 50% slower than reference)
2. **Need to identify hotspots** in cryptographic algorithms (FK20, FFT, MSM, pairings)
3. **Optimizing critical paths** in PeerDAS (EIP-7594) or KZG (EIP-4844) code
4. **Validating algorithmic complexity** (e.g., O(n log n) vs O(n²))
5. **Comparing optimization strategies** (fixed-base vs variable-base MSM)

## How to investigate performance

### Step 1: Enable Metering

Add `{.meter.}` pragma to suspect procedures:

```nim
import constantine/platforms/abstractions  # Re-exports metering/tracer

proc hotspotFunction*(...) {.meter.} =
  # This will be tracked when compiled with -d:CTT_METER
```

### Step 2: Create Test Binary

Create a minimal test file in `metering/` or `build/`:

```nim
# metering/m_your_test.nim
import
  constantine/platforms/metering/[reports, tracer],
  # ... your imports

proc main() =
  resetMetering()
  yourFunction()
  reportCli(Metrics, "UseAssembly")

when isMainModule:
  main()
```

### Step 3: Compile with Metering

```bash
nim c -r --hints:off --warnings:off --verbosity:0 \
  -d:danger -d:CTT_METER \
  --outdir:build \
  metering/m_your_test.nim
```

### Step 4: Analyze Output

Metering output shows:
- **# of Calls**: How many times each proc was called
- **Throughput (ops/s)**: Operations per second
- **Time (µs)**: Total and average time per call
- **CPU cycles**: Approximate cycle count (indicative only)

Look for:
- High call counts × high avg time = **primary bottleneck**
- EC operations (scalarMul, multiScalarMul) are typically 100-1000× slower than field ops
- Variable-base MSM vs fixed-base MSM can differ by 5-10×

### Step 5: For Detailed Profiling

Compile a small binary for perf:

```bash
nim c -d:danger --debugger:native \
  --outdir:build \
  metering/m_your_test.nim

# Then use perf, vtune, or similar
perf record -- ./build/m_your_test
perf report
```

## Key Patterns in Constantine

### Metering Infrastructure

- **`constantine/platforms/metering/tracer.nim`**: Defines `{.meter.}` macro
- **`constantine/platforms/metering/reports.nim`**: CLI reporting
- **`constantine/platforms/abstractions.nim`**: Re-exports metering primitives
- **Flag**: `-d:CTT_METER` enables metering (off by default)

### Common Bottlenecks

1. **Scalar Multiplication** (`scalarMul_vartime`)

2. **Multi-Scalar Multiplication** (`multiScalarMul_vartime`)
   - Look for Pippenger vs fixed-base optimization opportunities

3. **FFT Operations** (`fft_nr`, `ec_fft_nr`)

4. **Field Operations** (`prod`, `square`, `inv`)
   - `inv` and `inv_vartime` are much slower than mul (~100×)
   - Batch inversion can help

## Notes

- **Metering overhead**: Metering adds ~10-20% overhead; use for relative comparison, not absolute timing
- **Cycle counts**: CPU cycle measurements are approximate (affected by turbo boost, throttling)
- **Compiler effects**: GCC vs Clang can differ significantly on bigint arithmetic
- **Assembly**: Constantine's compile-time assembler improves performance; check `UseASM_X86_64` flag