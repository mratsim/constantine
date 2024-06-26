# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/extension_fields,
  constantine/math/io/[io_bigints, io_ec],
  constantine/math/ec_shortweierstrass,
  constantine/hash_to_curve/hash_to_curve,
  constantine/hashes,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(132)

proc report(op, curve: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<40} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<40} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, Name: static Algebra, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, $Name, startTime, stopTime, startClk, stopClk, iters)

proc bench_BLS12_381_hash_to_G1(iters: int) =
  const dst = "BLS_SIG_BLS12381G1-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp[BLS12_381], G1]

  bench("Hash to G1 (SSWU method - Draft #14)", BLS12_381, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc bench_BLS12_381_hash_to_G2(iters: int) =
  const dst = "BLS_SIG_BLS12381G2-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp2[BLS12_381], G2]

  bench("Hash to G2 (SSWU method - Draft #14)", BLS12_381, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc bench_BLS12_381_hash_to_G1_SVDW(iters: int) =
  const dst = "BLS_SIG_BLS12381G1-SHA256-SVDW-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp[BLS12_381], G1]

  bench("Hash to G1 (SVDW method)", BLS12_381, iters):
    sha256.hashToCurve_svdw(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc bench_BLS12_381_hash_to_G2_SVDW(iters: int) =
  const dst = "BLS_SIG_BLS12381G2-SHA256-SVDW-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp2[BLS12_381], G2]

  bench("Hash to G2 (SVDW method)", BLS12_381, iters):
    sha256.hashToCurve_svdw(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc bench_BN254_Snarks_hash_to_G1(iters: int) =
  const dst = "BLS_SIG_BN254SNARKSG1-SHA256-SVDW-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp[BN254_Snarks], G1]

  bench("Hash to G1 (SVDW method)", BN254_Snarks, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc bench_BN254_Snarks_hash_to_G2(iters: int) =
  const dst = "BLS_SIG_BN254SNARKSG2-SHA256-SVDW-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp2[BN254_Snarks], G2]

  bench("Hash to G2 (SVDW method)", BN254_Snarks, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )


proc bench_BLS12_381_G1_jac_aff_conversion(iters: int) =
  const dst = "BLS_SIG_BLS12381G1-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp[BLS12_381], G1]
  var Paff: EC_ShortW_Aff[Fp[BLS12_381], G1]

  sha256.hashToCurve(
    k = 128,
    output = P,
    augmentation = "",
    message = msg,
    domainSepTag = dst
  )

  bench("G1 Jac->Affine conversion (for pairing)", BLS12_381, iters):
    Paff.affine(P)

proc bench_BLS12_381_G2_jac_aff_conversion(iters: int) =
  const dst = "BLS_SIG_BLS12381G2-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"

  var P: EC_ShortW_Jac[Fp2[BLS12_381], G2]
  var Paff: EC_ShortW_Aff[Fp2[BLS12_381], G2]

  sha256.hashToCurve(
    k = 128,
    output = P,
    augmentation = "",
    message = msg,
    domainSepTag = dst
  )

  bench("G2 Jac->Affine conversion (for pairing)", BLS12_381, iters):
    Paff.affine(P)

const Iters = 1000

proc main() =
  separator()
  bench_BLS12_381_hash_to_G1(Iters)
  bench_BLS12_381_hash_to_G2(Iters)
  bench_BLS12_381_hash_to_G1_SVDW(Iters)
  bench_BLS12_381_hash_to_G2_SVDW(Iters)
  bench_BN254_Snarks_hash_to_G1(Iters)
  bench_BN254_Snarks_hash_to_G2(Iters)
  bench_BLS12_381_G1_jac_aff_conversion(Iters)
  bench_BLS12_381_G2_jac_aff_conversion(Iters)
  separator()

main()
notes()
