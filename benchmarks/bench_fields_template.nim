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
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/named/zoo_square_roots,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

export notes, abstractions
proc separator*() = separator(165)
proc smallSeparator*() = separator(8)

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
  var name = $instantiated[1][0] # 𝔽p
  name.add "[" & $Algebra(instantiated[1][1].intVal) & "]"
  result = newLit name

template bench(op: string, T: typedesc, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixFieldDisplay(T), startTime, stopTime, startClk, stopClk, iters)

func random_unsafe(rng: var RngState, a: var FpDbl) =
  ## Initialize a standalone Double-Width field element
  ## we don't reduce it modulo p², this is only used for benchmark
  let aHi = rng.random_unsafe(Fp[FpDbl.Name])
  let aLo = rng.random_unsafe(Fp[FpDbl.Name])
  for i in 0 ..< aLo.mres.limbs.len:
    a.limbs2x[i] = aLo.mres.limbs[i]
  for i in 0 ..< aHi.mres.limbs.len:
    a.limbs2x[aLo.mres.limbs.len+i] = aHi.mres.limbs[i]

func random_unsafe(rng: var RngState, a: var ExtensionField2x) =
  for i in 0 ..< a.coords.len:
    rng.random_unsafe(a.coords[i])

proc addBench*(T: typedesc, iters: int) {.noinline.} =
  var x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  bench("Addition", T, iters):
    x += y

proc add10Bench*(T: typedesc, iters: int) {.noinline.} =
  var xs: array[10, T]
  for x in xs.mitems():
    x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  bench("Additions (10)", T, iters):
    staticFor i, 0, 10:
      xs[i] += y

proc subBench*(T: typedesc, iters: int) {.noinline.} =
  var x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  preventOptimAway(x)
  bench("Substraction", T, iters):
    x -= y

proc negBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T)
  bench("Negation", T, iters):
    r.neg(x)

proc ccopyBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T)
  bench("Conditional Copy", T, iters):
    r.ccopy(x, CtFalse)

proc div2Bench*(T: typedesc, iters: int) {.noinline.} =
  var x = rng.random_unsafe(T)
  bench("Division by 2", T, iters):
    x.div2()

proc mulBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Multiplication", T, iters):
    r.prod(x, y)

proc sqrBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Squaring", T, iters):
    r.square(x)

proc mul2xUnrBench*(T: typedesc, iters: int) {.noinline.} =
  var r: doublePrec(T)
  let x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Multiplication 2x unreduced", T, iters):
    r.prod2x(x, y)

proc sqr2xUnrBench*(T: typedesc, iters: int) {.noinline.} =
  var r: doublePrec(T)
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Squaring 2x unreduced", T, iters):
    r.square2x(x)

proc rdc2xBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  var t: doublePrec(T)
  rng.random_unsafe(t)
  preventOptimAway(r)
  bench("Redc 2x", T, iters):
    r.redc2x(t)

proc sumprodBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let a = rng.random_unsafe(T)
  let b = rng.random_unsafe(T)
  let u = rng.random_unsafe(T)
  let v = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Linear combination", T, iters):
    r.sumprod([a, b], [u, v])

proc toBigBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T.getBigInt()
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("BigInt <- field conversion", T, iters):
    r.fromField(x)

proc toFieldBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T.getBigInt())
  preventOptimAway(r)
  bench("BigInt -> field conversion", T, iters):
    r.fromBig(x)

proc invBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Inversion (constant-time)", T, iters):
    r.inv(x)

proc invVartimeBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Inversion (variable-time)", T, iters):
    r.inv_vartime(x)

proc isSquareBench*(T: typedesc, iters: int) {.noinline.} =
  let x = rng.random_unsafe(T)
  bench("isSquare (constant-time)", T, iters):
    let qrt = x.isSquare()

proc sqrtBench*(T: typedesc, iters: int) {.noinline.} =
  let x = rng.random_unsafe(T)

  const algoType = block:
    when T.Name.has_P_3mod4_primeModulus():
      "p ≡ 3 (mod 4)"
    elif T.Name.has_P_5mod8_primeModulus():
      "p ≡ 5 (mod 8)"
    else:
      "Tonelli-Shanks"
  const addchain = block:
    when T.Name.hasSqrtAddchain() or T.Name.hasTonelliShanksAddchain():
      "with addition chain"
    else:
      "without addition chain"
  const desc = "Square Root (constant-time " & algoType & " " & addchain & ")"
  bench(desc, T, iters):
    var r = x
    discard r.sqrt_if_square()

proc sqrtRatioBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let u = rng.random_unsafe(T)
  let v = rng.random_unsafe(T)
  bench("Fused SquareRoot+Division+isSquare sqrt(u/v)", T, iters):
    let isSquare = r.sqrt_ratio_if_square(u, v)

proc sqrtVartimeBench*(T: typedesc, iters: int) {.noinline.} =
  let x = rng.random_unsafe(T)

  const algoType = block:
    when T.Name.has_P_3mod4_primeModulus():
      "p ≡ 3 (mod 4)"
    elif T.Name.has_P_5mod8_primeModulus():
      "p ≡ 5 (mod 8)"
    else:
      "Tonelli-Shanks"
  const addchain = block:
    when T.Name.hasSqrtAddchain() or T.Name.hasTonelliShanksAddchain():
      "with addition chain"
    else:
      "without addition chain"
  const desc = "Square Root (vartime " & algoType & " " & addchain & ")"
  bench(desc, T, iters):
    var r = x
    discard r.sqrt_if_square_vartime()

proc sqrtRatioVartimeBench*(T: typedesc, iters: int) {.noinline.} =
  var r: T
  let u = rng.random_unsafe(T)
  let v = rng.random_unsafe(T)
  bench("Fused SquareRoot+Division+isSquare sqrt_vartime(u/v)", T, iters):
    let isSquare = r.sqrt_ratio_if_square_vartime(u, v)

proc powBench*(T: typedesc, iters: int) {.noinline.} =
  let x = rng.random_unsafe(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r = x
  bench("Exp curve order (constant-time) - " & $exponent.bits & "-bit", T, iters):
    r.pow(exponent)

proc powVartimeBench*(T: typedesc, iters: int) {.noinline.} =
  let x = rng.random_unsafe(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r = x
  bench("Exp by curve order (vartime) - " & $exponent.bits & "-bit", T, iters):
    r.pow_vartime(exponent)
