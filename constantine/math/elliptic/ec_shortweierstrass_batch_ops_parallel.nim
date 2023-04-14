# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../../platforms/threadpool/[threadpool, partitioners],
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

proc sum_reduce_vartime_parallelChunks[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) {.noInline.} =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  ## Compute is parallelized, if beneficial.
  ## This function can be nested in another parallel function

  # Chunking constants in ec_shortweierstrass_batch_ops.nim
  const maxTempMem = 262144 # 2¹⁸ = 262144
  const maxChunkSize = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])
  const minChunkSize = (maxChunkSize * 60) div 100 # We want 60%~100% full chunks

  if points.len <= maxChunkSize:
    r.setInf()
    r.accumSum_chunk_vartime(points.asUnchecked(), points.len)
    return

  let chunkDesc = balancedChunksPrioSize(
    start = 0, stopEx = points.len,
    minChunkSize, maxChunkSize,
    numChunksHint = tp.numThreads.int)

  let partialResults = allocStackArray(r.typeof(), chunkDesc.numChunks)

  syncScope:
    for iter in items(chunkDesc):
      proc sum_reduce_chunk_vartime_wrapper(res: ptr, p: ptr, pLen: int) {.nimcall.} =
        # The borrow checker prevents capturing `var` and `openArray`
        # so we capture pointers instead.
        res[].setInf()
        res[].accumSum_chunk_vartime(p, pLen)

      tp.spawn partialResults[iter.chunkID].addr.sum_reduce_chunk_vartime_wrapper(
                points.asUnchecked() +% iter.start,
                iter.size)

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
