# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Original transposition codes from Laser project
# (c) Mamy André Ratsimbazafy, Apache  License version 2

import
  # Stdlib
  system/ansi_c, std/[strformat, os, strutils, math, cpuinfo],
  # Constantine
  constantine/threadpool

when not defined(windows):
  # bench
  import ../wtime, ../resources


# Memory
# ---------------------------------------------------

proc wv_alloc*(T: typedesc): ptr T {.inline.}=
  ## Default allocator for the Picasso library
  ## This allocates memory to hold the type T
  ## and returns a pointer to it
  ##
  ## Can use Nim allocator to measure the overhead of its lock
  ## Memory is not zeroed
  when defined(WV_useNimAlloc):
    createSharedU(T)
  else:
    cast[ptr T](c_malloc(csize_t sizeof(T)))

proc wv_alloc*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T] {.inline.} =
  ## Default allocator for the Picasso library.
  ## This allocates a contiguous chunk of memory
  ## to hold ``len`` elements of type T
  ## and returns a pointer to it.
  ##
  ## Can use Nim allocator to measure the overhead of its lock
  ## Memory is not zeroed
  when defined(WV_useNimAlloc):
    cast[type result](createSharedU(T, len))
  else:
    cast[type result](c_malloc(csize_t len*sizeof(T)))

proc wv_free*[T: ptr](p: T) {.inline.} =
  when defined(WV_useNimAlloc):
    freeShared(p)
  else:
    c_free(p)

# Transpose implementations
# ---------------------------------------------------

type TransposeStrategy = enum
  Sequential
  Naive
  Nested
  TiledNested

# Question: do we need __restrict to avoid the compiler generating
#           defensive aliasing robust code?

proc sequentialTranspose(tp: Threadpool, M, N: int, bufIn, bufOut: ptr UncheckedArray[float32]) =
  for j in 0 ..< N:
    for i in 0 ..< M:
      bufOut[j*M+i] = bufIn[i*N+j]

proc cttNaiveTranspose(tp: Threadpool, M, N: int, bufIn, bufOut: ptr UncheckedArray[float32]) =
  ## Transpose a MxN matrix into a NxM matrix

  # Write are more expensive than read so we keep i accesses linear for writes
  tp.parallelFor j in 0 ..< N:
    captures: {M, N, bufIn, bufOut}
    for i in 0 ..< M:
      bufOut[j*M+i] = bufIn[i*N+j]

proc cttNestedTranspose(tp: Threadpool, M, N: int, bufIn, bufOut: ptr UncheckedArray[float32]) =
  ## Transpose a MxN matrix into a NxM matrix with nested for loops

  tp.parallelFor j in 0 ..< N:
    captures: {tp, M, N, bufIn, bufOut}
    tp.parallelFor i in 0 ..< M:
      captures: {j, M, N, bufIn, bufOut}
      bufOut[j*M+i] = bufIn[i*N+j]

proc ctt2DTiledNestedTranspose(tp: Threadpool, M, N: int, bufIn, bufOut: ptr UncheckedArray[float32]) =
  ## Transpose with 2D tiling and nested

  const blck = 64 # const do not need to be captured

  tp.parallelFor j in 0 ..< N:
    stride: blck
    captures: {tp, M, N, bufIn, bufOut}
    tp.parallelFor i in 0 ..< M:
      stride: blck
      captures: {j, M, N, bufIn, bufOut}
      for jj in j ..< min(j+blck, N):
        for ii in i ..< min(i+blck, M):
          bufOut[jj*M+ii] = bufIn[ii*N+jj]

# Meta
# ---------------------------------------------------

func computeMeta(height, width: int): tuple[reqOps, reqBytes, bufSize: int] =

  result.reqOps = height * width
  result.reqBytes = sizeof(float32) * height * width
  result.bufSize = height * width

func initialize(buffer: ptr UncheckedArray[float32], len: int) =
  for i in 0 ..< len:
    buffer[i] = i.float32

# Bench
# ---------------------------------------------------

template memUsage(maxRSS, runtimeRSS, pageFaults: untyped{ident}, body: untyped) =
  var maxRSS, runtimeRSS, pageFaults: int32
  block:
    when not defined(windows):
      var ru: Rusage
      getrusage(RusageSelf, ru)
      runtimeRSS = ru.ru_maxrss
      pageFaults = ru.ru_minflt

    body

    when not defined(windows):
      getrusage(RusageSelf, ru)
      runtimeRSS = ru.ru_maxrss - runtimeRSS
      pageFaults = ru.ru_minflt - pageFaults
      maxRss = ru.ru_maxrss

proc report(
    M, N: int, nthreads: int32, nrounds: int, reordered: bool,
    transposeStrategy: TransposeStrategy, reqOps, reqBytes: int,
    mxnTime: float64, mxnMaxRSS, mxnRuntimeRss, mxnPageFaults: int32,
    nxmTime: float64, nxmMaxRSS, nxmRuntimeRss, nxmPageFaults: int32,
  ) =

  let arithIntensity = reqOps.float / reqBytes.float
  let mxnPerf = reqOps.float/(mxnTime*1e-3 / nrounds.float) * 1e-9 # Gops per second
  let nxmPerf = reqOps.float/(nxmTime*1e-3 / nrounds.float) * 1e-9 # Gops per second

  echo "--------------------------------------------------------------------------"
  echo "Scheduler:                                    Constantine's threadpool"
  echo "Benchmark:                                    Transpose - ", $transposeStrategy
  echo "Threads:                                      ", nthreads
  echo "# of rounds:                                  ", nrounds
  echo "# of operations:                              ", reqOps
  echo "# of bytes:                                   ", reqBytes
  echo "Arithmetic Intensity:                         ", round(arithIntensity, 3)
  echo "--------------------------------------------------------------------------"
  if not reordered:
    echo "Transposition:                                ", M,'x',N, " --> ", N, 'x', M
    when not defined(windows):
      echo "Time(ms):                                     ", round(mxnTime, 3)
      echo "Max RSS (KB):                                 ", mxnMaxRss
      echo "Runtime RSS (KB):                             ", mxnRuntimeRSS
      echo "# of page faults:                             ", mxnPageFaults
      echo "Perf (GMEMOPs/s ~ GigaMemory Operations/s)    ", round(mxnPerf, 3)
    echo "--------------------------------------------------------------------------"
    echo "Transposition:                                ", N,'x',M, " --> ", M, 'x', N
    when not defined(windows):
      echo "Time(ms):                                     ", round(nxmTime, 3)
      echo "Max RSS (KB):                                 ", nxmMaxRss
      echo "Runtime RSS (KB):                             ", nxmRuntimeRSS
      echo "# of page faults:                             ", nxmPageFaults
      echo "Perf (GMEMOPs/s ~ GigaMemory Operations/s)    ", round(nxmPerf, 3)
  else:
    echo "Transposition:                                ", N,'x',M, " --> ", M, 'x', N
    when not defined(windows):
      echo "Time(ms):                                     ", round(nxmTime, 3)
      echo "Max RSS (KB):                                 ", nxmMaxRss
      echo "Runtime RSS (KB):                             ", nxmRuntimeRSS
      echo "# of page faults:                             ", nxmPageFaults
      echo "Perf (GMEMOPs/s ~ GigaMemory Operations/s)    ", round(mxnPerf, 3)
    echo "--------------------------------------------------------------------------"
    echo "Transposition:                                ", M,'x',N, " --> ", N, 'x', M
    when not defined(windows):
      echo "Time(ms):                                     ", round(mxnTime, 3)
      echo "Max RSS (KB):                                 ", mxnMaxRss
      echo "Runtime RSS (KB):                             ", mxnRuntimeRSS
      echo "# of page faults:                             ", mxnPageFaults
      echo "Perf (GMEMOPs/s ~ GigaMemory Operations/s)    ", round(nxmPerf, 3)

template runBench(tp: Threadpool, transposeName: typed, reorderCompute, isSequential: bool): untyped =
  if not reorderCompute:
    if not isSequential:
      tp = Threadpool.new()
    memUsage(mxnMaxRss, mxnRuntimeRss, mxnPageFaults):
      when not defined(windows):
        let start = wtime_msec()
      for _ in 0 ..< nrounds:
        tp.transposeName(M, N, bufIn, bufOut)
      if not isSequential:
        tp.syncAll()
      when not defined(windows):
        let stop = wtime_msec()
        mxnTime = stop - start

    memUsage(nxmMaxRss, nxmRuntimeRss, nxmPageFaults):
      when not defined(windows):
        let start = wtime_msec()
      for _ in 0 ..< nrounds:
        tp.transposeName(N, M, bufIn, bufOut)
      if not isSequential:
        tp.syncAll()
      when not defined(windows):
        let stop = wtime_msec()
        nxmTime = stop - start

    if not isSequential:
      tp.shutdown()

    report(M, N, nthreads, nrounds, reorderCompute,
        transposeStrat, reqOps, reqBytes,
        mxnTime, mxnMaxRSS, mxnRuntimeRss, mxnPageFaults,
        nxmTime, nxmMaxRSS, nxmRuntimeRss, nxmPageFaults
      )

  else:
    if not isSequential:
      tp = Threadpool.new()
    memUsage(nxmMaxRss, nxmRuntimeRss, nxmPageFaults):
      when not defined(windows):
        let start = wtime_msec()
      for _ in 0 ..< nrounds:
        tp.transposeName(N, M, bufIn, bufOut)
      if not isSequential:
        tp.syncAll()
      when not defined(windows):
        let stop = wtime_msec()
        nxmTime = stop - start

    memUsage(mxnMaxRss, mxnRuntimeRss, mxnPageFaults):
      when not defined(windows):
        let start = wtime_msec()
      for _ in 0 ..< nrounds:
        tp.transposeName(M, N, bufIn, bufOut)
      if not isSequential:
        tp.syncAll()
      when not defined(windows):
        let stop = wtime_msec()
        mxnTime = stop - start

    if not isSequential:
      tp.shutdown()

    report(M, N, nthreads, nrounds, reorderCompute,
        transposeStrat, reqOps, reqBytes,
        mxnTime, mxnMaxRSS, mxnRuntimeRss, mxnPageFaults,
        nxmTime, nxmMaxRSS, nxmRuntimeRss, nxmPageFaults
      )

# Interface
# ---------------------------------------------------

proc main() =

  var
    M = 400
    N = 4000
    nrounds = 1000
    transposeStrat = TiledNested
    reorderCompute = false

  if paramCount() == 0:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <M: int> <N: int> <rounds: int> <transposeStrategy: Sequential|Naive|Nested|TiledNested> <reorderCompute: bool>"
    echo &"Running with default M={M}, N={N}, rounds={nrounds}, transposeStrategy={transposeStrat}, reorderCompute={reorderCompute}"
  elif paramCount() == 5:
    M = paramStr(1).parseInt()
    N = paramStr(2).parseInt()
    nrounds = paramStr(3).parseInt()
    transposeStrat = paramStr(4).parseEnum[:TransposeStrategy]()
    reorderCompute = paramStr(5).parseBool()
  else:
    let exeName = getAppFilename().extractFilename()
    echo &"Usage: {exeName} <M: int> <N: int> <rounds: int> <transposeStrategy: Sequential|Naive|Nested|TiledNested> <reorderCompute: bool>"
    echo &"Default \"{exeName} {M} {N} {nrounds} {transposeStrat} {reorderCompute}\""
    quit 1

  echo "Inverting the transpose order may favor one transposition heavily for non-tiled strategies"

  let isSequential = transposeStrat == Sequential
  var nthreads: int32
  if transposeStrat == Sequential:
    nthreads = 1
  elif existsEnv"CTT_NUM_THREADS":
    nthreads = getEnv"CTT_NUM_THREADS".parseInt().int32
  else:
    nthreads = countProcessors().int32

  let (reqOps, reqBytes, bufSize) = computeMeta(M, N)

  let bufOut = wv_alloc(float32, bufSize)
  let bufIn = wv_alloc(float32, bufSize)

  bufIn.initialize(bufSize)

  var mxnTime, nxmTime: float64

  var tp: Threadpool
  case transposeStrat
  of Sequential: tp.runBench(sequentialTranspose, reorderCompute, isSequential)
  of Naive: tp.runBench(cttNaiveTranspose, reorderCompute, isSequential)
  of Nested: tp.runBench(cttNestedTranspose, reorderCompute, isSequential)
  of TiledNested: tp.runBench(ctt2DTiledNestedTranspose, reorderCompute, isSequential)

  wv_free(bufOut)
  wv_free(bufIn)

main()
