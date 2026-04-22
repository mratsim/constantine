# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        Benchmark of Bit-Reversal Permutation Algorithms
#
# ############################################################
# Compares:
#   - Naive algorithm (simple, cache-unfriendly)
#   - COBRA algorithm (cache-optimized, Carter & Gatlin 1998)
#   - Out-of-place + copy (in-place via temporary buffer)
#   - Automatic threshold selection
#
# Tests both in-place and out-of-place variants
# ############################################################

import
  std/[times, monotimes, strformat],
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/polynomials/fft {.all.},
  constantine/math/io/io_fields,
  constantine/platforms/bithacks,
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator() = separator(145)

proc report*(op, typ: string, size: int, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    let cycles = (stopClk - startClk) div iters
    echo &"{op:<32} size {size:>7}    {typ:<15} {throughput:>15.3f} ops/s  {ns:>12} ns/op  {cycles:>12} CPU cycles"
  else:
    echo &"{op:<32} size {size:>7}    {typ:<15} {throughput:>15.3f} ops/s  {ns:>12} ns/op"

template bench*(op, typ: string, size, iters: int, body: untyped): untyped =
  block:
    measure(iters, startTime, stopTime, startClk, stopClk, body)
    report(op, typ, size, startTime, stopTime, startClk, stopClk, iters)

func bitReversalInPlaceViaCopy[T](buf: var openArray[T]) =
  ## In-place bit-reversal via out-of-place + copy.
  ## This is often faster than true in-place algorithms because:
  ## 1. Out-of-place has better cache locality
  ## 2. No swap overhead
  ## 3. Copy is a simple linear scan
  var temp = newSeq[T](buf.len)
  bit_reversal_permutation(temp, buf)
  for i in 0 ..< buf.len:
    buf[i] = temp[i]

proc bench_BitReversal*(T: typedesc) =
  const name = $T
  echo "\n=== Bit-Reversal Permutation Benchmark (" & name & ") ==="
  separator()
  echo "Comparing naive, COBRA, out-of-place+copy, and auto-dispatch algorithms"
  echo "Threshold: out-of-place = 2^7 = 128 elements"
  echo ""

  const
    NumIters = 3
    MaxLogN = 26

  var rng: RngState
  rng.seed 1234

  let maxN = 1 shl MaxLogN
  var src = newSeq[T](maxN)
  rng.random_unsafe(src)

  echo "=== In-Place Variants ==="
  separator()

  for logN in countup(2, MaxLogN-1, 4):
    let N = 1 shl logN
    var buf = src[0..<N]

    bench("Naive (in-place)", name, N, NumIters):
      buf.bit_reversal_permutation_naive()

    bench("COBRA (in-place)", name, N, NumIters):
      buf.bit_reversal_permutation_cobra()

    bench("OOP+Copy (in-place)", name, N, NumIters):
      buf.bitReversalInPlaceViaCopy()

    bench("Auto-dispatch", name, N, NumIters):
      buf.bit_reversal_permutation()

    echo "----"

  echo "\n=== Out-of-Place Variants ==="
  separator()

  for logN in countup(2, MaxLogN-1, 4):
    let N = 1 shl logN
    var dst = newSeq[T](N)

    bench("Naive (out-of-place)", name, N, NumIters):
      bit_reversal_permutation_naive(dst, src.toOpenArray(0, N-1))

    bench("COBRA (out-of-place)", name, N, NumIters):
      bit_reversal_permutation_cobra(dst, src.toOpenArray(0, N-1))

    bench("Auto-dispatch", name, N, NumIters):
      bit_reversal_permutation(dst, src.toOpenArray(0, N-1))

    echo "----"

  echo "\n=== Summary ==="
  echo &"Threshold (out-of-place): 2^7 = 128 elements"
  echo &"Threshold (in-place):     2^18 = 262,144 elements"
  echo ""
  echo "Note: Out-of-place is at least 2x faster than true in-place"
  echo "      due to better cache locality and no swap overhead."
  echo "      The 'OOP+Copy' variant is often the best in-place option."

when isMainModule:
  echo "============================================================"
  echo "        Bit-Reversal Permutation Benchmarks"
  echo "============================================================"
  echo ""

  warmup()

  echo "Testing with uint32 (4 bytes per element):"
  bench_BitReversal(uint32)

  echo "\n\nTesting with Fr[BLS12_381] (32 bytes per element):"
  bench_BitReversal(Fr[BLS12_381])

  echo ""
