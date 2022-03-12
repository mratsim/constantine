# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../src/constantine/blssig_pop_on_bls12381_g2,
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

template bench(op: string, curve: string, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, curve, startTime, stopTime, startClk, stopClk, iters)

proc benchDeserPubkey*(iters: int) =
  var seckey: array[32, byte]
  for i in 1 ..< 32:
    seckey[i] = byte 42
  var
    sk{.noInit.}: SecretKey
    pk{.noInit.}: PublicKey
    pk_comp{.noInit.}: array[48, byte]

  let ok = sk.deserialize_secret_key(seckey)
  doAssert ok == cttBLS_Success
  let ok2 = pk.derive_public_key(sk)
  doAssert ok2 == cttBLS_Success

  # Serialize compressed
  let ok3 = pk_comp.serialize_public_key_compressed(pk)
  doAssert ok3 == cttBLS_Success

  var pk2{.noInit.}: PublicKey

  bench("Pubkey deserialization (full checks)", "BLS12_381 G1", iters):
    let status = pk2.deserialize_public_key_compressed(pk_comp)

proc benchDeserPubkeyUnchecked*(iters: int) =
  var seckey: array[32, byte]
  for i in 1 ..< 32:
    seckey[i] = byte 42
  var
    sk{.noInit.}: SecretKey
    pk{.noInit.}: PublicKey
    pk_comp{.noInit.}: array[48, byte]

  let ok = sk.deserialize_secret_key(seckey)
  doAssert ok == cttBLS_Success
  let ok2 = pk.derive_public_key(sk)
  doAssert ok2 == cttBLS_Success

  # Serialize compressed
  let ok3 = pk_comp.serialize_public_key_compressed(pk)
  doAssert ok3 == cttBLS_Success

  var pk2{.noInit.}: PublicKey

  bench("Pubkey deserialization (skip checks)", "BLS12_381 G1", iters):
    let status = pk2.deserialize_public_key_compressed_unchecked(pk_comp)

proc benchDeserSig*(iters: int) =
  var seckey: array[32, byte]
  for i in 1 ..< 32:
    seckey[i] = byte 42
  const msg = "abcdef0123456789"

  var
    sk{.noInit.}: SecretKey
    pk{.noInit.}: PublicKey
    sig_comp{.noInit.}: array[96, byte]
    sig {.noInit.}: Signature

  let ok = sk.deserialize_secret_key(seckey)
  doAssert ok == cttBLS_Success
  let ok2 = pk.derive_public_key(sk)
  doAssert ok2 == cttBLS_Success

  let status = sig.sign(sk, msg)
  doAssert status == cttBLS_Success

  # Serialize compressed
  let ok3 = sig_comp.serialize_signature_compressed(sig)
  doAssert ok3 == cttBLS_Success

  var sig2{.noInit.}: Signature

  bench("Signature deserialization (full checks)", "BLS12_381 G2", iters):
    let status = sig2.deserialize_signature_compressed(sig_comp)

proc benchDeserSigUnchecked*(iters: int) =
  var seckey: array[32, byte]
  for i in 1 ..< 32:
    seckey[i] = byte 42
  const msg = "abcdef0123456789"

  var
    sk{.noInit.}: SecretKey
    pk{.noInit.}: PublicKey
    sig_comp{.noInit.}: array[96, byte]
    sig {.noInit.}: Signature

  let ok = sk.deserialize_secret_key(seckey)
  doAssert ok == cttBLS_Success
  let ok2 = pk.derive_public_key(sk)
  doAssert ok2 == cttBLS_Success

  let status = sig.sign(sk, msg)
  doAssert status == cttBLS_Success

  # Serialize compressed
  let ok3 = sig_comp.serialize_signature_compressed(sig)
  doAssert ok3 == cttBLS_Success

  var sig2{.noInit.}: Signature

  bench("Signature deserialization (skip checks)", "BLS12_381 G2", iters):
    let status = sig2.deserialize_signature_compressed_unchecked(sig_comp)

proc benchSign*(iters: int) =
  var seckey: array[32, byte]
  for i in 1 ..< 32:
    seckey[i] = byte 42
  let msg = "Mr F was here"

  var pk: PublicKey
  var sk: SecretKey
  var sig: Signature

  let ok = sk.deserialize_secret_key(seckey)
  doAssert ok == cttBLS_Success

  bench("BLS signature", "BLS12_381 G2", iters):
    let status = sig.sign(sk, msg)
    doAssert status == cttBLS_Success


proc benchVerify*(iters: int) =
  var seckey: array[32, byte]
  for i in 1 ..< 32:
    seckey[i] = byte 42
  let msg = "Mr F was here"

  var pk: PublicKey
  var sk: SecretKey
  var sig: Signature

  let ok = sk.deserialize_secret_key(seckey)
  doAssert ok == cttBLS_Success

  let ok2 = sig.sign(sk, msg)

  let ok3 = pk.derive_public_key(sk)
  doAssert ok3 == cttBLS_Success

  bench("BLS verification", "BLS12_381", iters):
    let valid = pk.verify(msg, sig)

const Iters = 1000

proc main() =
  separator()
  benchDeserPubkey(Iters)
  benchDeserPubkeyUnchecked(Iters)
  benchDeserSig(Iters)
  benchDeserSigUnchecked(Iters)
  separator()
  benchSign(Iters)
  benchVerify(Iters)
  separator()

main()
notes()
