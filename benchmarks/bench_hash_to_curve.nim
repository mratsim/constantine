# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/[common, curves, type_bigint, type_ff],
  ../constantine/[towers, hashes],
  ../constantine/io/[io_bigints, io_ec],
  ../constantine/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective],
  ../constantine/hash_to_curve/hash_to_curve,
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(132)

proc report(op, curve: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<40} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<40} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, C: static Curve, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, $C, startTime, stopTime, startClk, stopClk, iters)

proc bench_BLS12_381_hash_to_G2(iters: int) =
  const dst = "BLS_SIG_BLS12381G2-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"

  var P: ECP_ShortW_Prj[Fp2[BLS12_381], G2]

  bench("Hash to G2 (Draft #11)", BLS12_381, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc bench_BLS12_381_proj_aff_conversion(iters: int) =
  const dst = "BLS_SIG_BLS12381G2-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"

  var P: ECP_ShortW_Prj[Fp2[BLS12_381], G2]
  var Paff: ECP_ShortW_Aff[Fp2[BLS12_381], G2]

  sha256.hashToCurve(
    k = 128,
    output = P,
    augmentation = "",
    message = msg,
    domainSepTag = dst
  )

  bench("Proj->Affine conversion (for pairing)", BLS12_381, iters):
    Paff.affine(P)

const Iters = 1000

proc main() =
  separator()
  bench_BLS12_381_hash_to_G2(Iters)
  bench_BLS12_381_proj_aff_conversion(Iters)
  separator()

main()
notes()
