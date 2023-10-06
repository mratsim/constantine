# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../../threadpool/[threadpool, partitioners],
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
  ## Scales better for large number of points

  # Chunking constants in ec_shortweierstrass_batch_ops.nim
  const maxTempMem = 262144 # 2¹⁸ = 262144
  const maxChunkSize = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])
  const minChunkSize = (maxChunkSize * 60) div 100 # We want 60%~100% full chunks

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
      r.sum_vartime(r, partialResults[i])
  else:
    let partialResultsAffine = allocStackArray(ECP_ShortW_Aff[F, G], chunkDesc.numChunks)
    partialResultsAffine.batchAffine(partialResults, chunkDesc.numChunks)
    r.sum_reduce_vartime(partialResultsAffine, chunkDesc.numChunks)

proc sum_reduce_vartime_parallelAccums[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  ## 2x faster for low number of points

  const maxTempMem = 1 shl 18 # 2¹⁸ = 262144
  const maxChunkSize = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])
  type Acc = EcAddAccumulator_vartime[typeof(r), F, G, maxChunkSize]

  let ps = points.asUnchecked()
  let N = points.len

  mixin globalAcc

  const chunkSize = 32

  tp.parallelFor i in 0 ..< N:
    stride: chunkSize
    captures: {ps, N}
    reduceInto(globalAcc: ptr Acc):
      prologue:
        var workerAcc = allocHeap(Acc)
        workerAcc[].init()
      forLoop:
        for j in i ..< min(i+chunkSize, N):
          workerAcc[].update(ps[j])
      merge(remoteAccFut: Flowvar[ptr Acc]):
        let remoteAcc = sync(remoteAccFut)
        workerAcc[].merge(remoteAcc[])
        freeHeap(remoteAcc)
      epilogue:
        workerAcc[].handover()
        return workerAcc

  let ctx = sync(globalAcc)
  ctx[].finish(r)
  freeHeap(ctx)

proc sum_reduce_vartime_parallel*[F; G: static Subgroup](
       tp: Threadpool,
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) {.inline.} =
  ## Parallel Batch addition of `points` into `r`
  ## `r` is overwritten

  if points.len < 256:
    r.setInf()
    r.accumSum_chunk_vartime(points.asUnchecked(), points.len)
  elif points.len < 8192:
    tp.sum_reduce_vartime_parallelAccums(r, points)
  else:
    tp.sum_reduce_vartime_parallelChunks(r, points)
