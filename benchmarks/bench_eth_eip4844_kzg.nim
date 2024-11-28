# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/ethereum_eip4844_kzg_parallel,
  constantine/named/algebras,
  constantine/math/io/io_fields,
  constantine/threadpool/threadpool,
  constantine/csprngs/sysrand,
  constantine/platforms/primitives,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint,
  # Standard library
  std/[os, strutils]

proc separator*() = separator(180)

proc report(op, threads: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<40} {threads:<16} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<40} {threads:<16} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op, threads: string, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, threads, startTime, stopTime, startClk, stopClk, iters)

type
  BenchSet[N: static int] = ref object
    blobs: array[N, Blob]
    commitments: array[N, array[48, byte]]
    proofs: array[N, array[48, byte]]
    # This is only used for `verify_kzg_proof` and
    # there is no short-circuit if they don't match
    opening_challenge, eval_at_challenge: array[32, byte]

proc randomize(rng: var RngState, blob: var Blob) =
  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let t {.noInit.} = rng.random_unsafe(Fr[BLS12_381])
    let offset = i*BYTES_PER_FIELD_ELEMENT
    blob.toOpenArray(offset, offset+BYTES_PER_FIELD_ELEMENT-1)
        .marshal(t, bigEndian)

proc new(T: type BenchSet, ctx: ptr EthereumKZGContext): T =
  new(result)
  for i in 0 ..< result.N:
    rng.randomize(result.blobs[i])
    discard ctx.blob_to_kzg_commitment(result.commitments[i], result.blobs[i])
    discard ctx.compute_blob_kzg_proof(result.proofs[i], result.blobs[i], result.commitments[i])

  let opening_challenge = rng.random_unsafe(Fr[BLS12_381])
  let eval_at_challenge = rng.random_unsafe(Fr[BLS12_381])

  discard result.opening_challenge.marshal(opening_challenge, bigEndian)
  discard result.eval_at_challenge.marshal(eval_at_challenge, bigEndian)

proc benchBlobToKzgCommitment(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =

  let startSerial = getMonotime()
  block:
    bench("blob_to_kzg_commitment", "serial", iters):
      var commitment {.noInit.}: array[48, byte]
      doAssert cttEthKzg_Success == ctx.blob_to_kzg_commitment(commitment, b.blobs[0])
  let stopSerial = getMonotime()

  ## We require `tp` to be unintialized as even idle threads somehow reduce perf of serial benches
  let tp = Threadpool.new()
  let numThreads = tp.numThreads

  let startParallel = getMonotime()
  block:
    bench("blob_to_kzg_commitment", $tp.numThreads & " threads", iters):
      var commitment {.noInit.}: array[48, byte]
      doAssert cttEthKzg_Success == tp.blob_to_kzg_commitment_parallel(ctx, commitment, b.blobs[0])
  let stopParallel = getMonotime()

  tp.shutdown()

  let perfSerial = inNanoseconds((stopSerial-startSerial) div iters)
  let perfParallel = inNanoseconds((stopParallel-startParallel) div iters)

  let parallelSpeedup = float(perfSerial) / float(perfParallel)
  echo &"Speedup ratio parallel {numThreads} threads over serial: {parallelSpeedup:>6.3f}x"

proc benchComputeKzgProof(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =

  let startSerial = getMonotime()
  block:
    bench("compute_kzg_proof", "serial", iters):
      var proof {.noInit.}: array[48, byte]
      var eval_at_challenge {.noInit.}: array[32, byte]
      doAssert cttEthKzg_Success == ctx.compute_kzg_proof(proof, eval_at_challenge, b.blobs[0], b.opening_challenge)
  let stopSerial = getMonotime()

  ## We require `tp` to be unintialized as even idle threads somehow reduce perf of serial benches
  let tp = Threadpool.new()
  let numThreads = tp.numThreads

  let startParallel = getMonotime()
  block:
    bench("compute_kzg_proof", $tp.numThreads & " threads", iters):
      var proof {.noInit.}: array[48, byte]
      var eval_at_challenge {.noInit.}: array[32, byte]
      doAssert cttEthKzg_Success == tp.compute_kzg_proof_parallel(ctx, proof, eval_at_challenge, b.blobs[0], b.opening_challenge)
  let stopParallel = getMonotime()

  tp.shutdown()

  let perfSerial = inNanoseconds((stopSerial-startSerial) div iters)
  let perfParallel = inNanoseconds((stopParallel-startParallel) div iters)

  let parallelSpeedup = float(perfSerial) / float(perfParallel)
  echo &"Speedup ratio parallel {numThreads} threads over serial: {parallelSpeedup:>6.3f}x"

proc benchComputeBlobKzgProof(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =

  let startSerial = getMonotime()
  block:
    bench("compute_blob_kzg_proof", "serial", iters):
      var proof {.noInit.}: array[48, byte]
      doAssert cttEthKzg_Success == ctx.compute_blob_kzg_proof(proof, b.blobs[0], b.commitments[0])
  let stopSerial = getMonotime()

  ## We require `tp` to be unintialized as even idle threads somehow reduce perf of serial benches
  let tp = Threadpool.new()
  let numThreads = tp.numThreads

  let startParallel = getMonotime()
  block:
    bench("compute_blob_kzg_proof", $tp.numThreads & " threads", iters):
      var proof {.noInit.}: array[48, byte]
      doAssert cttEthKzg_Success == tp.compute_blob_kzg_proof_parallel(ctx, proof, b.blobs[0], b.commitments[0])
  let stopParallel = getMonotime()

  tp.shutdown()

  let perfSerial = inNanoseconds((stopSerial-startSerial) div iters)
  let perfParallel = inNanoseconds((stopParallel-startParallel) div iters)

  let parallelSpeedup = float(perfSerial) / float(perfParallel)
  echo &"Speedup ratio parallel {numThreads} threads over serial: {parallelSpeedup:>6.3f}x"

proc benchVerifyKzgProof(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =

  bench("verify_kzg_proof", "serial", iters):
    discard ctx.verify_kzg_proof(b.commitments[0], b.opening_challenge, b.eval_at_challenge, b.proofs[0])

  echo "verify_kzg_proof is always serial"

proc benchVerifyBlobKzgProof(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =

  let startSerial = getMonotime()
  block:
    bench("verify_blob_kzg_proof", "serial", iters):
      discard ctx.verify_blob_kzg_proof(b.blobs[0], b.commitments[0], b.proofs[0])
  let stopSerial = getMonotime()

  ## We require `tp` to be unintialized as even idle threads somehow reduce perf of serial benches
  let tp = Threadpool.new()
  let numThreads = tp.numThreads

  let startParallel = getMonotime()
  block:
    bench("verify_blob_kzg_proof", $tp.numThreads & " threads", iters):
      discard tp.verify_blob_kzg_proof_parallel(ctx, b.blobs[0], b.commitments[0], b.proofs[0])
  let stopParallel = getMonotime()

  tp.shutdown()

  let perfSerial = inNanoseconds((stopSerial-startSerial) div iters)
  let perfParallel = inNanoseconds((stopParallel-startParallel) div iters)

  let parallelSpeedup = float(perfSerial) / float(perfParallel)
  echo &"Speedup ratio parallel {numThreads} threads over serial: {parallelSpeedup:>6.3f}x"

proc benchVerifyBlobKzgProofBatch(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =

  var secureRandomBytes {.noInit.}: array[32, byte]
  discard sysrand(secureRandomBytes)

  var i = 1

  while i <= b.N:

    let startSerial = getMonotime()
    block:
      bench("verify_blob_kzg_proof (batch " & $i & ')', "serial", iters):
        discard verify_blob_kzg_proof_batch(
                  ctx,
                  b.blobs.asUnchecked(),
                  b.commitments.asUnchecked(),
                  b.proofs.asUnchecked(),
                  i,
                  secureRandomBytes)
    let stopSerial = getMonotime()

    ## We require `tp` to be unintialized as even idle threads somehow reduce perf of serial benches
    let tp = Threadpool.new()
    let numTHreads = tp.numThreads

    let startParallel = getMonotime()
    block:
      bench("verify_blob_kzg_proof (batch " & $i & ')', $tp.numThreads & " threads", iters):
        discard tp.verify_blob_kzg_proof_batch_parallel(
                  ctx,
                  b.blobs.asUnchecked(),
                  b.commitments.asUnchecked(),
                  b.proofs.asUnchecked(),
                  i,
                  secureRandomBytes)
    let stopParallel = getMonotime()

    tp.shutdown()

    let perfSerial = inNanoseconds((stopSerial-startSerial) div iters)
    let perfParallel = inNanoseconds((stopParallel-startParallel) div iters)

    let parallelSpeedup = float(perfSerial) / float(perfParallel)
    echo &"Speedup ratio parallel {numThreads} threads over serial: {parallelSpeedup:>6.3f}x"
    echo ""

    i *= 2

const TrustedSetupMainnet =
  currentSourcePath.rsplit(DirSep, 1)[0] /
  ".." / "constantine" /
  "commitments_setups" /
  "trusted_setup_ethereum_kzg4844_reference.dat"

proc trusted_setup*(): ptr EthereumKZGContext =
  ## This is a convenience function for the Ethereum mainnet testing trusted setups.
  ## It is insecure and will be replaced once the KZG ceremony is done.

  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "\n[Trusted Setup Error] " & $tsStatus
  echo "Trusted Setup loaded successfully"
  return ctx

const Iters = 100
proc main() =
  let ctx = trusted_setup()
  let b = BenchSet[64].new(ctx)
  separator()
  benchBlobToKzgCommitment(b, ctx, Iters)
  echo ""
  benchComputeKzgProof(b, ctx, Iters)
  echo ""
  benchComputeBlobKzgProof(b, ctx, Iters)
  echo ""
  benchVerifyKzgProof(b, ctx, Iters)
  echo ""
  benchVerifyBlobKzgProof(b, ctx, Iters)
  echo ""
  benchVerifyBlobKzgProofBatch(b, ctx, Iters)
  separator()
  ctx.trusted_setup_delete()

when isMainModule:
  main()
