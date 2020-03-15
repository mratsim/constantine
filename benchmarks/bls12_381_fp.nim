# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#           Benchmark of modular exponentiation
#
# ############################################################

# 2 implementations are available
# - 1 is constant time
# - 1 exposes the exponent bits to:
#   timing attack,
#   memory access analysis,
#   power analysis (i.e. oscilloscopes on embedded)
#   It is suitable for public exponents for example
#   to compute modular inversion via the Fermat method

import
  ../constantine/config/[common, curves],
  ../constantine/arithmetic/[bigints_checked, finite_fields],
  ../constantine/io/[io_bigints, io_fields],
  random, std/monotimes, times, strformat,
  ./timers

const Iters = 1_000_000
const InvIters = 1000

randomize(1234)

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
  echo &"\n\nWarmup: {stop - start:>4.4f} s, result {foo} (displayed to avoid compiler optimizing warmup away)\n"

warmup()

echo "\n⚠️ Measurements are approximate and use the CPU nominal clock: Turbo-Boost and overclocking will skew them."
echo "==========================================================================================================\n"

proc report(op, field: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  echo &"{op:<15} {field:<15} {inNanoseconds((stop-start) div iters):>9} ns {(stopClk - startClk) div iters:>9} cycles"

proc addBench() =
  var x, y: Fp[BLS12_381]
  # BN254 field modulus
  x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
  # BLS12-381 prime - 2
  y.fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< Iters:
    x += y
  let stopClk = getTicks()
  let stop = getMonotime()
  report("Addition", "Fp[BLS12_381]", start, stop, startClk, stopClk, Iters)


addBench()

proc subBench() =
  var x, y: Fp[BLS12_381]
  # BN254 field modulus
  x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
  # BLS12-381 prime - 2
  y.fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< Iters:
    x -= y
  let stopClk = getTicks()
  let stop = getMonotime()
  report("Substraction", "Fp[BLS12_381]", start, stop, startClk, stopClk, Iters)

subBench()

proc negBench() =
  var r, x: Fp[BLS12_381]
  # BN254 field modulus
  x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")

  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< Iters:
    r.neg(x)
  let stopClk = getTicks()
  let stop = getMonotime()
  report("Negation", "Fp[BLS12_381]", start, stop, startClk, stopClk, Iters)

negBench()

proc mulBench() =
  var r, x, y: Fp[BLS12_381]
  # BN254 field modulus
  x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
  # BLS12-381 prime - 2
  y.fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< Iters:
    r.prod(x, y)
  let stopClk = getTicks()
  let stop = getMonotime()
  report("Multiplication", "Fp[BLS12_381]", start, stop, startClk, stopClk, Iters)

mulBench()

proc sqrBench() =
  var r, x: Fp[BLS12_381]
  # BN254 field modulus
  x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")

  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< Iters:
    r.square(x)
  let stopClk = getTicks()
  let stop = getMonotime()
  report("Squaring", "Fp[BLS12_381]", start, stop, startClk, stopClk, Iters)

sqrBench()

proc invBench() =
  # TODO: having x on the stack triggers stack smashing detection. To be investigated
  var x: ref Fp[BLS12_381]
  new x
  # BN254 field modulus
  x[].fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")

  let start = getMonotime()
  let startClk = getTicks()
  for _ in 0 ..< InvIters:
    # Note: we don't copy the original x so x is alterning between x and x^-1
    inv(x[])
  let stopClk = getTicks()
  let stop = getMonotime()
  report("Inversion", "Fp[BLS12_381]", start, stop, startClk, stopClk, InvIters)

invBench()
