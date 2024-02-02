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
  ../constantine/platforms/abstractions,
  ../constantine/math/config/curves,
  ../constantine/math/[arithmetic, extension_fields],
  ../constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_scalar_mul, ec_endomorphism_accel,
    ec_twistededwards_affine,
    ec_twistededwards_projective],
  ../constantine/math/constants/zoo_generators,
  ../constantine/math/pairings/[
    cyclotomic_subgroups,
    pairings_bls12,
    pairings_bn
  ],
  ../constantine/math/io/io_fields,
  ../constantine/math/constants/zoo_pairings,
  ../constantine/hashes,
  ../constantine/hash_to_curve/hash_to_curve,
  ../constantine/serialization/[
    codecs_status_codes, 
    codecs_banderwagon
  ],
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_blueprint

export
  ec_shortweierstrass_projective,
  ec_shortweierstrass_jacobian

export abstractions # generic sandwich on SecretBool and SecretBool in Jacobian sum
export zoo_pairings # generic sandwich https://github.com/nim-lang/Nim/issues/11225
export notes

type
  Prj* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  Aff* = ECP_TwEdwards_Prj[Fp[Banderwagon]]

const Iters = 10000

proc separator*() = separator(152)

proc report(op, domain: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<35} {domain:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<35} {domain:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixEllipticDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curveName = $Curve(instantiated[1][1][1].intVal)
  name.add "[" & fieldName & "[" & curveName & "]]"
  result = newLit name

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Curve(instantiated[1][1].intVal) & "]"
  result = newLit name

func fixDisplay(T: typedesc): string =
  when T is (ECP_ShortW_Prj or ECP_ShortW_Jac or ECP_ShortW_Aff):
    fixEllipticDisplay(T)
  elif T is (Fp or Fp2 or Fp4 or Fp6 or Fp12):
    fixFieldDisplay(T)
  else:
    $T

func fixDisplay(T: Curve): string =
  $T

template bench(op: string, T: typed, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixDisplay(T), startTime, stopTime, startClk, stopClk, iters)

# proc equalityBench*(T: typedesc, iters: int) =
#   when T is Aff:
#     let P = Banderwagon.getGenerator()
#     let Q = Banderwagon.getGenerator()
#   else:
#     var P, Q: Prj
#     P.fromAffine(Banderwagon.getGenerator())
#     Q.fromAffine(Banderwagon.getGenerator())
#   bench("Banderwagon Equality ", T, iters):
#     assert (P == Q).bool()



proc serializaBench*(T: typedesc, iters: int) =
  var bytes: array[32, byte]
  var P: Prj
  P.fromAffine(Banderwagon.getGenerator())
  for i in 0 ..< 9:
    P.double()
  bench("Banderwagon Serialization", T, iters):
    discard bytes.serialize(P)

proc deserializeBench*(T: typedesc, iters: int) =
  var bytes: array[32, byte]
  var P: Prj
  P.fromAffine(Banderwagon.getGenerator())
  for i in 0 ..< 6:
    P.double()
  discard bytes.serialize(P)
  bench("Banderwagon Deserialization", T, iters):
    discard P.deserialize(bytes)


proc main() =
  # separator()
  # equalityBench(Aff, Iters)
  # equalityBench(Prj, Iters)
  separator()
  serializaBench(Prj, Iters)
  deserializeBench(Prj, Iters)

main()
notes()