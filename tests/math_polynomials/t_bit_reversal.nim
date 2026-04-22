# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Bit-Reversal Permutation Tests
#
# Tests for:
#   - Naive algorithm (simple, cache-unfriendly)
#   - COBRA algorithm (cache-optimized, Carter & Gatlin 1998)
#   - Automatic threshold selection
#   - Involution property (BRP(BRP(x)) = x)
#   - Correctness across threshold boundaries

import
  std/strutils,
  ../../constantine/named/algebras,
  ../../constantine/math/arithmetic,
  ../../constantine/math/polynomials/fft_common {.all.},
  ../../constantine/math/io/io_fields,
  ../../constantine/platforms/bithacks

proc testNaiveOutOfPlace*[T](maxLogN: int) =
  echo "Testing naive out-of-place bit-reversal..."
  
  for logN in 1 .. maxLogN:
    let N = 1 shl logN
    
    var src = newSeq[T](N)
    for i in 0 ..< N:
      src[i] = T(i)
    
    var dst = newSeq[T](N)
    dst.bit_reversal_permutation_naive(src)
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert dst[i] == T(rev_i),
        "Naive out-of-place failed at logN=" & $logN & " index=" & $i & 
        " (expected " & $rev_i & " but got " & $dst[i] & ")"
  
  echo "  ✓ Naive out-of-place PASSED (logN=1.." & $maxLogN & ")"

proc testCobraOutOfPlace*[T](minLogN, maxLogN: int) =
  echo "Testing COBRA out-of-place bit-reversal (logN=" & $minLogN & ".." & $maxLogN & ")..."
  
  for logN in minLogN .. maxLogN:
    let N = 1 shl logN
    
    var src = newSeq[T](N)
    for i in 0 ..< N:
      src[i] = T(i)
    
    var dst = newSeq[T](N)
    dst.bit_reversal_permutation_cobra(src)
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert dst[i] == T(rev_i),
        "COBRA out-of-place failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $dst[i] & ")"
  
  echo "  ✓ COBRA out-of-place PASSED (logN=" & $minLogN & ".." & $maxLogN & ")"

proc testNaiveInPlace*[T](maxLogN: int) =
  echo "Testing naive in-place bit-reversal..."
  
  for logN in 1 .. maxLogN:
    let N = 1 shl logN
    
    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i)
    
    buf.bit_reversal_permutation_naive()
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert buf[i] == T(rev_i),
        "Naive in-place failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $buf[i] & ")"
  
  echo "  ✓ Naive in-place PASSED (logN=1.." & $maxLogN & ")"

proc testCobraInPlace*[T](minLogN, maxLogN: int) =
  echo "Testing COBRA in-place bit-reversal (logN=" & $minLogN & ".." & $maxLogN & ")..."
  
  for logN in minLogN .. maxLogN:
    let N = 1 shl logN
    
    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i)
    
    buf.bit_reversal_permutation_cobra()
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert buf[i] == T(rev_i),
        "COBRA in-place failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $buf[i] & ")"
  
  echo "  ✓ COBRA in-place PASSED (logN=" & $minLogN & ".." & $maxLogN & ")"

proc testAutoOutOfPlace*[T](maxLogN: int) =
  echo "Testing automatic out-of-place bit-reversal (threshold selection)..."
  
  for logN in 1 .. maxLogN:
    let N = 1 shl logN
    
    var src = newSeq[T](N)
    for i in 0 ..< N:
      src[i] = T(i)
    
    var dst = newSeq[T](N)
    bit_reversal_permutation(dst, src)
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert dst[i] == T(rev_i),
        "Auto out-of-place failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $dst[i] & ")"
  
  echo "  ✓ Auto out-of-place PASSED (logN=1.." & $maxLogN & ")"

proc testAutoInPlace*[T](maxLogN: int) =
  echo "Testing automatic in-place bit-reversal (threshold selection)..."
  
  for logN in 1 .. maxLogN:
    let N = 1 shl logN
    
    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i)
    
    buf.bit_reversal_permutation()
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert buf[i] == T(rev_i),
        "Auto in-place failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $buf[i] & ")"
  
  echo "  ✓ Auto in-place PASSED (logN=1.." & $maxLogN & ")"

proc testInvolution*[T](maxLogN: int) =
  echo "Testing involution property (BRP(BRP(x)) = x) for logN=1.." & $maxLogN & "..."
  
  for logN in 1 .. maxLogN:
    let N = 1 shl logN
    
    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i + 1)  # Use i+1 to avoid all zeros
    
    buf.bit_reversal_permutation()
    buf.bit_reversal_permutation()
    
    for i in 0 ..< N:
      doAssert buf[i] == T(i + 1),
        "Involution failed at logN=" & $logN & " index=" & $i &
        " (expected " & $(i+1) & " but got " & $buf[i] & ")"
  
  echo "  ✓ Involution property PASSED (logN=1.." & $maxLogN & ")"

proc testThresholdBoundary*[T]() =
  echo "Testing threshold boundary behavior..."
  
  const Threshold = 7  # bitReversalOutOfPlaceThreshold
  
  # Test just below threshold (should use naive)
  let belowN = 1 shl (Threshold - 1)
  var src_below = newSeq[T](belowN)
  for i in 0 ..< belowN:
    src_below[i] = T(i)
  
  var dst_below = newSeq[T](belowN)
  bit_reversal_permutation(dst_below, src_below)
  
  for i in 0 ..< belowN:
    let rev_i = reverseBits(uint32(i), uint32(Threshold - 1))
    doAssert dst_below[i] == T(rev_i),
      "Below threshold failed at index=" & $i
  
  # Test at threshold (should use COBRA)
  let atN = 1 shl Threshold
  var src_at = newSeq[T](atN)
  for i in 0 ..< atN:
    src_at[i] = T(i)
  
  var dst_at = newSeq[T](atN)
  bit_reversal_permutation(dst_at, src_at)
  
  for i in 0 ..< atN:
    let rev_i = reverseBits(uint32(i), uint32(Threshold))
    doAssert dst_at[i] == T(rev_i),
      "At threshold failed at index=" & $i
  
  # Test just above threshold (should use COBRA)
  let aboveN = 1 shl (Threshold + 1)
  var src_above = newSeq[T](aboveN)
  for i in 0 ..< aboveN:
    src_above[i] = T(i)
  
  var dst_above = newSeq[T](aboveN)
  bit_reversal_permutation(dst_above, src_above)
  
  for i in 0 ..< aboveN:
    let rev_i = reverseBits(uint32(i), uint32(Threshold + 1))
    doAssert dst_above[i] == T(rev_i),
      "Above threshold failed at index=" & $i
  
  echo "  ✓ Threshold boundary tests PASSED"

proc testLargeSizes*[T]() =
  echo "Testing large sizes (logN=12..16)..."
  
  for logN in 12 .. 16:
    let N = 1 shl logN
    
    var src = newSeq[T](N)
    for i in 0 ..< N:
      src[i] = T(i)
    
    var dst = newSeq[T](N)
    bit_reversal_permutation(dst, src)
    
    # Spot check a few indices instead of all (for speed)
    let checkIndices = [0, 1, N-1, N div 2, N div 4, 3*N div 4]
    for i in checkIndices:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert dst[i] == T(rev_i),
        "Large size failed at logN=" & $logN & " index=" & $i &
        " (expected " & $rev_i & " but got " & $dst[i] & ")"
    
    echo "  ✓ logN=" & $logN & " (N=" & $N & ") PASSED (spot check)"

when isMainModule:
  echo "========================================"
  echo "    Bit-Reversal Permutation Tests"
  echo "========================================"
  echo ""
  
  testNaiveOutOfPlace[int64](12)
  echo ""
  
  testCobraOutOfPlace[int64](7, 16)
  echo ""
  
  testNaiveInPlace[int64](12)
  echo ""
  
  testCobraInPlace[int64](7, 14)
  echo ""
  
  testAutoOutOfPlace[int64](16)
  echo ""
  
  testAutoInPlace[int64](16)
  echo ""
  
  testInvolution[int64](14)
  echo ""
  
  testThresholdBoundary[int64]()
  echo ""
  
  testLargeSizes[int64]()
  echo ""
  
  echo ""
  echo "========================================"
  echo "    All bit-reversal tests PASSED ✓"
  echo "========================================"
