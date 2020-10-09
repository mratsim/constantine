# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark of pairings
#
# ############################################################

import
  # Internals
  ../constantine/config/[curves, common],
  ../constantine/arithmetic,
  ../constantine/io/io_bigints,
  ../constantine/towers,
  ../constantine/elliptic/[ec_shortweierstrass_projective, ec_shortweierstrass_affine],
  ../constantine/hash_to_curve/cofactors,
  ../constantine/pairing/[
    cyclotomic_fp12,
    lines_projective,
    mul_fp12_by_lines,
    pairing_bls12,
    pairing_bn
  ],
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

proc report(op, curve: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

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

template bench(op: string, C: static Curve, iters: int, body: untyped): untyped =
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

  report(op, $C, start, stop, startClk, stopClk, iters)

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactorReference()

proc lineDoubleBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
  var Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  Paff.affineFromProjective(P)
  bench("Line double", C, iters):
    line.line_double(T, Paff)

proc lineAddBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  var
    Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
    Qaff: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  bench("Line add", C, iters):
    line.line_add(T, Qaff, Paff)

proc mulFp12byLine_xyz000_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
  var Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  Paff.affineFromProjective(P)

  line.line_double(T, Paff)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xyz000", C, iters):
    f.mul_sparse_by_line_xyz000(line)

proc mulFp12byLine_xy000z_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
  var Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  Paff.affineFromProjective(P)

  line.line_double(T, Paff)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xy000z", C, iters):
    f.mul_sparse_by_line_xy000z(line)

proc millerLoopBLS12Bench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  var
    Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
    Qaff: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)

  var f: Fp12[C]

  bench("Miller Loop BLS12", C, iters):
    f.millerLoopGenericBLS12(Paff, Qaff)

proc millerLoopBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  var
    Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
    Qaff: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)

  var f: Fp12[C]

  bench("Miller Loop BN", C, iters):
    f.millerLoopGenericBN(Paff, Qaff)

proc finalExpEasyBench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  bench("Final Exponentiation Easy", C, iters):
    r.finalExpEasy()

proc finalExpHardBLS12Bench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  r.finalExpEasy()
  bench("Final Exponentiation Hard BLS12", C, iters):
    r.finalExpHard_BLS12()

proc finalExpHardBNBench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  r.finalExpEasy()
  bench("Final Exponentiation Hard BN", C, iters):
    r.finalExpHard_BN()

proc finalExpBLS12Bench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  bench("Final Exponentiation BLS12", C, iters):
    r.finalExpEasy()
    r.finalExpHard_BLS12()

proc finalExpBNBench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  bench("Final Exponentiation BN", C, iters):
    r.finalExpEasy()
    r.finalExpHard_BN()

proc pairingBLS12Bench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])

  var f: Fp12[C]

  bench("Pairing BLS12", C, iters):
    f.pairing_bls12(P, Q)

proc pairingBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])

  var f: Fp12[C]

  bench("Pairing BN", C, iters):
    f.pairing_bn(P, Q)
