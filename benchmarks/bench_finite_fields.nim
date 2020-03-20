# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark of finite fields
#
# ############################################################

import
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/io/[io_bigints, io_fields],
  ../constantine/primitives,
  # Helpers
  ../helpers/[timers, prng, static_for],
  # Standard library
  std/[monotimes, times, strformat, strutils, macros]

const Iters = 1_000_000
const InvIters = 1000
const AvailableCurves = [
  P224,
  BN254,
  P256,
  Secp256k1,
  BLS12_381
]

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench_finite_field xoshiro512** seed: ", seed

# warmup
proc warmup*() =
  # Warmup - make sure cpu is on max perf
  let start = cpuTime()
  var foo = 123
  for i in 0 ..< 300_000_000:
    foo += i*i mod 456
    foo = foo mod 789

  # Compiler shouldn't optimize away the results as cpuTime rely on sideeffects
  let stop = cpuTime()
  echo &"Warmup: {stop - start:>4.4f} s, result {foo} (displayed to avoid compiler optimizing warmup away)\n"

warmup()

echo "\n⚠️ Measurements are approximate and use the CPU nominal clock: Turbo-Boost and overclocking will skew them."
echo "==========================================================================================================\n"
echo "All benchmarks are using constant-time implementations to protect against side-channel attacks."
when defined(gcc):
  echo "\nCompiled with GCC"
elif defined(clang):
  echo "\nCompiled with Clang"
elif defined(vcc):
  echo "\nCompiled with MSVC"
elif defined(icc):
  echo "\nCompiled with ICC"
else:
  echo "\nCompiled with an unknown compiler"

when defined(i386) or defined(amd64):
  import ../helpers/x86
  echo "Running on ", cpuName(), "\n\n"

proc report(op, field: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  echo &"{op:<15} {field:<15} {inNanoseconds((stop-start) div iters):>9} ns {(stopClk - startClk) div iters:>9} cycles"

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Curve(instantiated[1][1].intVal) & "]"
  result = newLit name

# Compilers are smart with dead code (but not with multiprecision arithmetic :/)
var globalsAreNotOptimizedAway: Word

template bench(op: string, T: typedesc, iters: int, body: untyped): untyped =
  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< iters:
    body
  let stopClk = getTicks()
  let stop = getMonotime()

  report(op, fixFieldDisplay(T), start, stop, startClk, stopClk, iters)

proc addBench(T: typedesc) =
  var x = rng.random(T)
  let y = rng.random(T)
  bench("Addition", T, Iters):
    x += y
  globalsAreNotOptimizedAway += x.mres.limbs[^1]

proc subBench(T: typedesc) =
  var x = rng.random(T)
  let y = rng.random(T)
  preventOptimAway(x)
  bench("Substraction", T, Iters):
    x -= y
  globalsAreNotOptimizedAway += x.mres.limbs[^1]

proc negBench(T: typedesc) =
  var r: T
  let x = rng.random(T)
  bench("Negation", T, Iters):
    r.neg(x)
  globalsAreNotOptimizedAway += r.mres.limbs[^1]

proc mulBench(T: typedesc) =
  var r: T
  let x = rng.random(T)
  let y = rng.random(T)
  preventOptimAway(r)
  bench("Multiplication", T, Iters):
    r.prod(x, y)

proc sqrBench(T: typedesc) =
  var r: T
  let x = rng.random(T)
  preventOptimAway(r)
  bench("Squaring", T, Iters):
    r.square(x)

proc invBench(T: typedesc) =
  var r: T
  let x = rng.random(T)
  preventOptimAway(r)
  bench("Inversion", T, InvIters):
    r.inv(x)

proc main() =
  echo "-".repeat(80)
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(Fp[curve])
    subBench(Fp[curve])
    negBench(Fp[curve])
    mulBench(Fp[curve])
    sqrBench(Fp[curve])
    invBench(Fp[curve])
    echo "-".repeat(80)

main()

echo "Notes:"
echo "  GCC is significantly slower than Clang on multiprecision arithmetic."
