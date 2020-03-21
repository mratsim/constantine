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
  ../constantine/tower_field_extensions/[abelian_groups, fp2_complex, fp6_1_plus_i],
  # Helpers
  ../helpers/[timers, prng, static_for],
  # Standard library
  std/[monotimes, times, strformat, strutils, macros]

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

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

template bench(op: string, T: typedesc, iters: int, body: untyped): untyped =
  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< iters:
    body
  let stopClk = getTicks()
  let stop = getMonotime()

  report(op, fixFieldDisplay(T), start, stop, startClk, stopClk, iters)

proc addBench*(T: typedesc, iters: int) =
  var x = rng.random(T)
  let y = rng.random(T)
  bench("Addition", T, iters):
    x += y

proc subBench*(T: typedesc, iters: int) =
  var x = rng.random(T)
  let y = rng.random(T)
  preventOptimAway(x)
  bench("Substraction", T, iters):
    x -= y

proc negBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random(T)
  bench("Negation", T, iters):
    r.neg(x)

proc mulBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random(T)
  let y = rng.random(T)
  preventOptimAway(r)
  bench("Multiplication", T, iters):
    r.prod(x, y)

proc sqrBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random(T)
  preventOptimAway(r)
  bench("Squaring", T, iters):
    r.square(x)

proc invBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random(T)
  preventOptimAway(r)
  bench("Inversion", T, iters):
    r.inv(x)
