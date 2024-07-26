# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Stdlib
  system/ansi_c, std/[os, strutils, cpuinfo, math, strformat, locks],
  # Constantine
  constantine/threadpool

when not defined(windows):
  # bench
  import ../wtime, ../resources

# TODO: there is an overflow on Linux32 or MacOS for MaxRSS but not Linux or Windows
# This test is quite important to ensure parallel reductions work within a generic proc.
{.push checks: off.}

# Helpers
# -------------------------------------------------------

# We need a thin wrapper around raw pointers for matrices,
# we can't pass "var" to other threads
type
  Matrix[T: SomeFloat] = object
    buffer: ptr UncheckedArray[T]
    ld: int

template `[]`[T](mat: Matrix[T], row, col: Natural): T =
  # row-major storage
  assert row < mat.ld
  assert col < mat.ld
  mat.buffer[row * mat.ld + col]

template `[]=`[T](mat: Matrix[T], row, col: Natural, value: T) =
  assert row < mat.ld
  assert col < mat.ld
  mat.buffer[row * mat.ld + col] = value

type
  Histogram = object
    buffer: ptr UncheckedArray[int64]
    len: int

template `[]`(hist: Histogram, idx: Natural): int64 =
  # row-major storage
  assert idx in 0 ..< hist.len
  hist.buffer[idx]

template `[]=`(hist: Histogram, idx: Natural, value: int64) =
  assert idx in 0 ..< hist.len
  hist.buffer[idx] = value

proc wv_alloc*(T: typedesc): ptr T {.inline.}=
  cast[ptr T](c_malloc(csize_t sizeof(T)))

proc wv_alloc*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T] {.inline.} =
  cast[type result](c_malloc(csize_t len*sizeof(T)))

proc wv_free*[T: ptr](p: T) {.inline.} =
  c_free(p)

# -------------------------------------------------------

proc prepareMatrix[T](matrix: var Matrix[T], N: int) =
  matrix.buffer = wv_alloc(T, N*N)
  matrix.ld = N

  for i in 0 ..< N:
    for j in 0 ..< N:
      matrix[i, j] = 1.0 / T(N) * T(i) * 100

proc newHistogram(bins: int): Histogram =
  result.buffer = wv_alloc(int64, bins)
  result.len = bins

# Reports
# -------------------------------------------------------

template memUsage(maxRSS, runtimeRSS, pageFaults: untyped{ident}, body: untyped) =
  var maxRSS, runtimeRSS, pageFaults: int32
  block:
    var ru: Rusage
    getrusage(RusageSelf, ru)
    runtimeRSS = ru.ru_maxrss
    pageFaults = ru.ru_minflt

    body

    getrusage(RusageSelf, ru)
    runtimeRSS = ru.ru_maxrss - runtimeRSS
    pageFaults = ru.ru_minflt - pageFaults
    maxRss = ru.ru_maxrss

proc reportConfig(
    scheduler: string,
    nthreads, N, bins: int) =

  echo "--------------------------------------------------------------------------"
  echo "Scheduler:                                    ", scheduler
  echo "Benchmark:                                    Histogram 2D "
  echo "Threads:                                      ", nthreads
  echo "Matrix:                                       ", N, " x ", N
  echo "Histogram bins:                               ", bins

proc reportBench(
    time: float64, maxRSS, runtimeRss, pageFaults: int, max: SomeFloat
  ) =
  echo "--------------------------------------------------------------------------"
  echo "Time(ms):                                     ", round(time, 3)
  echo "Max RSS (KB):                                 ", maxRss
  echo "Runtime RSS (KB):                             ", runtimeRSS
  echo "# of page faults:                             ", pageFaults
  echo "Max (from histogram):                         ", max

template runBench(tp: Threadpool, procName: untyped, matrix: Matrix, bins: int, parallel: static bool = true) =
  var hist = newHistogram(bins)

  when not defined(windows):
    block:
      var max: matrix.T
      let start = wtime_msec()
      memUsage(maxRSS, runtimeRSS, pageFaults):
        when parallel:
          tp = Threadpool.new()
          max = procName(tp, matrix, hist)
          tp.shutdown()
        else:
          max = procName(matrix, hist)
      let stop = wtime_msec()

      reportBench(stop-start, maxRSS, runtimeRSS, pageFaults, max)
  else:
    block:
      var max: matrix.T
      when parallel:
        tp = Threadpool.new()
        max = procName(tp, matrix, hist)
        tp.shutdown()
      else:
        max = procName(matrix, hist)

  wv_free(hist.buffer)

# Algo
# -------------------------------------------------------

proc generateHistogramSerial[T](matrix: Matrix[T], hist: Histogram): T =

  # zero-ing the histogram
  for i in 0 ..< hist.len:
    hist[i] = 0

  # Note don't run on borders, they have no neighbour
  for i in 1 ..< matrix.ld-1:
    for j in 1 ..< matrix.ld-1:

      # Sum of cell neigbors
      let sum = abs(matrix[i, j] - matrix[i-1, j]) + abs(matrix[i,j] - matrix[i+1, j]) +
                abs(matrix[i, j] - matrix[i, j-1] + abs(matrix[i, j] - matrix[i, j+1]))

      # Compute index of histogram bin
      let k = int(sum * T(matrix.ld))
      hist[k] += 1

      # Keep track of the largest element
      if sum > result:
        result = sum

proc generateHistogramThreadpoolReduce[T](tp: Threadpool, matrix: Matrix[T], hist: Histogram): T =
  # We await reduce max only, sending the histogram across threads
  # is too costly so the temporary histogram are freed in their allocating threads

  # In generic proc, Nim tries to resolve symbol earlier than when the reduce macros creates them
  # so we need to tell Nim that the symbol will exist in time.
  mixin distributedMax

  let boxes = hist.len

  for i in 0 ..< boxes:
    hist[i] = 0

  # Parallel reduction
  tp.parallelFor i in 1 ..< matrix.ld-1:
    captures: {hist, matrix, boxes}
    reduceInto(distributedMax: Flowvar[T]):
      prologue:
        let threadHist = newHistogram(boxes)
        var max = T(-Inf)
      forLoop:
        # with inner for loop
        for j in 1 ..< matrix.ld-1:
          let sum = abs(matrix[i, j] - matrix[i-1, j]) + abs(matrix[i,j] - matrix[i+1, j]) +
                    abs(matrix[i, j] - matrix[i, j-1] + abs(matrix[i, j] - matrix[i, j+1]))
          let k = int(sum * T(matrix.ld))

          threadHist[k] += 1
          if sum > max:
            max = sum
      merge(remoteMax: FlowVar[T]):
        block:
          let remoteMax = sync(remoteMax) # Await max from other thread
          if remoteMax > max:
            max = remoteMax
          for k in 0 ..< boxes:
            discard hist[k].addr.atomicFetchAdd(threadHist[k], ATOMIC_RELAXED)
      epilogue:
        wv_free(threadHist.buffer)
        return max

  return sync(distributedMax)

# proc generateHistogramThreadpoolStaged[T](matrix: Matrix[T], hist: Histogram): T =

#   var max = T(-Inf)
#   let maxAddr = max.addr

#   var lock: Lock
#   lock.initLock()
#   let lockAddr = lock.addr

#   let boxes = hist.len

#   for i in 0 ..< boxes:
#     hist[i] = 0

#   # Parallel reduction
#   parallelForStaged i in 1 ..< matrix.ld-1:
#     captures: {maxAddr, lockAddr, hist, matrix, boxes}
#     awaitable: histoLoop
#     prologue:
#       let threadHist = newHistogram(boxes)
#       var threadMax = T(-Inf)
#     forLoop:
#       # with inner for loop
#       for j in 1 ..< matrix.ld-1:
#         let sum = abs(matrix[i, j] - matrix[i-1, j]) + abs(matrix[i,j] - matrix[i+1, j]) +
#                   abs(matrix[i, j] - matrix[i, j-1] + abs(matrix[i, j] - matrix[i, j+1]))
#         let k = int(sum * T(matrix.ld))

#         threadHist[k] += 1
#         if sum > threadMax:
#           threadMax = sum
#     epilogue:
#       lockAddr[].acquire()
#       maxAddr[] = max(maxAddr[], threadMax)
#       if threadMax > maxAddr[]:
#         maxAddr[] = threadMax
#       for k in 0 ..< boxes:
#         hist[k] += threadHist[k]
#       lockAddr[].release()
#       wv_free(threadHist.buffer)

#   let waslastThread = sync(histoLoop)
#   lock.deinitLock()
#   return max

proc main() =

  if sizeof(int) == 4:
    echo "Running on 32-bit. This benchmark is requires 64-bit."
    return

  var
    matrixSize = 25000
    boxes = 1000

  if paramCount() == 0:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <matrixSize: int> <boxes: int>"
    echo &"Running with default matrixSize={matrixSize}, boxes={boxes}"
  elif paramCount() == 2:
    matrixSize = paramStr(1).parseInt()
    boxes = paramStr(2).parseInt()
  else:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <matrixSize: int> <boxes: int>"
    echo &"Default \"{exeName} {matrixSize} {boxes}\""
    quit 1

  var nthreads: int
  if existsEnv"CTT_NUM_THREADS":
    nthreads = getEnv"CTT_NUM_THREADS".parseInt()
  else:
    nthreads = countProcessors()

  var tp: Threadpool
  var matrix: Matrix[float32]
  # The reference code zero-out the histogram in the bench as well
  prepareMatrix(matrix, matrixSize)

  reportConfig("Sequential", 1, matrixSize, boxes)
  runBench(tp, generateHistogramSerial, matrix, boxes, parallel = false)
  reportConfig("Constantine's threadpool - Parallel Reduce", nthreads, matrixSize, boxes)
  runBench(tp, generateHistogramThreadpoolReduce, matrix, boxes)
  # reportConfig("Constantine's threadpool - Parallel For Staged", nthreads, matrixSize, boxes)
  # runBench(generateHistogramThreadpoolStaged, matrix, boxes)

  wv_free(matrix.buffer)


main()
