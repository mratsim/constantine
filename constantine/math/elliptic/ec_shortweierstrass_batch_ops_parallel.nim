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
    numChunks = (totalIters + maxChunkSize - 1) div maxChunkSize # ceildiv
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

proc sum_reduce_vartime_parallel*[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) {.noInline.} =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  ## Compute is parallelized, if beneficial.
  ## This function cannot be nested in another parallel function
  ##
  ## Side-effects due to thread-local threadpool variable accesses.

  # TODO:
  #   This function is needed in Multi-Scalar Multiplication (MSM)
  #   The main bottleneck (~80% time) of zero-ledge proof systems.
  #   MSM is difficult to scale above 16 cores,
  #   allowing nested parallelism will expose more parallelism opportunities.

  # Chunking constants in ec_shortweierstrass_batch_ops.nim

  const minNumPointsParallel = 1024 # For 256-bit curves that's 1024*(32+32) = 65536 temp mem
  const maxTempMem = 262144 # 2¹⁸ = 262144
  const maxNumPoints = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])

  # 262144 / (2*1024) = 128 bytes allowed per coordinates. Largest curve BW6-761 requires 96 bytes per coordinate. And G2 is on Fp, not Fp2.
  static: doAssert minNumPointsParallel <= maxNumPoints, "The curve " & $r.typeof & " requires large size and needs to be tuned."

  if points.len < minNumPointsParallel:
    r.sum_reduce_vartime(points)
    return

  let chunkDesc = computeBalancedChunks(
    start = 0, stopEx = points.len,
    minNumPointsParallel, maxNumPoints,
    targetNumChunks = tp.numThreads.int)

  let partialResults = allocStackArray(r.typeof(), chunkDesc.numChunks)

  for iter in items(chunkDesc):
    proc sum_reduce_vartime_wrapper(res: ptr, p: ptr, pLen: int) {.nimcall.} =
      # The borrow checker prevents capturing `var` and `openArray`
      # so we capture pointers instead.
      res[].sum_reduce_vartime(p, pLen)

    tp.spawn partialResults[iter.chunkID].addr.sum_reduce_vartime_wrapper(
              points.asUnchecked() +% iter.start,
              iter.stopEx - iter.start)

  tp.syncAll() # TODO: this prevents nesting in another parallel region

  const minNumPointsSerial = 16
  if chunkDesc.numChunks < minNumPointsSerial:
    r.setInf()
    for i in 0 ..< chunkDesc.numChunks:
      r += partialResults[i]
  else:
    let partialResultsAffine = allocStackArray(ECP_ShortW_Aff[F, G], chunkDesc.numChunks)
    partialResultsAffine.batchAffine(partialResults, chunkDesc.numChunks)
    r.sum_reduce_vartime(partialResultsAffine, chunkDesc.numChunks)

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
