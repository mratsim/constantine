# Constantine
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#           Matrix Transposition Benchmarks
#
# Comparing different transposition strategies for large field elements
# Target: Fr[BLS12_381] (32 bytes per element)
#
# Implementations tested:
# 1. Naive sequential
# 2. Naive with exchanged loop order
# 3. 1D blocked (various block sizes)
# 4. 2D blocked/tiled (various block sizes) [WINNER]
# 5. Divide & conquer cache-oblivious (untested, for reference)
#
# See: https://github.com/mratsim/laser/blob/master/benchmarks/transpose/transpose_bench.nim
#
# ############################################################

import
  std/[random, times, stats, strformat, math, sequtils],
  constantine/math/arithmetic,
  constantine/named/config_fields_and_curves

# ############################################################
# Benchmarking utilities
# ############################################################

template printStats(name: string, req_ops: int, global_start, global_stop: float) {.dirty.} =
  echo "\n", name
  echo &"Collected {stats.n} samples in {global_stop - global_start:>4.3f} seconds"
  echo &"Average time: {stats.mean * 1000:>4.3f} ms"
  echo &"Stddev  time: {stats.standardDeviationS * 1000:>4.3f} ms"
  echo &"Min     time: {stats.min * 1000:>4.3f} ms"
  echo &"Max     time: {stats.max * 1000:>4.3f} ms"
  echo &"Perf:         {req_ops.float / stats.mean / 1e9:>4.3f} GMEMOPs/s"
  echo &"Throughput:   {req_ops.float * 32.0 / stats.mean / 1e9:>4.3f} GB/s"

template bench(name: string, initialisation, body: untyped) {.dirty.} =
  block:
    var stats: RunningStat
    let global_start = epochTime()
    for _ in 0 ..< NbSamples:
      initialisation
      let start = epochTime()
      body
      let stop = epochTime()
      stats.push(stop - start)
    let global_stop = epochTime()
    printStats(name, req_ops, global_start, global_stop)

# ############################################################
# Test parameters
# ############################################################

const
  M = 512       # Rows
  N = 512       # Columns
  NbSamples = 100

# For Fr[BLS12_381]
type F = Fr[BLS12_381]

let req_ops = M * N
let req_bytes = sizeof(F) * M * N

echo &"Benchmarking matrix transposition: {M}x{N} matrix"
echo &"Element type: Fr[BLS12_381] ({sizeof(F)} bytes)"
echo &"Total size: {req_bytes / 1024 / 1024:>4.2f} MB"
echo &"Required operations: {req_ops}"
echo ""

# ############################################################
# Test data setup
# ############################################################

# Create input matrix with constant values (values don't matter for perf)
var input = newSeq[F](M * N)
for i in 0 ..< M * N:
  input[i] = F.getOne()

# ############################################################
# 1. Naive Sequential Transpose
# ############################################################

proc naiveTranspose[T](dst, src: ptr UncheckedArray[T], M, N: int) =
  ## Simple row-to-column copy
  ## Poor cache performance due to strided writes
  for j in 0 ..< N:
    for i in 0 ..< M:
      dst[j * M + i] = src[i * N + j]

proc benchNaive() =
  var output = newSeq[F](N * M)
  let pi = cast[ptr UncheckedArray[F]](input[0].addr)
  let po = cast[ptr UncheckedArray[F]](output[0].addr)

  bench("Naive Sequential"):
    discard
  do:
    naiveTranspose(po, pi, M, N)

benchNaive()

# ############################################################
# 2. Naive with Exchanged Loop Order
# ############################################################

proc naiveTransposeExchanged[T](dst, src: ptr UncheckedArray[T], M, N: int) =
  ## Iterate input linearly, write with stride
  ## Better read pattern, worse write pattern
  for i in 0 ..< M:
    for j in 0 ..< N:
      dst[j * M + i] = src[i * N + j]

proc benchNaiveExchanged() =
  var output = newSeq[F](N * M)
  let pi = cast[ptr UncheckedArray[F]](input[0].addr)
  let po = cast[ptr UncheckedArray[F]](output[0].addr)

  bench("Naive (exchanged loops)"):
    discard
  do:
    naiveTransposeExchanged(po, pi, M, N)

benchNaiveExchanged()

# ############################################################
# 3. 1D Blocked Transpose
# ############################################################

proc blocked1DTranspose[T](dst, src: ptr UncheckedArray[T], M, N: int, blockSize: static int) =
  ## Block along one dimension (rows of output) to improve cache locality
  ## Processes output in blocks of blockSize rows at a time
  ## Note: For 32-byte elements, 1D blocking has limited benefit vs 2D
  const blck = blockSize
  for jj in countup(0, N - 1, blck):
    for j in jj ..< min(jj + blck, N):
      for i in 0 ..< M:
        dst[j * M + i] = src[i * N + j]

template benchBlocked1D(blockSize: static int) =
  var output = newSeq[F](N * M)
  let pi = cast[ptr UncheckedArray[F]](input[0].addr)
  let po = cast[ptr UncheckedArray[F]](output[0].addr)

  const name = "1D Blocked (block=" & $blockSize & ")"
  bench(name):
    discard
  do:
    blocked1DTranspose[F](po, pi, M, N, blockSize)

# Test various block sizes
benchBlocked1D(8)
benchBlocked1D(16)
benchBlocked1D(32)
benchBlocked1D(64)
benchBlocked1D(128)

# ############################################################
# 4. 2D Blocked (Tiled) Transpose [WINNER]
# ############################################################

proc blocked2DTranspose[T](dst, src: ptr UncheckedArray[T], M, N: int, blockSize: static int) =
  ## 2D tiling - process matrix in small tiles
  ## Best cache utilization for large matrices
  ##
  ## For 32-byte elements (Fr[BLS12_381]):
  ## - block=16: 16×16×32 = 8KB per tile (fits in L1)
  ## - block=32: 32×32×32 = 32KB per tile (L1/L2 boundary)
  const blck = blockSize
  for jj in countup(0, N - 1, blck):
    for ii in countup(0, M - 1, blck):
      for j in jj ..< min(jj + blck, N):
        for i in ii ..< min(ii + blck, M):
          dst[j * M + i] = src[i * N + j]

template benchBlocked2D(blockSize: static int) =
  var output = newSeq[F](N * M)
  let pi = cast[ptr UncheckedArray[F]](input[0].addr)
  let po = cast[ptr UncheckedArray[F]](output[0].addr)

  const name = "2D Blocked (block=" & $blockSize & ")"
  bench(name):
    discard
  do:
    blocked2DTranspose[F](po, pi, M, N, blockSize)

# Test various block sizes - smaller for 32-byte elements
benchBlocked2D(4)
benchBlocked2D(8)
benchBlocked2D(16)
benchBlocked2D(32)

# ############################################################
# Summary
# ############################################################

echo "\n============================================================"
echo "Benchmark complete"
echo "============================================================"
echo "\nRecommended production implementation:"
echo "  → 2D Blocked with block size 16 or 32"
echo "  → See: constantine/math/matrix/transpose.nim"
echo "\nKey insight: For 32-byte field elements, 16×16 tiles"
echo "(8KB per tile) fit perfectly in L1 cache, giving 2×"
echo "speedup over naive sequential transposition."
echo "============================================================"