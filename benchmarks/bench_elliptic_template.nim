# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark of elliptic curves
#
# ############################################################

import
  # Internals
  ../constantine/config/curves,
  ../constantine/arithmetic,
  ../constantine/io/io_bigints,
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

echo "Optimization level => no optimization: ", not defined(release), " | release: ", defined(release), " | danger: ", defined(danger)

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
  echo "-".repeat(157)

proc report(op, elliptic: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<40} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<40} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixEllipticDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curveName = $Curve(instantiated[1][1][1].intVal)
  name.add "[" & fieldName & "[" & curveName & "]]"
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

  report(op, fixEllipticDisplay(T), start, stop, startClk, stopClk, iters)

proc addBench*(T: typedesc, iters: int) =
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  let Q = rng.random_unsafe(T)
  bench("EC Add G1", T, iters):
    r.sum(P, Q)

proc doublingBench*(T: typedesc, iters: int) =
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  bench("EC Double G1", T, iters):
    r.double(P)

proc scalarMulGenericBench*(T: typedesc, scratchSpaceSize: static int, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()

  var r {.noInit.}: T
  let P = rng.random_unsafe(T)

  let exponent = rng.random_unsafe(BigInt[bits])
  var exponentCanonical{.noInit.}: array[(bits+7) div 8, byte]
  exponentCanonical.exportRawUint(exponent, bigEndian)

  var scratchSpace{.noInit.}: array[scratchSpaceSize, T]

  bench("EC ScalarMul Generic G1 (scratchsize = " & $scratchSpaceSize & ')', T, iters):
    r = P
    r.scalarMulGeneric(exponentCanonical, scratchSpace)

# import ../tests/support/ec_reference_scalar_mult
#
# proc scalarMulUnsafeDoubleAddBench*(T: typedesc, iters: int) =
#   const bits = T.F.C.getCurveOrderBitwidth()
#
#   var r {.noInit.}: T
#   let P = rng.random_unsafe(T)
#
#   let exponent = rng.random_unsafe(BigInt[bits])
#   var exponentCanonical{.noInit.}: array[(bits+7) div 8, byte]
#   exponentCanonical.exportRawUint(exponent, bigEndian)
#
#   bench("EC ScalarMul G1 (unsafe DoubleAdd)", T, iters):
#     r = P
#     r.unsafe_ECmul_double_add(exponentCanonical)
