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
  ./bench_blueprint

export notes
proc separator*() = separator(165)

proc report(op, field: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<70} {field:<18} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<70} {field:<18} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Curve(instantiated[1][1].intVal) & "]"
  result = newLit name

template bench(op: string, T: typedesc, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixFieldDisplay(T), startTime, stopTime, startClk, stopClk, iters)

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

proc ccopyBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  bench("Conditional Copy", T, iters):
    r.ccopy(x, CtFalse)

proc div2Bench*(T: typedesc, iters: int) =
  var x = rng.random_unsafe(T)
  bench("Division by 2", T, iters):
    x.div2()

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
  bench("Inversion (constant-time default impl)", T, iters):
    r.inv(x)

proc invEuclidBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Inversion (constant-time Euclid)", T, iters):
    r.inv_euclid(x)

proc invPowFermatBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  const exponent = T.getInvModExponent()
  bench("Inversion (exponentiation p-2, Little Fermat)", T, iters):
    var r = x
    r.powUnsafeExponent(exponent)

proc invAddChainBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Inversion (addition chain)", T, iters):
    r.inv_addchain(x)

proc sqrtBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  bench("Square Root (constant-time default impl)", T, iters):
    var r = x
    discard r.sqrt()

proc sqrtP3mod4Bench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  bench("SquareRoot (p ≡ 3 (mod 4) exponentiation)", T, iters):
    r.invsqrt_p3mod4(x)
    r *= x

proc sqrtAddChainBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  bench("SquareRoot (addition chain)", T, iters):
    r.invsqrt_addchain(x)
    r *= x

proc sqrtTonelliBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  bench("SquareRoot (constant-time Tonelli-Shanks exponentiation)", T, iters):
    r.invsqrt_tonelli_shanks(x, useAddChain = false)
    r *= x

proc sqrtTonelliAddChainBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  bench("SquareRoot (constant-time Tonelli-Shanks addchain)", T, iters):
    r.invsqrt_tonelli_shanks(x, useAddChain = true)
    r *= x

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
