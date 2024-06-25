# Demo of API using a very inefficient π approcimation algorithm.

import
  std/[strutils, cpuinfo],
  constantine/threadpool

# From https://github.com/nim-lang/Nim/blob/v1.6.2/tests/parallel/tpi.nim
# Leibniz Formula https://en.wikipedia.org/wiki/Leibniz_formula_for_%CF%80
proc term(k: int): float =
  if k mod 2 == 1:
    -4'f / float(2*k + 1)
  else:
    4'f / float(2*k + 1)

proc piApprox(tp: Threadpool, n: int): float =
  var pendingFuts = newSeq[Flowvar[float]](n)
  for k in 0 ..< pendingFuts.len:
    pendingFuts[k] = tp.spawn term(k) # Schedule a task on the threadpool a return a handle to retrieve the result.
  for k in 0 ..< pendingFuts.len:
    result += sync pendingFuts[k]     # Block until the result is available.

proc main() =

  echo "\n=============================================================================================="
  echo "Running 'threadpool/examples/e02_parallel_pi.nim'"
  echo "=============================================================================================="

  var n = 1_000_000
  let tp = Threadpool.new() # Default to the number of hardware threads.

  echo formatFloat(tp.piApprox(n))

  tp.shutdown()

# Compile with nim c -r -d:release --threads:on --outdir:build example.nim
main()
