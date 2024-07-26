# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Summary of the performance of a curve
#
# ############################################################

import
  # Internals
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/ec_twistededwards,
  constantine/named/zoo_generators,
  constantine/math/io/io_fields,
  constantine/hash_to_curve/hash_to_curve,
  constantine/serialization/codecs_banderwagon,
  # Helpers
  ./bench_blueprint

const Iters = 10000

proc separator*() = separator(152)

proc report(op, domain: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {domain:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {domain:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixEllipticDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curveName = $Algebra(instantiated[1][1][1].intVal)
  name.add "[" & fieldName & "[" & curveName & "]]"
  result = newLit name

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Algebra(instantiated[1][1].intVal) & "]"
  result = newLit name

func fixDisplay(T: typedesc): string =
  when T is (EC_TwEdw_Prj or EC_TwEdw_Aff):
    fixEllipticDisplay(T)
  elif T is (Fp or Fp2 or Fp4 or Fp6 or Fp12):
    fixFieldDisplay(T)
  else:
    $T

func fixDisplay(T: Algebra): string =
  $T

template bench(op: string, T: typed, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixDisplay(T), startTime, stopTime, startClk, stopClk, iters)

proc equalityBench*(T: typedesc, iters: int) =
  when T is EC_TwEdw_Prj[Fp[Banderwagon]]:
    let P = Banderwagon.getGenerator()
    let Q = Banderwagon.getGenerator()
  else:
    var P, Q: EC_TwEdw_Prj[Fp[Banderwagon]]
    P.setGenerator()
    Q.setGenerator()
  bench("Banderwagon Equality ", T, iters):
    assert (P == Q).bool()


proc serializeBench*(T: typedesc, iters: int) =
  var bytes: array[32, byte]
  var P: EC_TwEdw_Prj[Fp[Banderwagon]]
  P.setGenerator()
  for i in 0 ..< 9:
    P.double()
  bench("Banderwagon Serialization", T, iters):
    discard bytes.serialize(P)

proc deserializeBench_vartime*(T: typedesc, iters: int) =
  var bytes: array[32, byte]
  var P: EC_TwEdw_Prj[Fp[Banderwagon]]
  P.setGenerator()
  for i in 0 ..< 6:
    P.double()
  discard bytes.serialize(P)

  var Q: EC_TwEdw_Aff[Fp[Banderwagon]]
  bench("Banderwagon Deserialization (vartime)", T, iters):
    discard Q.deserialize_vartime(bytes)

proc deserializeBenchUnchecked_vartime*(T: typedesc, iters: int) =
  var bytes: array[32, byte]
  var P: EC_TwEdw_Prj[Fp[Banderwagon]]
  P.setGenerator()
  for i in 0 ..< 6:
    P.double()
  discard bytes.serialize(P)

  var Q: EC_TwEdw_Aff[Fp[Banderwagon]]
  bench("Banderwagon Deserialization Unchecked (vartime)", T, iters):
    discard Q.deserialize_unchecked_vartime(bytes)

proc serializeUncompressedBench*(T: typedesc, iters: int) =
  var bytes: array[64, byte]
  var P: EC_TwEdw_Prj[Fp[Banderwagon]]
  P.setGenerator()
  for i in 0 ..< 6:
    P.double()

  var Q: EC_TwEdw_Aff[Fp[Banderwagon]]
  Q.affine(P)
  bench("Banderwagon Serialization Uncompressed from affine point", T, iters):
    discard bytes.serializeUncompressed(Q)

proc deserializeUncompressedBench*(T: typedesc, iters: int) =
  var bytes: array[64, byte]
  var P: EC_TwEdw_Prj[Fp[Banderwagon]]
  P.setGenerator()
  for i in 0 ..< 6:
    P.double()

  var Q: EC_TwEdw_Aff[Fp[Banderwagon]]
  Q.affine(P)
  discard bytes.serializeUncompressed(Q)
  bench("Banderwagon Deserialization Uncompressed", T, iters):
    discard Q.deserializeUncompressed(bytes)

proc deserializeUncompressedBenchUnchecked*(T: typedesc, iters: int) =
  var bytes: array[64, byte]
  var P: EC_TwEdw_Prj[Fp[Banderwagon]]
  P.setGenerator()
  for i in 0 ..< 6:
    P.double()

  var Q: EC_TwEdw_Aff[Fp[Banderwagon]]
  Q.affine(P)
  discard bytes.serializeUncompressed(Q)
  bench("Banderwagon Deserialization Uncompressed Unchecked", T, iters):
    discard Q.deserializeUncompressed_unchecked(bytes)


proc main() =
  equalityBench(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)
  separator()
  serializeBench(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)
  separator()
  deserializeBench_vartime(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)
  deserializeBenchUnchecked_vartime(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)
  separator()
  serializeUncompressedBench(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)
  deserializeUncompressedBench(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)
  deserializeUncompressedBenchUnchecked(EC_TwEdw_Prj[Fp[Banderwagon]], Iters)

main()
notes()
