# Partitioners

For data parallelism (parallel for loops) there are 2 main scheduling strategies:
- static scheduling, when work is regular (for example adding 2 matrices).
  In that case, splitting the loop
  into same-sized chunk provides perfect speedup, with no synchronization overhead.
  (Assuming threads have the same performance and no parasite load)
- dynamic scheduling, when work is irregular (for example zero-ing buffers of different length).

Partitioners help implementing static scheduling.

Static scheduling
=================

Usually static scheduling is problematic because the threshold below which running in parallel
is both hardware dependent, data layout and function dependent, see https://github.com/zy97140/omp-benchmark-for-pytorch

| CPU Model                          | Sockets | Cores/Socket | Frequency |
|------------------------------------|---------|--------------|-----------|
| Intel(R) Xeon(R) CPU E5-2699 v4    | 2       | 22           | 2.20GHz   |
| Intel(R) Xeon(R) Platinum 8180 CPU | 2       | 28           | 2.50GHz   |
| Intel(R) Core(TM) i7-5960X CPU     | 1       | 8            | 3.00GHz   |

| contiguous op | Xeon(R) Platinum 8180 CPU | Xeon(R) CPU E5-2699 v4 | i7-5960X CPU |
|---------------|---------------------------|------------------------|--------------|
| copy          | 80k                       | 20k                    | 8k           |
| add           | 80k                       | 20k                    | 8k           |
| div           | 50k                       | 10k                    | 2k           |
| exp           | 1k                        | 1k                     | 1k           |
| sin           | 1k                        | 1k                     | 1k           |
| sum           | 1k                        | 1k                     | 1k           |
| prod          | 1k                        | 1k                     | 1k           |

| non-contiguous op | Xeon(R) Platinum 8180 CPU | Xeon(R) CPU E5-2699 v4 | i7-5960X CPU |
|-------------------|---------------------------|------------------------|--------------|
| copy              | 20k                       | 8k                     | 2k           |
| add               | 20k                       | 8k                     | 2k           |
| div               | 10k                       | 8k                     | 1k           |
| exp               | 1k                        | 1k                     | 1k           |
| sin               | 2k                        | 2k                     | 1k           |
| sum               | 1k                        | 1k                     | 1k           |
| prod              | 1k                        | 1k                     | 1k           |


# Static partitioner
====================

```Nim
iterator balancedChunks*(start, stopEx, numChunks: int): tuple[chunkID, start, stopEx: int] =
  ## Balanced chunking algorithm for a range [start, stopEx)
  ## This splits a range into min(stopEx-start, numChunks) balanced regions
  ## and returns a tuple (chunkID, offset, length)

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
    totalIters = stopEx - start
    baseChunkSize = totalIters div numChunks
    cutoff = totalIters mod numChunks

  for chunkID in 0 ..< min(numChunks, totalIters):
    if chunkID < cutoff:
      let offset = start + ((baseChunkSize + 1) * chunkID)
      let chunkSize = baseChunkSize + 1
      yield (chunkID, offset, offset+chunkSize)
    else:
      let offset = start + (baseChunkSize * chunkID) + cutoff
      let chunkSize = baseChunkSize
      yield (chunkID, offset, chunkSize)

when isMainModule:
  for chunk in balancedChunks(start = 0, stopEx = 40, numChunks = 12):
    echo chunk
```

Dynamic scheduling
==================

Dynamic schedulers decide at runtime whether to split a range for processing by multiple threads at runtime.
Unfortunately most (all?) of those in production do not or cannot take into account
the actual functions being called within a `parallel_for` section,
and might split into too fine-grained chunks or into too coarse-grained chunks.
Alternatively they might ask the programmer for a threshold below which not to split.
As the programmer has no way to know if their code will run on a Raspberry Pi or a powerful workstation, that choice cannot be optimal.

Recent advances in research like "Lazy Binary Splitting" and "Lazy Tree Splitting"
allows dynamic scheduling to fully adapt to the system current load and
the parallel section computational needs without programmer input (grain size or minimal split threshold)
by using backpressure.


Why do we need partitioners for cryptographic workload then?
============================================================


Here are 3 basic cryptographic primitives that are non-trivial to parallelize:

1. batch elliptic-curve addition
2. multi-scalar multiplication (MSM)
3. batch signature verification via multi-pairing

On the other hand, merkle tree hashing for example is a primitive where both static or dynamic scheduling should give perfect speedup.

Let's take the example of batch EC addition.
--------------------------------------------

There is a naive way, via doing a parallel EC sum reduction,
for example for 1M points,
using projective coordinates, each sum costs 12M (field multiplication)
At first level we have 500k sums, then 250k sums, then 125k, ...
The number of sums is ~1M, for a total cost of 12e⁶

```
 0 1 2 3 4 5 6 7
  +   +   +   +
    +       +
        +
```

The fast way uses affine sum for an asymptotic cost of 6M, so 2x faster.
but this requires an inversion, a fixed cost of ~131M (256-bit) to ~96M (384-bit)
whatever number of additions we accumulate
That inversion needs to be amortized into at least 20-25 additions.

Let's take a look at multi-pairing
----------------------------------

Multi-pairing is split into 2 phases:
- 1. the Miller-Loop which is embarassing parallel, each thread can compute it on their own.
- 2. reducing the n Miller-Loops into a single 𝔽pₖ point using parallel 𝔽pₖ sum reduction.
- 3. Computing the final exponentiation, a fixed cost whatever the number of Miller Loops we did.
  3alt. Alternatively, computing n final exponentiations, and merging them with a 𝔽pₖ product reduction
        in that case, step 2 is not needed.

Conclusion
----------

Dynamic scheduling for reduction with variable + fixed costs (independent of chunk size) is tricky.
Furthermore the computations are regular, same workload per range and static scheduling seems like a great fit.

The downside is if a core has a parasite workload or on architecture like ARM big.Little or Alder Lake
with performance and power-saving cores.

Alternatively, we can add dynamic scheduling hints about min and max chunk size so that
chunk size is kept within the optimal range whatever the number of idle threads.