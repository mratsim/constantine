# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#              Bit-Reversal Permutations for FFT
#
# ############################################################
# - Towards an Optimal Bit-Reversal Permutation Program
#   Larry Carter and Kang Su Gatlin, 1998
#   https://csaws.cs.technion.ac.il/~itai/Courses/Cache/bit.pdf
#
# - Practically efficient methods for performing bit-reversed
#   permutation in C++11 on the x86-64 architecture
#   Knauth, Adas, Whitfield, Wang, Ickler, Conrad, Serang, 2017
#   https://arxiv.org/pdf/1708.01873.pdf

import
  constantine/math/arithmetic,
  constantine/platforms/[allocs, primitives]

# No exceptions allowed
{.push raises: [].}

# Error model
# ------------------------------------------------------------------------------

type
  FFTStatus* = enum
    FFT_Success
    FFT_InconsistentInputOutputLengths = "Output length must match input length"
    FFT_TooManyValues = "Input length greater than the field 2-adicity (number of roots of unity)"
    FFT_SizeNotPowerOfTwo = "Input must be of a power of 2 length"

template checkSizesReturnEarly*(desc, output, vals: untyped): untyped =
  ## Validate FFT input sizes and return early with appropriate FFTStatus on failure.
  ## Use this at the start of FFT functions to validate inputs before allocation or computation.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

# Bit-reversal permutation
# ------------------------------------------------------------------------------

func optimalLogTileSize(T: type): uint {.inline.} =
  ## Returns the optimal log of the tile size
  ## depending on the type and common L1 cache size
  # `lscpu` can return desired cache values.
  # We underestimate modern cache sizes so that performance is good even on older architectures.

  # 1. Derive ideal size depending on the type
  const cacheLine = 64'u     # Size of a cache line
  const l1Size = 32'u * 1024 # Size of L1 cache
  const elems_per_cacheline = max(1'u, cacheLine div T.sizeof().uint)

  var q = l1Size div T.sizeof().uint
  q = q div 2 # use only half of the cache, this limits cache eviction, especially with hyperthreading.
  q = q.nextPowerOfTwo_vartime().log2_vartime()
  q = q div 2 # 2²𐞥 should be smaller than the cache

  # If the cache line can accommodate spare elements
  # increment the tile size
  while 1'u shl q < elems_per_cacheline:
    q += 1

  return q

func deriveLogTileSize(T: type, logN: uint): uint {.inline.} =
  ## Returns the log of the tile size

  # 1. Compute the optimal tile size
  var q = optimalLogTileSize(T)

  # 2. We want to ensure logN - 2*q > 0
  while int(logN) - int(q+q) < 0:
    q -= 1

  return q

const bitReversalOutOfPlaceThreshold* = 7
  ## Threshold (as log2) above which the COBRA algorithm is used for out-of-place.
  ## Below this threshold, the naive algorithm is faster on modern CPUs.

func bit_reversal_permutation_naive[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) =
  ## Out-of-place bit reversal permutation using a naive algorithm.
  ##
  ## For each index i, places src[i] into dst[reverseBits(i)].
  ##
  ## **IMPORTANT**: `dst` and `src` must NOT alias (be the same array).
  ## Use the in-place overload if you need to permute in-place.

  debug: doAssert src.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len

  let logN = log2_vartime(uint src.len)
  for i in 0'u ..< src.len.uint:
    dst[int reverseBits(i, logN)] = src[i]

func bit_reversal_permutation_naive[T](buf: var openArray[T]) {.used.} =
  ## In-place bit reversal permutation using a naive algorithm.
  ##
  ## This uses a swap-based approach where we traverse the array and
  ## swap elements to their bit-reversed positions.
  ## Only used for benchmarking.
  ##   Whether for uint32 (4 bytes) to Fr[BLS12_381]
  ##   the in-place algorithm is at least 2x slower than out-of-place
  ##   AND tuning the naive vs cobra threshold is trickier
  ##   and might severely depend on the memory bandwidth
  ##   and be very different between Apple CPUs and Intel/AMD
  debug: doAssert buf.len.uint.isPowerOf2_vartime()

  let logN = log2_vartime(uint buf.len)
  for i in 0'u ..< buf.len.uint:
    let rev_i = reverseBits(i, logN)
    if i < rev_i:
      swap(buf[i], buf[rev_i])

func bit_reversal_permutation_cobra[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) =
  ## Out-of-place bit reversal permutation using the COBRA algorithm
  ## (Cache Optimal BitReverse Algorithm from Carter & Gatlin, 1998)
  ##
  ## This implements the "square strategy" which is cache-efficient and
  ## nearly optimal. It uses a temporary buffer that fits in L1 cache.
  ##
  ## Algorithm:
  ##   for b = 0 to 2^(lgN-2q) - 1
  ##     b' = r(b)
  ##     for a = 0 to 2^q - 1
  ##       a' = r(a)
  ##       for c = 0 to 2^q - 1
  ##         T[a'c] = A[abc]
  ##     for c = 0 to 2^q - 1
  ##       c' = r(c)
  ##       for a' = 0 to 2^q - 1
  ##         B[c'b'a'] = T[a'c]
  ##
  ## Parameters:
  ##   - dst: destination array (must have same length as src)
  ##   - src: source array in natural order
  ##
  ## The destination will contain the bit-reversed permutation of src.
  ##
  ## **IMPORTANT**: `dst` and `src` must NOT alias (be the same array).
  ## Use the in-place overload if you need to permute in-place.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  debug: doAssert src.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len

  let logN = log2_vartime(uint src.len)
  let logTileSize = deriveLogTileSize(T, logN)
  let logBLen = logN - 2*logTileSize
  let bLen = 1'u shl logBLen
  let tileSize = 1'u shl logTileSize

  let t = allocHeapArray(T, tileSize*tileSize)

  for b in 0'u ..< bLen:
    let bRev = reverseBits(b, logBLen)

    for a in 0'u ..< tileSize:
      let aRev = reverseBits(a, logTileSize)
      for c in 0'u ..< tileSize:
        # T[a'c] = A[abc]
        let tIdx = (aRev shl logTileSize) or c
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        t[tIdx] = src[idx]

    for c in 0'u ..< tileSize:
      let cRev = reverseBits(c, logTileSize)
      for aRev in 0'u ..< tileSize:
        let idx = (cRev shl (logBLen+logTileSize)) or
                  (bRev shl logTileSize) or aRev
        let tIdx = (aRev shl logTileSize) or c
        dst[idx] = t[tIdx]

  freeHeap(t)

func bit_reversal_permutation_cobra[T](buf: var openArray[T]) {.used.} =
  ## In-place bit reversal permutation using the COBRA algorithm.
  ## Only used for benchmarking.
  ##   Whether for uint32 (4 bytes) to Fr[BLS12_381]
  ##   the in-place algorithm is at least 2x slower than out-of-place
  ##   AND tuning the naive vs cobra threshold is trickier
  ##   and might severely depend on the memory bandwidth
  ##   and be very different between Apple CPUs and Intel/AMD
  #
  # We adapt the following out-of-place algorithm to in-place.
  #
  # for b = 0 to 2ˆ(lgN-2q) - 1
  #   b' = r(b)
  #   for a = 0 to 2ˆq - 1
  #     a' = r(a)
  #     for c = 0 to 2ˆq - 1
  #       T[a'c] = A[abc]
  #
  #   for c = 0 to 2ˆq - 1
  #     c' = r(c)                <- Note: typo in paper, they say c'=r(a)
  #     for a' = 0 to 2ˆq - 1
  #       B[c'b'a'] = T[a'c]
  #
  # As we are in-place, A and B refer to the same buffer and
  # we don't want to destructively write to B.
  # Instead we swap B and T to save the overwritten slot.
  #
  # Due to bitreversal being an involution, we can redo the first loop
  # to place the overwritten data in its correct slot.
  #
  # Hence
  #
  # for b = 0 to 2ˆ(lgN-2q) - 1
  #   b' = r(b)
  #   for a = 0 to 2ˆq - 1
  #     a' = r(a)
  #     for c = 0 to 2ˆq - 1
  #       T[a'c] = A[abc]
  #
  #   for c = 0 to 2ˆq - 1
  #     c' = r(c)
  #     for a' = 0 to 2ˆq - 1
  #       if abc < c'b'a'
  #         swap(A[c'b'a'], T[a'c])
  #
  #   for a = 0 to 2ˆq - 1
  #     a' = r(a)
  #     for c = 0 to 2ˆq - 1
  #       c' = r(c)
  #       if abc < c'b'a'
  #         swap(A[abc], T[a'c])

  debug: doAssert buf.len.uint.isPowerOf2_vartime()

  let logN = log2_vartime(uint buf.len)
  let logTileSize = deriveLogTileSize(T, logN)
  let logBLen = logN - 2*logTileSize
  let bLen = 1'u shl logBLen
  let tileSize = 1'u shl logTileSize

  let t = allocHeapArray(T, tileSize*tileSize)

  for b in 0'u ..< bLen:
    let bRev = reverseBits(b, logBLen)

    for a in 0'u ..< tileSize:
      let aRev = reverseBits(a, logTileSize)
      for c in 0'u ..< tileSize:
        # T[a'c] = A[abc]
        let tIdx = (aRev shl logTileSize) or c
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        t[tIdx] = buf[idx]

    for c in 0'u ..< tileSize:
      let cRev = reverseBits(c, logTileSize)
      for aRev in 0'u ..< tileSize:
        let a = reverseBits(aRev, logTileSize)
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        let idxRev = (cRev shl (logBLen+logTileSize)) or
                     (bRev shl logTileSize) or aRev
        if idx < idxRev:
          let tIdx = (aRev shl logTileSize) or c
          swap(buf[idxRev], t[tIdx])

    for a in 0'u ..< tileSize:
      let aRev = reverseBits(a, logTileSize)
      for c in 0'u ..< tileSize:
        let cRev = reverseBits(c, logTileSize)
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        let idxRev = (cRev shl (logBLen+logTileSize)) or
                     (bRev shl logTileSize) or aRev
        if idx < idxRev:
          let tIdx = (aRev shl logTileSize) or c
          swap(buf[idx], t[tIdx])

  freeHeap(t)

func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
  ## Out-of-place bit reversal permutation (no aliasing between dst and src).
  ##
  ## Automatically selects between naive and COBRA algorithms based on size.
  ## For small sizes (< 2^7 elements), the naive algorithm is faster.
  ## For larger sizes, the COBRA cache-optimized algorithm is used.
  debug: doAssert src.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len

  let logN = log2_vartime(uint src.len)
  if logN >= bitReversalOutOfPlaceThreshold:
    # Use out-of-place COBRA for large sizes
    bit_reversal_permutation_cobra(dst, src)
  else:
    # Use naive algorithm for small sizes
    bit_reversal_permutation_naive(dst, src)

func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) =
  ## Out-of-place bit reversal permutation with aliasing detection.
  ##
  ## If dst and src are the same array (aliasing), a temporary buffer is allocated.
  debug: doAssert dst.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len
  debug: doAssert dst.len > 0

  if dst[0].addr == src[0].addr:
    # Alias: allocate temp, permute to temp, copy back
    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
    freeHeapAligned(tmp)
  else:
    bit_reversal_permutation_noalias(dst, src)

func bit_reversal_permutation*[T](buf: var openArray[T]) =
  ## In-place bit reversal permutation.
  ##
  ## Out-of-place is at least 2x faster than in-place so dispatch to out-of-place
  debug: doAssert buf.len.uint.isPowerOf2_vartime()
  debug: doAssert buf.len > 0
  var tmp = allocHeapArrayAligned(T, buf.len, alignment = 64)
  bit_reversal_permutation_noalias(tmp.toOpenArray(0, buf.len-1), buf)
  copyMem(buf[0].addr, tmp[0].addr, buf.len * sizeof(buf[0]))
  freeHeapAligned(tmp)