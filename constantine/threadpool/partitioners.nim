# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ########################################################### #
#                                                             #
#              Static Partitioning algorithms                 #
#                                                             #
# ########################################################### #

# This file implements static/eager partitioning algorithms.
#
# see docs/partitioners.md
#
# Note:
#   Those algorithms cannot take into account:
#   - Other workloads on the computer
#   - Heterogenous cores (for example Big.Little on ARM or Performance/Efficiency on x86)
#   - Load imbalance (i.e. raytracing a wall vs raytracing a mirror)
#   - CPU performance (see https://github.com/zy97140/omp-benchmark-for-pytorch)

type ChunkDescriptor* = object
  start, numSteps: int
  numChunks*, baseChunkSize, cutoff: int

iterator items*(c: ChunkDescriptor): tuple[chunkID, start, size: int] =
  for chunkID in 0 ..< c.numChunks:
    if chunkID < c.cutoff:
      let offset = c.start + ((c.baseChunkSize + 1) * chunkID)
      let chunkSize = c.baseChunkSize + 1
      yield (chunkID, offset, min(chunkSize, c.numSteps-offset))
    else:
      let offset = c.start + (c.baseChunkSize * chunkID) + c.cutoff
      let chunkSize = c.baseChunkSize
      yield (chunkID, offset, min(chunkSize, c.numSteps-offset))

func ceilDiv_vartime(a, b: auto): auto {.inline.} =
  (a + b - 1) div b

func balancedChunksPrioNumber*(start, stopEx, numChunks: int): ChunkDescriptor {.inline.} =
  ## Balanced chunking algorithm for a range [start, stopEx)
  ## This splits a range into min(stopEx-start, numChunks) balanced regions
  # Rationale
  # The following simple chunking scheme can lead to severe load imbalance
  #
  # let chunk_offset = chunk_size * thread_id
  # let chunk_size   = if thread_id < nb_chunks - 1: chunk_size
  #                    else: omp_size - chunk_offset
  #
  # For example dividing 40 items on 12 threads will lead to
  # a base_chunk_size of 40/12 = 3 so work on the first 11 threads
  # will be 3 * 11 = 33, and the remainder 7 on the last thread.
  #
  # Instead of dividing 40 work items on 12 cores into:
  # 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 7 = 3*11 + 7 = 40
  # the following scheme will divide into
  # 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3 = 4*4 + 3*8 = 40
  #
  # This is compliant with OpenMP spec (page 60)
  # http://www.openmp.org/mp-documents/openmp-4.5.pdf
  # "When no chunk_size is specified, the iteration space is divided into chunks
  # that are approximately equal in size, and at most one chunk is distributed to
  # each thread. The size of the chunks is unspecified in this case."
  # ---> chunks are the same ±1

  let
    numSteps = stopEx - start
    baseChunkSize = numSteps div numChunks
    cutoff = numSteps mod numChunks

  return ChunkDescriptor(
    start: start, numSteps: numSteps,
    numChunks: numChunks, baseChunkSize: baseChunkSize, cutoff: cutoff)

func balancedChunksPrioSize*(start, stopEx, minChunkSize, maxChunkSize, numChunksHint: int): ChunkDescriptor =
  ## Balanced chunking algorithm for a range [start, stopEx)
  ## This ideally splits a range into min(stopEx-start, numChunksHint) balanced regions
  ## unless the chunk size isn't in the range [minChunkSize, maxChunkSize]
  #
  # so many division/modulo. Can we do better?
  let numSteps = stopEx - start
  var numChunks = max(numChunksHint, 1)
  var baseChunkSize = numSteps div numChunks
  var cutoff = numSteps mod numChunks        # Should be computed in a single instruction with baseChunkSize

  if baseChunkSize < minChunkSize:
    numChunks = max(numSteps div minChunkSize, 1)
    baseChunkSize = numSteps div numChunks
    cutoff = numSteps mod numChunks
  elif baseChunkSize > maxChunkSize or (baseChunkSize == maxChunkSize and cutoff != 0):
    # After cutoff, we do baseChunkSize+1, and would run afoul of the maxChunkSize constraint (unless no remainder), hence ceildiv
    numChunks = numSteps.ceilDiv_vartime(maxChunkSize)
    baseChunkSize = numSteps div numChunks
    cutoff = numSteps mod numChunks

  return ChunkDescriptor(
    start: start, numSteps: numSteps,
    numChunks: numChunks, baseChunkSize: baseChunkSize, cutoff: cutoff)

# Sanity checks
# ---------------------------------------

when isMainModule:
  block:
    let chunkDesc = balancedChunksPrioSize(start = 0, stopEx = 40, minChunkSize = 16, maxChunkSize = 128, numChunksHint = 12)
    for chunk in chunkDesc:
      echo chunk

  block:
    let chunkDesc = balancedChunksPrioSize(start = 0, stopEx = 10000, minChunkSize = 16, maxChunkSize = 128, numChunksHint = 12)
    for chunk in chunkDesc:
      echo chunk
