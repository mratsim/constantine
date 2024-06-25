# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Stdlib
  system/ansi_c, std/[strformat, os, strutils, cpuinfo, math, random, locks],
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
# Note that matrices for log-sum-exp are usually in the following shapes:
# - Classification of a batch of 256 images in 3 categories: 256x3
# - Classification of a batch of words from a 50000 words dictionary: 256x50000

# Helpers
# -------------------------------------------------------

proc wv_alloc*(T: typedesc): ptr T {.inline.}=
  cast[ptr T](c_malloc(csize_t sizeof(T)))

proc wv_alloc*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T] {.inline.} =
  cast[type result](c_malloc(csize_t len*sizeof(T)))

proc wv_free*[T: ptr](p: T) {.inline.} =
  c_free(p)

# We need a thin wrapper around raw pointers for matrices,
# we can't pass "var" to other threads
type
  Matrix[T: SomeFloat] = object
    buffer: ptr UncheckedArray[T]
    nrows, ncols: int # int64 on x86-64

func newMatrix[T](rows, cols: Natural): Matrix[T] {.inline.} =
  # Create a rows x cols Matrix
  result.buffer = cast[ptr UncheckedArray[T]](c_malloc(csize_t rows*cols*sizeof(T)))
  result.nrows = rows
  result.ncols = cols

template `[]`[T](M: Matrix[T], row, col: Natural): T =
  # row-major storage
  assert row < M.nrows
  assert col < M.ncols
  M.buffer[row * M.ncols + col]

template `[]=`[T](M: Matrix[T], row, col: Natural, value: T) =
  assert row < M.nrows
  assert col < M.ncols
  M.buffer[row * M.ncols + col] = value

proc initialize[T](M: Matrix[T]) =
  randomize(1234) # Seed
  for i in 0 ..< M.nrows:
    for j in 0 ..< M.ncols:
      M[i, j] = T(rand(1.0))

func rowView*[T](M: Matrix[T], rowPos, size: Natural): Matrix[T]{.inline.}=
  ## Returns a new view offset by the row and column stride
  result.buffer = cast[ptr UncheckedArray[T]](
    addr M.buffer[rowPos * M.ncols]
  )
  result.nrows = size
  result.ncols = M.ncols

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
    nthreads: int, datasetSize, batchSize, imageLabels, textVocabulary: int64
  ) =

  echo "--------------------------------------------------------------------------"
  echo "Scheduler:                                    ", scheduler
  echo "Benchmark:                                    Log-Sum-Exp (Machine Learning) "
  echo "Threads:                                      ", nthreads
  echo "datasetSize:                                  ", datasetSize
  echo "batchSize:                                    ", batchSize
  echo "# of full batches:                            ", datasetSize div batchSize
  echo "# of image labels:                            ", imageLabels
  echo "Text vocabulary size:                         ", textVocabulary

proc reportBench(
    batchSize, numLabels: int64,
    time: float64, maxRSS, runtimeRss, pageFaults: int32,
    logSumExp: float32
  ) =
  echo "--------------------------------------------------------------------------"
  echo "Dataset:                                      ", batchSize,'x',numLabels
  echo "Time(ms):                                     ", round(time, 3)
  echo "Max RSS (KB):                                 ", maxRss
  echo "Runtime RSS (KB):                             ", runtimeRSS
  echo "# of page faults:                             ", pageFaults
  echo "Logsumexp:                                    ", logsumexp

template runBench(procName: untyped, datasetSize, batchSize, numLabels: int64) =
  let data = newMatrix[float32](datasetSize, numLabels)
  data.initialize()

  when not defined(windows):
    let start = wtime_msec()

    var lse = 0'f32
    memUsage(maxRSS, runtimeRSS, pageFaults):
      # For simplicity we ignore the last few data points
      for batchIdx in 0 ..< datasetSize div batchSize:
        let X = data.rowView(batchIdx*batchSize, batchSize)
        lse += procName(X)

    let stop = wtime_msec()

    reportBench(batchSize, numlabels, stop-start, maxRSS, runtimeRSS, pageFaults, lse)
  else:
    # For simplicity we ignore the last few data points
    var lse = 0'f32
    for batchIdx in 0 ..< datasetSize div batchSize:
      let X = data.rowView(batchIdx*batchSize, batchSize)
      lse += procName(X)


template runBench(tp: Threadpool, procName: untyped, datasetSize, batchSize, numLabels: int64) =
  let data = newMatrix[float32](datasetSize, numLabels)
  data.initialize()

  when not defined(windows):
    let start = wtime_msec()

    var lse = 0'f32
    memUsage(maxRSS, runtimeRSS, pageFaults):
      # For simplicity we ignore the last few data points
      for batchIdx in 0 ..< datasetSize div batchSize:
        let X = data.rowView(batchIdx*batchSize, batchSize)
        lse += procName(tp, X)

    let stop = wtime_msec()

    reportBench(batchSize, numlabels, stop-start, maxRSS, runtimeRSS, pageFaults, lse)
  else:
    var lse = 0'f32
    for batchIdx in 0 ..< datasetSize div batchSize:
      let X = data.rowView(batchIdx*batchSize, batchSize)
      lse += procName(tp, X)

# Algo - Serial
# -------------------------------------------------------

proc maxSerial[T: SomeFloat](M: Matrix[T]) : T =
  result = T(-Inf)

  for i in 0 ..< M.nrows:
    for j in 0 ..< M.ncols:
      result = max(result, M[i, j])

proc logsumexpSerial[T: SomeFloat](M: Matrix[T]): T =
  let alpha = M.maxSerial()

  result = 0

  for i in 0 ..< M.nrows:
    for j in 0 ..< M.ncols:
      result += exp(M[i, j] - alpha)

  result = alpha + ln(result)

# Algo - parallel reduction
# -------------------------------------------------------

proc maxThreadpoolReduce[T: SomeFloat](tp: Threadpool, M: Matrix[T]) : T =
  mixin globalMax

  tp.parallelFor i in 0 ..< M.nrows:
    captures:{M}
    reduceInto(globalMax: Flowvar[T]):
      prologue:
        var localMax = T(-Inf)
      forLoop:
        for j in 0 ..< M.ncols:
          localMax = max(localMax, M[i, j])
      merge(remoteMax: Flowvar[T]):
        localMax = max(localMax, sync(remoteMax))
      epilogue:
        return localMax

  result = sync(globalMax)

proc logsumexpThreadpoolReduce[T: SomeFloat](tp: Threadpool, M: Matrix[T]): T =
  mixin lse

  let alpha = tp.maxThreadpoolReduce(M)
  tp.parallelFor i in 0 ..< M.nrows:
    captures:{alpha, M}
    reduceInto(lse: Flowvar[T]):
      prologue:
        var localLSE = 0.T
      forLoop:
        for j in 0 ..< M.ncols:
          localLSE += exp(M[i, j] - alpha)
      merge(remoteLSE: Flowvar[T]):
        localLSE += sync(remoteLSE)
      epilogue:
        return localLSE

  result = alpha + ln(sync(lse))

# Algo - parallel reduction collapsed
# -------------------------------------------------------

proc maxThreadpoolCollapsed[T: SomeFloat](tp: Threadpool, M: Matrix[T]) : T =
  mixin globalMax

  tp.parallelFor ij in 0 ..< M.nrows * M.ncols:
    captures:{M}
    reduceInto(globalMax: Flowvar[T]):
      prologue:
        var localMax = T(-Inf)
      forLoop:
        localMax = max(localMax, M.buffer[ij])
      merge(remoteMax: FlowVar[T]):
        localMax = max(localMax, sync(remoteMax))
      epilogue:
        return localMax

  result = sync(globalMax)

proc logsumexpThreadpoolCollapsed[T: SomeFloat](tp: Threadpool, M: Matrix[T]): T =
  mixin lse
  let alpha = tp.maxThreadpoolCollapsed(M)

  tp.parallelFor ij in 0 ..< M.nrows * M.ncols:
    captures:{alpha, M}
    reduceInto(lse: Flowvar[T]):
      prologue:
        var localLSE = 0.T
      forLoop:
        localLSE += exp(M.buffer[ij] - alpha)
      merge(remoteLSE: Flowvar[T]):
        localLSE += sync(remoteLSE)
      epilogue:
        return localLSE

  result = alpha + ln(sync(lse))

# proc maxThreadpoolStaged[T: SomeFloat](tp: Threadpool, M: Matrix[T]) : T =
#   mixin maxLoop
#
#   var max = T(-Inf)
#   let maxAddr = max.addr
#
#   var lock: Lock
#   lock.initLock()
#   let lockAddr = lock.addr
#
#   tp.parallelForStaged i in 0 ..< M.nrows:
#     captures:{maxAddr, lockAddr, M}
#     awaitable: maxLoop
#     prologue:
#       var localMax = T(-Inf)
#     forLoop:
#       for j in 0 ..< M.ncols:
#         localMax = max(localMax, M[i, j])
#     epilogue:
#       lockAddr[].acquire()
#       maxAddr[] = max(maxAddr[], localMax)
#       lockAddr[].release()
#
#   let waslastThread = sync(maxLoop)
#   lock.deinitLock()
#
# proc logsumexpThreadpoolStaged[T: SomeFloat](tp: Threadpool, M: Matrix[T]): T =
#   mixin logSumExpLoop
#   let alpha = M.maxThreadpoolStaged()
#
#   var lse = T(0)
#   let lseAddr = lse.addr
#
#   # Atomic increment for float is done with a Compare-And-Swap loop usually.
#   # Due to lazy splitting, load distribution is unbalanced between threads so they shouldn't
#   # finish at the same time in general and lock contention would be low
#   var lock: Lock
#   lock.initLock()
#   let lockAddr = lock.addr
#
#  tp.parallelForStaged i in 0 ..< M.nrows:
#     captures:{lseAddr, lockAddr, alpha, M}
#     awaitable: logSumExpLoop
#     prologue:
#       var localLSE = 0.T
#     loop:
#       for j in 0 ..< M.ncols:
#         localLSE += exp(M[i, j] - alpha)
#     epilogue:
#       lockAddr[].acquire()
#       lseAddr[] += localLSE
#       lockAddr[].release()
#
#   let wasLastThread = sync(logSumExpLoop)
#   result = alpha + ln(lse)
#   lock.deinitLock()

# Main
# -------------------------------------------------------

proc main() =
  echo "Note that a text vocabulary is often in the 50000-15000 words\n"

  var
    datasetSize     = 20000'i64
    batchSize       = 256'i64
    imagelabels     = 1000'i64
    textVocabulary = 10000'i64

  if paramCount() == 0:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <datasetSize: int64> <batchSize: int64> <imagelabels: int64> <textVocabulary: int64>"
    echo &"Running with default datasetSize={datasetSize}, batchSize={batchSize}, imagelabels={imagelabels}, textVocabulary={textVocabulary}"
  elif paramCount() == 4:
    datasetSize    = paramStr(1).parseBiggestInt().int64
    batchSize      = paramStr(2).parseBiggestInt().int64
    imagelabels    = paramStr(3).parseBiggestInt().int64
    textVocabulary = paramStr(4).parseBiggestInt().int64
  else:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <datasetSize: int64> <batchSize: int64> <imagelabels: int64> <textVocabulary: int64>"
    echo &"Default \"{datasetSize} {batchSize} {imagelabels} {textVocabulary}\""
    quit 1

  var nthreads: int
  if existsEnv"CTT_NUM_THREADS":
    nthreads = getEnv"CTT_NUM_THREADS".parseInt()
  else:
    nthreads = countProcessors()

  let sanityM = newMatrix[float32](1, 9)
  for i in 0'i32 ..< 9:
    sanityM[0, i] = i.float32 + 1

  echo "Sanity check, logSumExp(1..<10) should be 9.4585514 (numpy logsumexp): ", logsumexpSerial(sanityM)
  echo '\n'
  wv_free(sanityM.buffer)

  reportConfig("Sequential", 1, datasetSize, batchSize, imageLabels, textVocabulary)
  block:
    runBench(logsumexpSerial, datasetSize, batchSize, imageLabels)
  block:
    runBench(logsumexpSerial, datasetSize, batchSize, textVocabulary)

  # TODO: Placing the threadpool before the sequential bench makes it take ~85 ms instead of ~48 ms
  var tp = Threadpool.new(nthreads)

  # TODO: The parallel algorithm is slower than Weave AND slower than serial

  reportConfig("Constantine's Threadpool Reduce", nthreads, datasetSize, batchSize, imageLabels, textVocabulary)
  block:
    tp.runBench(logsumexpThreadpoolReduce, datasetSize, batchSize, imageLabels)
  block:
    tp.runBench(logsumexpThreadpoolReduce, datasetSize, batchSize, textVocabulary)

  reportConfig("Constantine's Threadpool (Collapsed)", nthreads, datasetSize, batchSize, imageLabels, textVocabulary)
  block:
    tp.runBench(logsumexpThreadpoolCollapsed, datasetSize, batchSize, imageLabels)
  block:
    tp.runBench(logsumexpThreadpoolCollapsed, datasetSize, batchSize, textVocabulary)

  # reportConfig("Constantine's Threadpool (Staged)", nthreads, datasetSize, batchSize, imageLabels, textVocabulary)
  # block:
  #   tp.runBench(logsumexpThreadpoolStaged, datasetSize, batchSize, imageLabels)
  # block:
  #   tp.runBench(logsumexpThreadpoolStaged, datasetSize, batchSize, textVocabulary)

  tp.shutdown()

main()
