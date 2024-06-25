# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/[
    ethereum_bls_signatures_parallel,
    ethereum_eip2333_bls12381_key_derivation],
  constantine/math/arithmetic,
  constantine/threadpool/threadpool,
  # Std
  std/[os, cpuinfo],
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

proc separator*() = separator(180)

proc report(op, curve: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  let cycles = (stopClk - startClk) div iters
  when SupportsGetTicks:
    echo &"{op:<88} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {cycles:>9} CPU cycles (approx)"
  else:
    echo &"{op:<88} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, curve: string, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, curve, startTime, stopTime, startClk, stopClk, iters)

proc demoKeyGen(): tuple[seckey: SecretKey, pubkey: PublicKey] =
  # Don't do this at home, this is for benchmarking purposes
  # The RNG is NOT cryptographically secure
  # The API for keygen is not ready in ethereum_bls_signatures
  let ikm = rng.random_byte_seq(32)
  doAssert cast[ptr BigInt[255]](result.seckey.addr)[].derive_master_secretKey(ikm)
  result.pubkey.derive_pubkey(result.seckey)

proc benchDeserPubkey*(iters: int) =
  let (sk, pk) = demoKeyGen()
  var pk_comp{.noInit.}: array[48, byte]

  # Serialize compressed
  let status = pk_comp.serialize_pubkey_compressed(pk)
  doAssert status == cttCodecEcc_Success

  var pk2{.noInit.}: PublicKey

  bench("Pubkey deserialization (full checks)", "BLS12_381 G1", iters):
    let status = pk2.deserialize_pubkey_compressed(pk_comp)

proc benchDeserPubkeyUnchecked*(iters: int) =
  let (sk, pk) = demoKeyGen()
  var pk_comp{.noInit.}: array[48, byte]

  # Serialize compressed
  let status = pk_comp.serialize_pubkey_compressed(pk)
  doAssert status == cttCodecEcc_Success

  var pk2{.noInit.}: PublicKey

  bench("Pubkey deserialization (skip checks)", "BLS12_381 G1", iters):
    let status = pk2.deserialize_pubkey_compressed_unchecked(pk_comp)

proc benchDeserSig*(iters: int) =
  let (sk, pk) = demoKeyGen()
  const msg = "abcdef0123456789"

  var
    sig_comp{.noInit.}: array[96, byte]
    sig {.noInit.}: Signature

  sig.sign(sk, msg)

  # Serialize compressed
  let status = sig_comp.serialize_signature_compressed(sig)
  doAssert status == cttCodecEcc_Success

  var sig2{.noInit.}: Signature

  bench("Signature deserialization (full checks)", "BLS12_381 G2", iters):
    let status = sig2.deserialize_signature_compressed(sig_comp)

proc benchDeserSigUnchecked*(iters: int) =
  let (sk, pk) = demoKeyGen()
  const msg = "abcdef0123456789"

  var
    sig_comp{.noInit.}: array[96, byte]
    sig {.noInit.}: Signature

  sig.sign(sk, msg)

  # Serialize compressed
  let status = sig_comp.serialize_signature_compressed(sig)
  doAssert status == cttCodecEcc_Success

  var sig2{.noInit.}: Signature

  bench("Signature deserialization (skip checks)", "BLS12_381 G2", iters):
    let status = sig2.deserialize_signature_compressed_unchecked(sig_comp)

proc benchSign*(iters: int) =
  let (sk, pk) = demoKeyGen()
  let msg = "Mr F was here"

  var sig: Signature

  bench("BLS signature", "BLS12_381 G2", iters):
    sig.sign(sk, msg)

proc benchVerify*(iters: int) =
  let (sk, pk) = demoKeyGen()
  let msg = "Mr F was here"

  var sig: Signature
  sig.sign(sk, msg)

  bench("BLS verification", "BLS12_381", iters):
    let valid = pk.verify(msg, sig)

proc benchFastAggregateVerify*(numKeys, iters: int) =
  ## Verification of N pubkeys signing 1 message
  let msg = "Mr F was here"

  var validators = newSeq[PublicKey](numKeys)
  var sigs = newSeq[Signature](numKeys)
  var aggSig: Signature

  for i in 0 ..< numKeys:
    let (sk, pk) = demoKeyGen()
    validators[i] = pk
    sigs[i].sign(sk, msg)

  aggSig.aggregate_signatures_unstable_api(sigs)

  bench("BLS agg verif of 1 msg by " & $numKeys & " pubkeys", "BLS12_381", iters):
    let valid = validators.fast_aggregate_verify(msg, aggSig)

proc benchVerifyMulti*(numSigs, iters: int) =
  ## Verification of N pubkeys signing for N messages

  var triplets: seq[tuple[pubkey: PublicKey, msg: array[32, byte], sig: Signature]]

  var hashedMsg: array[32, byte]
  var sig: Signature

  for i in 0 ..< numSigs:
    let (sk, pk) = demoKeyGen()
    sha256.hash(hashedMsg, "msg" & $i)
    sig.sign(sk, hashedMsg)
    triplets.add (pk, hashedMsg, sig)

  bench("BLS verif of " & $numSigs & " msgs by " & $numSigs & " pubkeys", "BLS12_381", iters):
    for i in 0 ..< triplets.len:
      let ok = triplets[i].pubkey.verify(triplets[i].msg, triplets[i].sig)
      doAssert ok == cttEthBls_Success

proc benchVerifyBatched*(numSigs, iters: int) =
  ## Verification of N pubkeys signing for N messages

  var
    pubkeys: seq[PublicKey]
    messages: seq[array[32, byte]]
    signatures: seq[Signature]

  var hashedMsg: array[32, byte]
  var sig: Signature

  for i in 0 ..< numSigs:
    let (sk, pk) = demoKeyGen()
    sha256.hash(hashedMsg, "msg" & $i)
    sig.sign(sk, hashedMsg)

    pubkeys.add pk
    messages.add hashedMsg
    signatures.add sig

  let secureBlindingBytes = sha256.hash("Mr F was here")

  bench("BLS serial batch verify of " & $numSigs & " msgs by "& $numSigs & " pubkeys (with blinding)", "BLS12_381", iters):
    let ok = batch_verify(pubkeys, messages, signatures, secureBlindingBytes)
    doAssert ok == cttEthBls_Success

proc benchVerifyBatchedParallel*(numSigs, iters: int) =
  ## Verification of N pubkeys signing for N messages

  var
    tp: Threadpool
    pubkeys: seq[PublicKey]
    messages: seq[array[32, byte]]
    signatures: seq[Signature]

  var hashedMsg: array[32, byte]
  var sig: Signature


  var numThreads: int
  if existsEnv"CTT_NUM_THREADS":
    numThreads = getEnv"CTT_NUM_THREADS".parseInt()
  else:
    numThreads = countProcessors()
  tp = Threadpool.new(numThreads)

  for i in 0 ..< numSigs:
    let (sk, pk) = demoKeyGen()
    sha256.hash(hashedMsg, "msg" & $i)
    sig.sign(sk, hashedMsg)

    pubkeys.add pk
    messages.add hashedMsg
    signatures.add sig

  let secureBlindingBytes = sha256.hash("Mr F was here")

  bench("BLS parallel batch verify (" & $tp.numThreads & " threads) of " & $numSigs & " msgs by "& $numSigs & " pubkeys (with blinding)", "BLS12_381", iters):
    let ok = tp.batch_verify_parallel(pubkeys, messages, signatures, secureBlindingBytes)
    doAssert ok == cttEthBls_Success, "invalid status: " & $ok

  tp.shutdown()

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
  benchFastAggregateVerify(numKeys = 128, iters = 10)
  separator()

  # Simulate Block verification (at most 6 signatures per block)
  benchVerifyMulti(numSigs = 6, iters = 10)
  benchVerifyBatched(numSigs = 6, iters = 10)
  benchVerifyBatchedParallel(numSigs = 6, iters = 10)
  separator()

  # Simulate 10 blocks verification
  benchVerifyMulti(numSigs = 60, iters = 10)
  benchVerifyBatched(numSigs = 60, iters = 10)
  benchVerifyBatchedParallel(numSigs = 60, iters = 10)
  separator()

  # Simulate 30 blocks verification
  benchVerifyMulti(numSigs = 180, iters = 10)
  benchVerifyBatched(numSigs = 180, iters = 10)
  benchVerifyBatchedParallel(numSigs = 180, iters = 10)
  separator()

main()
notes()
