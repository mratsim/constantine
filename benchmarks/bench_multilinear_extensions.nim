# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/boolean_hypercube/multilinear_extensions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/platforms/static_for,
  # Helpers
  helpers/prng_unsafe,
  benchmarks/bench_blueprint,
  std/macros

var rng*: RngState
let seed = 1234
rng.seed(seed)
echo "bench multilinear_extensions xoshiro512** seed: ", seed

proc separator*() = separator(155)

proc report(op, field: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {field:<18} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {field:<18} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

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

proc bench_mle(F: typedesc, num_vars: int) =
  var evals = newSeq[F](1 shl num_vars)
  for eval in evals.mitems():
    eval = rng.random_unsafe(F)

  let mle = MultilinearExtension[F].new(num_vars, evals)

  var coords = newSeq[F](num_vars)
  for coord in coords.mitems():
    coord = rng.random_unsafe(F)

  var r: F
  if num_vars <= 13:
    bench("Multilinear Extension " & $num_vars & " variables: Reference EvaluateAt", F, 100):
      r.evalMultilinearExtensionAt_reference(mle, coords)

  block:
    bench("Multilinear Extension " & $num_vars & " variables: Optimized EvaluateAt", F, 100):
      r.evalMultilinearExtensionAt(mle, coords)

const Curves = [BN254_Snarks, BLS12_381]

separator()
separator()
staticFor i, 0, Curves.len:
  const curve = Curves[i]
  for num_vars in countup(9, 19, 2):
    bench_mle(Fr[curve], num_vars)
    separator()
  separator()
