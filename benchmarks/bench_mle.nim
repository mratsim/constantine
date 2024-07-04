import
  constantine/boolean_hypercube/multilinear_extensions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  helpers/prng_unsafe,
  benchmarks/bench_blueprint,
  std/macros

var rng*: RngState
let seed = 1234
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

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

func toFp[N: static int](a: array[N, SomeUnsignedInt], Name: static Algebra): array[N, Fp[Name]] =
  for i in 0 ..< N:
    result[i] = Fp[Name].fromUint(a[i])

proc bench_thaler() =
  var evals = [uint32 1, 2, 1, 4].toFp(F5)
  let mle = MultilinearExtension[Fp[F5]].new(2, evals)

  var r: Fp[F5]
  bench("Multilinear Extension: Evaluate", Fp[F5], 100):
    r.evalMultilinearExtensionAt_reference(mle, [Fp[F5].fromUint(0'u), Fp[F5].fromUint(0'u)])

proc bench_arkworks(num_vars: int) =
  var evals = newSeq[Fr[BLS12_381]](1 shl num_vars)
  for eval in evals.mitems():
    eval = rng.random_unsafe(Fr[BLS12_381])

  let mle = MultilinearExtension[Fr[BLS12_381]].new(num_vars, evals)

  var coords = newSeq[Fr[BLS12_381]](num_vars)
  for coord in coords.mitems():
    coord = rng.random_unsafe(Fr[BLS12_381])

  var r: Fr[BLS12_381]
  bench("Multilinear Extension: Evaluate/" & $num_vars, Fr[BLS12_381], 100):
    r.evalMultilinearExtensionAt_reference(mle, coords)

bench_thaler()
bench_arkworks(10)
bench_arkworks(11)
bench_arkworks(12)
