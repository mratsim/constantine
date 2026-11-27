# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark of binary fields
#
# ############################################################
#
# The field operations are inlined, so each benchmark is a dependency chain
# (latency) or works over arrays (throughput), to keep the compiler
# from hoisting a loop-invariant operation out of the timed loop.

import
  # Internals
  constantine/platforms/abstractions,
  constantine/math/binary_fields,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator() = separator(132)

proc report(op, field: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds(stop-start).float64 / float64(iters)
  let throughput = 1e9 / ns
  when SupportsGetTicks:
    echo &"{op:<54} {field:<10} {throughput:>15.0f} ops/s {ns:>9.2f} ns/op {float64(stopClk - startClk) / float64(iters):>9.1f} CPU cycles (approx)"
  else:
    echo &"{op:<54} {field:<10} {throughput:>15.0f} ops/s {ns:>9.2f} ns/op"

template bench(op, field: string, iters: int, body: untyped): untyped =
  block:
    measure(iters, startTime, stopTime, startClk, stopClk, body)
    report(op, field, startTime, stopTime, startClk, stopClk, iters)

const Iters = 10_000_000
const N = 1024 # Array length for throughput

func checksum(x: GF2_64): uint64 = x.raw
func checksum(x: GF2_64x2): uint64 = x.c0.raw xor x.c1.raw

proc observe[T: GF2_64 or GF2_64x2](a, b: T) =
  ## Print values computed by the timed loops, after them,
  ## so that the compiler cannot remove those computations as dead code.
  ## Each benchmark below feeds its result into the next through `a` or `xs[0]`,
  ## so observing their final values keeps every timed loop live.
  echo &"  (checksum {checksum(a) xor checksum(b):016x}, keeps the timed results observable)"

proc benchK() =
  var a = rng.random_unsafe(GF2_64)
  let b = rng.random_unsafe(GF2_64)

  bench("Multiplication, latency", "𝔽₂⁶⁴", Iters):
    a.prod(a, b)
  bench("Multiplication, latency, portable", "𝔽₂⁶⁴", Iters):
    a.prod_portable(a, b)
  bench("Squaring, latency", "𝔽₂⁶⁴", Iters):
    a.square()
  bench("Squaring, latency, portable", "𝔽₂⁶⁴", Iters):
    a.square_portable(a)
  bench("Inversion (constant-time)", "𝔽₂⁶⁴", Iters div 100):
    a.inv()

  var xs, ys: array[N, GF2_64]
  for i in 0 ..< N:
    xs[i] = rng.random_unsafe(GF2_64)
    ys[i] = rng.random_unsafe(GF2_64)
  var acc: GF2_64Dbl
  var t: GF2_64Dbl
  bench("Dot product, per term, unreduced accumulation", "𝔽₂⁶⁴", Iters div N):
    acc.setZero()
    for i in 0 ..< N:
      t.prod2x(xs[i], ys[i])
      acc += t
    xs[0].redc2x(acc)
  # Report per term
  echo &"  (per term: divide ns/op above by {N})"

  observe(a, xs[0])

proc benchE() =
  var a = rng.random_unsafe(GF2_64x2)
  let b = rng.random_unsafe(GF2_64x2)
  let k = rng.random_unsafe(GF2_64)

  bench("Multiplication, latency", "𝔽₂¹²⁸", Iters):
    a.prod(a, b)
  bench("Multiplication, latency, portable", "𝔽₂¹²⁸", Iters):
    a.prod_portable(a, b)
  bench("Squaring, latency", "𝔽₂¹²⁸", Iters):
    a.square()
  bench("Squaring, latency, portable", "𝔽₂¹²⁸", Iters):
    a.square_portable(a)
  bench("Multiplication by 𝔽₂⁶⁴, latency", "𝔽₂¹²⁸", Iters):
    a.prod(a, k)
  bench("Inversion (constant-time)", "𝔽₂¹²⁸", Iters div 100):
    a.inv()

  var xs, ys: array[N, GF2_64x2]
  for i in 0 ..< N:
    xs[i] = rng.random_unsafe(GF2_64x2)
    ys[i] = rng.random_unsafe(GF2_64x2)
  var ks: array[N, GF2_64]
  for i in 0 ..< N:
    ks[i] = rng.random_unsafe(GF2_64)
  var r: GF2_64x2
  bench(&"Dot product (sumprod), {N} terms", "𝔽₂¹²⁸", Iters div N):
    r.sumprod(xs, ys)
    xs[0] = r
  bench(&"Dot product (sumprod), {N} terms, portable", "𝔽₂¹²⁸", Iters div N):
    r.sumprod_portable(xs, ys)
    xs[0] = r
  bench(&"Dot product by 𝔽₂⁶⁴ (sumprod), {N} terms", "𝔽₂¹²⁸", Iters div N):
    r.sumprod(xs, ks)
    xs[0] = r

  observe(a, xs[0])

proc main() =
  separator()
  echo "Carry-less multiplication in hardware: ", hasClmulHardware()
  separator()
  benchK()
  separator()
  benchE()
  separator()

main()
notes()
