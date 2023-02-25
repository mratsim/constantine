# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../../platforms/threadpool/threadpool,
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_jacobian,
  ./ec_shortweierstrass_projective,
  ./ec_shortweierstrass_batch_ops

# No exceptions allowed
{.push raises:[], checks: off.}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                    Parallel Batch addition
#
# ############################################################

type ChunkDescriptor = object
  start, totalIters: int
  numChunks, baseChunkSize, cutoff: int

func computeBalancedChunks(start, stopEx, minChunkSize, maxChunkSize, targetNumChunks: int): ChunkDescriptor =
  ## Balanced chunking algorithm for a range [start, stopEx)
  ## This ideally splits a range into min(stopEx-start, targetNumChunks) balanced regions
  ## unless the chunk size isn't in the range [minChunkSize, maxChunkSize]
  #
  # see constantine/platforms/threadpool/docs/partitioner.md
  let totalIters = stopEx - start
  var numChunks = max(targetNumChunks, 1)
  var baseChunkSize = totalIters div numChunks
  var cutoff = totalIters mod numChunks        # Should be computed in a single instruction with baseChunkSize

  if baseChunkSize < minChunkSize:
    numChunks = max(totalIters div minChunkSize, 1)
    baseChunkSize = totalIters div numChunks
    cutoff = totalIters mod numChunks
  elif baseChunkSize > maxChunkSize or (baseChunkSize == maxChunkSize and cutoff != 0):
    # After cutoff, we do baseChunkSize+1, and would run afoul of the maxChunkSize constraint (unless no remainder), hence ceildiv
    numChunks = totalIters.ceilDiv_vartime(maxChunkSize)
    baseChunkSize = totalIters div numChunks
    cutoff = totalIters mod numChunks

  return ChunkDescriptor(
    start: start, totaliters: totalIters,
    numChunks: numChunks, baseChunkSize: baseChunkSize, cutoff: cutoff
  )

iterator items(c: ChunkDescriptor): tuple[chunkID, start, stopEx: int] =
  for chunkID in 0 ..< min(c.numChunks, c.totalIters):
    if chunkID < c.cutoff:
      let offset = c.start + ((c.baseChunkSize + 1) * chunkID)
      let chunkSize = c.baseChunkSize + 1
      yield (chunkID, offset, min(offset+chunkSize, c.totalIters))
    else:
      let offset = c.start + (c.baseChunkSize * chunkID) + c.cutoff
      let chunkSize = c.baseChunkSize
      yield (chunkID, offset, min(offset+chunkSize, c.totalIters))

proc sum_reduce_vartime_parallelChunks[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) {.noInline.} =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  ## Compute is parallelized, if beneficial.
  ## This function cannot be nested in another parallel function

  # Chunking constants in ec_shortweierstrass_batch_ops.nim
  const maxTempMem = 262144 # 2¹⁸ = 262144
  const maxChunkSize = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])
  const minChunkSize = (maxChunkSize * 60) div 100

  if points.len <= maxChunkSize:
    r.setInf()
    r.accumSum_chunk_vartime(points.asUnchecked(), points.len)
    return

  let chunkDesc = computeBalancedChunks(
    start = 0, stopEx = points.len,
    maxChunkSize, maxChunkSize, # We want 66%~100% full chunks
    targetNumChunks = tp.numThreads.int)

  let partialResults = allocStackArray(r.typeof(), chunkDesc.numChunks)

  for iter in items(chunkDesc):
    proc sum_reduce_chunk_vartime_wrapper(res: ptr, p: ptr, pLen: int) {.nimcall.} =
      # The borrow checker prevents capturing `var` and `openArray`
      # so we capture pointers instead.
      res[].setInf()
      res[].accumSum_chunk_vartime(p, pLen)

    tp.spawn partialResults[iter.chunkID].addr.sum_reduce_chunk_vartime_wrapper(
              points.asUnchecked() +% iter.start,
              iter.stopEx - iter.start)

  tp.syncAll() # TODO: this prevents nesting in another parallel region

  const minChunkSizeSerial = 32
  if chunkDesc.numChunks < minChunkSizeSerial:
    r.setInf()
    for i in 0 ..< chunkDesc.numChunks:
      r += partialResults[i]
  else:
    let partialResultsAffine = allocStackArray(ECP_ShortW_Aff[F, G], chunkDesc.numChunks)
    partialResultsAffine.batchAffine(partialResults, chunkDesc.numChunks)
    r.sum_reduce_vartime(partialResultsAffine, chunkDesc.numChunks)

proc sum_reduce_vartime_parallelFor[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  ## Compute is parallelized, if beneficial.

  mixin globalSum

  const maxTempMem = 262144 # 2¹⁸ = 262144
  const maxStride = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])

  let p = points.asUnchecked
  let pointsLen = points.len

  tp.parallelFor i in 0 ..< points.len:
    stride: maxStride
    captures: {p, pointsLen}
    reduceInto(globalSum: typeof(r)):
      prologue:
        var localSum {.noInit.}: typeof(r)
        localSum.setInf()
      forLoop:
        let n = min(maxStride, pointsLen-i)
        localSum.accumSum_chunk_vartime(p +% i, n)
      merge(remoteSum: Flowvar[typeof(r)]):
        localSum += sync(remoteSum)
      epilogue:
        return localSum

  r = sync(globalSum)

proc sum_reduce_vartime_parallel*[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) {.inline.} =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  ## Compute is parallelized, if beneficial.
  ## This function cannot be nested in another parallel function
  when false:
    tp.sum_reduce_vartime_parallelFor(r, points)
  else:
    tp.sum_reduce_vartime_parallelChunks(r, points)

# Sanity checks
# ---------------------------------------

when isMainModule:
  block:
    let chunkDesc = computeBalancedChunks(start = 0, stopEx = 40, minChunkSize = 16, maxChunkSize = 128, targetNumChunks = 12)
    for chunk in chunkDesc:
      echo chunk

  block:
    let chunkDesc = computeBalancedChunks(start = 0, stopEx = 10000, minChunkSize = 16, maxChunkSize = 128, targetNumChunks = 12)
    for chunk in chunkDesc:
      echo chunk
