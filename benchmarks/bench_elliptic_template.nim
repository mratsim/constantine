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
  ../constantine/config/[curves, common],
  ../constantine/arithmetic,
  ../constantine/io/io_bigints,
  ../constantine/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_projective, ec_scalar_mul, ec_endomorphism_accel],
  # Helpers
  ../helpers/[prng_unsafe, static_for],
  ./platforms,
  # Standard library
  std/[monotimes, times, strformat, strutils, macros],
  # Reference unsafe scalar multiplication
  ../tests/support/ec_reference_scalar_mult

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
echo "  inline assembly: ", UseASM_X86_64

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
  echo "-".repeat(177)

proc report(op, elliptic: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

proc notes*() =
  echo "Notes:"
  echo "  - Compilers:"
  echo "    Compilers are severely limited on multiprecision arithmetic."
  echo "    Constantine compile-time assembler is used by default (nimble bench_fp)."
  echo "    GCC is significantly slower than Clang on multiprecision arithmetic due to catastrophic handling of carries."
  echo "    GCC also seems to have issues with large temporaries and register spilling."
  echo "    This is somewhat alleviated by Constantine compile-time assembler."
  echo "    Bench on specific compiler with assembler: \"nimble bench_ec_g1_gcc\" or \"nimble bench_ec_g1_clang\"."
  echo "    Bench on specific compiler with assembler: \"nimble bench_ec_g1_gcc_noasm\" or \"nimble bench_ec_g1_clang_noasm\"."
  echo "  - The simplest operations might be optimized away by the compiler."
  echo "  - Fast Squaring and Fast Multiplication are possible if there are spare bits in the prime representation (i.e. the prime uses 254 bits out of 256 bits)"

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
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  let Q = rng.random_unsafe(T)
  bench("EC Add " & G1_or_G2, T, iters):
    r.sum(P, Q)

proc mixedAddBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  let Q = rng.random_unsafe(T)
  var Qaff: ECP_ShortW_Aff[T.F, T.Tw]
  Qaff.affineFromProjective(Q)
  bench("EC Mixed Addition " & G1_or_G2, T, iters):
    r.madd(P, Qaff)

proc doublingBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  bench("EC Double " & G1_or_G2, T, iters):
    r.double(P)

proc affFromProjBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: ECP_ShortW_Aff[T.F, T.Tw]
  let P = rng.random_unsafe(T)
  bench("EC Projective to Affine " & G1_or_G2, T, iters):
    r.affineFromProjective(P)

proc affFromJacBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: ECP_ShortW_Aff[T.F, T.Tw]
  let P = rng.random_unsafe(T)
  bench("EC Jacobian to Affine " & G1_or_G2, T, iters):
    r.affineFromJacobian(P)

proc scalarMulGenericBench*(T: typedesc, window: static int, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul Generic " & G1_or_G2 & " (window = " & $window & ", scratchsize = " & $(1 shl window) & ')', T, iters):
    r = P
    r.scalarMulGeneric(exponent, window)

proc scalarMulEndo*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & G1_or_G2 & " (endomorphism accelerated)", T, iters):
    r = P
    r.scalarMulEndo(exponent)

proc scalarMulEndoWindow*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul Window-2 " & G1_or_G2 & " (endomorphism accelerated)", T, iters):
    r = P
    when T.F is Fp:
      r.scalarMulGLV_m2w2(exponent)
    else:
      {.error: "Not implemented".}

proc scalarMulUnsafeDoubleAddBench*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & G1_or_G2 & " (unsafe reference DoubleAdd)", T, iters):
    r = P
    r.unsafe_ECmul_double_add(exponent)
