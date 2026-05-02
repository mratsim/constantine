# Constantine
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#              Optimized Matrix Transposition
#
# Optimized for large field elements (e.g., Fr[BLS12_381] - 32 bytes)
#
# Benchmark results (512x512 matrix, 32-byte elements):
# - 2D Blocked (block=16):   20.4 GB/s  [WINNER]
# - 2D Blocked (block=32):   20.1 GB/s
# - 2D Blocked (block=8):    19.8 GB/s
# - Naive sequential:        10.1 GB/s
#
# See benchmarks/bench_matrix_transpose.nim for full comparison
#
# ############################################################

import
  std/[math],
  ../../platforms/views

export views

# ############################################################
#
#         2D Blocked (Tiled) Transposition
#
# ############################################################

proc transpose*[T](dst, src: ptr UncheckedArray[T], M, N: int, blockSize: static int = 16) {.inline.} =
  ## 2D tiled transposition for optimal cache utilization
  ##
  ## Processes matrix in blockSize x blockSize tiles.
  ## Optimal block size depends on element size:
  ## - 32-byte elements (Fr[BLS12_381]): block=16 or 32
  ## - 8-byte elements (float64): block=32 or 64
  ## - 4-byte elements (float32): block=64
  ##
  ## Performance: ~20 GB/s for 32-byte elements (2x naive)
  ##
  ## Parameters:
  ## - dst: output buffer (N x M elements)
  ## - src: input buffer (M x N elements)
  ## - M: number of rows in source matrix
  ## - N: number of columns in source matrix
  ## - blockSize: tile size (default 16, optimized for 32-byte elements)
  const blck = blockSize
  for jj in countup(0, N - 1, blck):
    for ii in countup(0, M - 1, blck):
      for j in jj ..< min(jj + blck, N):
        for i in ii ..< min(ii + blck, M):
          dst[j * M + i] = src[i * N + j]

# ############################################################
#
#              openArray-based convenience wrappers
#
# ############################################################

proc transpose*[T](dst: var openArray[T], src: openArray[T], M, N: int, blockSize: static int = 16) {.inline.} =
  ## Transpose M x N matrix from src to dst
  ##
  ## Both dst and src must be pre-allocated:
  ## - src: M * N elements
  ## - dst: N * M elements
  ##
  ## No heap allocations - uses ptr UncheckedArray internally
  doAssert dst.len >= N * M, "dst too small"
  doAssert src.len >= M * N, "src too small"
  
  let srcPtr = cast[ptr UncheckedArray[T]](unsafeAddr(src[0]))
  let dstPtr = cast[ptr UncheckedArray[T]](unsafeAddr(dst[0]))
  dstPtr.transpose(srcPtr, M, N, blockSize)