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
  ../constantine/config/[curves, common],
  ../constantine/arithmetic,
  ../constantine/towers,
  # Helpers
  ../helpers/[prng_unsafe, static_for],
  ./platforms,
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

echo "Optimization level => "
echo "  no optimization: ", not defined(release)
echo "  release: ", defined(release)
echo "  danger: ", defined(danger)
echo "  inline assembly: ", UseX86ASM

when (sizeof(int) == 4) or defined(Constantine32):
  echo "⚠️ Warning: using Constantine with 32-bit limbs"
else:
  echo "Using Constantine with 64-bit limbs"

when SupportsCPUName:
  echo "Running on ", cpuName(), ""

when SupportsGetTicks:
  echo "\n⚠️ Cycles measurements are approximate and use the CPU nominal clock: Turbo-Boost and overclocking will skew them."
  echo "i.e. a 20% overclock will be about 20% off (assuming no dynamic frequency scaling)"

echo "\n=================================================================================================================\n"

proc separator*() =
  echo "-".repeat(145)

proc report(op, field: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<50} {field:<18} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<50} {field:<18} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

proc notes*() =
  echo "Notes:"
  echo "  - Compilers:"
  echo "    Compilers are severely limited on multiprecision arithmetic."
  echo "    Inline Assembly is used by default (nimble bench_fp)."
  echo "    Bench without assembly can use \"nimble bench_fp_gcc\" or \"nimble bench_fp_clang\"."
  echo "    GCC is significantly slower than Clang on multiprecision arithmetic due to catastrophic handling of carries."
  echo "  - The simplest operations might be optimized away by the compiler."
  echo "  - Fast Squaring and Fast Multiplication are possible if there are spare bits in the prime representation (i.e. the prime uses 254 bits out of 256 bits)"

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Curve(instantiated[1][1].intVal) & "]"
  result = newLit name

template bench(op: string, T: typedesc, iters: int, body: untyped): untyped =
  let start = getMonotime()
  when SupportsGetTicks:
    let startClk = getTicks()
  for _ in 0 ..< iters:
    body
  when SupportsGetTicks:
    let stopClk = getTicks()
  let stop = getMonotime()

  when not SupportsGetTicks:
    let startClk = -1'i64
    let stopClk = -1'i64

  report(op, fixFieldDisplay(T), start, stop, startClk, stopClk, iters)

proc addBench*(T: typedesc, iters: int) =
  var x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  bench("Addition", T, iters):
    x += y

proc subBench*(T: typedesc, iters: int) =
  var x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  preventOptimAway(x)
  bench("Substraction", T, iters):
    x -= y

proc negBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  bench("Negation", T, iters):
    r.neg(x)

proc mulBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Multiplication", T, iters):
    r.prod(x, y)

proc sqrBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Squaring", T, iters):
    r.square(x)

proc invBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Inversion (constant-time Euclid)", T, iters):
    r.inv(x)

proc powFermatInversionBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  bench("Inversion via exponentiation p-2 (Little Fermat)", T, iters):
    var r = x
    r.powUnsafeExponent(T.C.getInvModExponent())

proc sqrtBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  bench("Square Root + square check (constant-time)", T, iters):
    var r = x
    discard r.sqrt_if_square()

proc powBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  let exponent = rng.random_unsafe(BigInt[T.C.getCurveOrderBitwidth()])
  bench("Exp curve order (constant-time) - " & $exponent.bits & "-bit", T, iters):
    var r = x
    r.pow(exponent)

proc powUnsafeBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  let exponent = rng.random_unsafe(BigInt[T.C.getCurveOrderBitwidth()])
  bench("Exp curve order (Leak exponent bits) - " & $exponent.bits & "-bit", T, iters):
    var r = x
    r.powUnsafeExponent(exponent)
