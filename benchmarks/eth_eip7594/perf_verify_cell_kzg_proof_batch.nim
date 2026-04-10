# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  benchset_serialization,
  constantine/eth_eip7594_peerdas,
  constantine/ethereum_eip4844_kzg_parallel,
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, io/io_fields],
  constantine/serialization/codecs_bls12_381,
  constantine/csprngs/sysrand,
  ../bench_blueprint,
  std/[os, strutils, monotimes]

func proofToBytes(proof: KZGProof): array[48, byte] =
  discard result.serialize_g1_compressed(EC_ShortW_Aff[Fp[BLS12_381], G1](proof))

proc report(op: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, startTime, stopTime, startClk, stopClk, iters)

proc benchVerifyCellKZGProofBatch_64Blobs(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Verify 64 blobs with all 128 cells each (8192 total cells)
  ## This is the main scaling benchmark for batch verification
  
  var secureRandomBytes {.noInit.}: array[32, byte]
  discard sysrand(secureRandomBytes)

  const MaxTotal = NumBlobs * CELLS_PER_EXT_BLOB  # 8192
  
  var commitments_bytes {.noInit.}: ref array[MaxTotal, array[48, byte]]
  var cell_indices {.noInit.}: ref array[MaxTotal, int]
  var cells_array {.noInit.}: ref array[MaxTotal, Cell]
  var proofs_bytes {.noInit.}: ref array[MaxTotal, array[48, byte]]
  new(commitments_bytes)
  new(cell_indices)
  new(cells_array)
  new(proofs_bytes)

  var idx = 0
  for blobIdx in 0 ..< 64:
    for cellIdx in 0 ..< CELLS_PER_EXT_BLOB:
      commitments_bytes[][idx] = b.commitments[blobIdx]
      cell_indices[][idx] = cellIdx
      cells_array[][idx] = b.cells[blobIdx][cellIdx]
      proofs_bytes[][idx] = proofToBytes(b.proofs[blobIdx][cellIdx])
      inc idx

  bench("verify_cell_kzg_proof_batch (64 blobs, 8192 cells)", iters):
    discard verify_cell_kzg_proof_batch(
      ctx,
      commitments_bytes[][0 ..< MaxTotal],
      cell_indices[][0 ..< MaxTotal],
      cells_array[][0 ..< MaxTotal],
      proofs_bytes[][0 ..< MaxTotal],
      secureRandomBytes
    )

proc main() =
  echo "PeerDAS (EIP-7594) - verify_cell_kzg_proof_batch Benchmark"
  echo "Optimized for perf/VTune profiling (single benchmark, serialized data)\n"

  let benchsetFile = currentSourcePath.rsplit(DirSep, 1)[0] / "benchset.dat"
  if not fileExists(benchsetFile):
    echo &"Error: BenchSet file not found: {benchsetFile}"
    echo "Run benchset_generation.nim first to generate the benchmark data."
    quit(1)

  const TrustedSetupMainnet =
    currentSourcePath.rsplit(DirSep, 1)[0] /
    ".." / ".." / "constantine" /
    "commitments_setups" /
    "trusted_setup_ethereum_kzg4844_reference.dat"

  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.trusted_setup_load(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess

  let b = BenchSet.load(benchsetFile)

  echo "Running verify_cell_kzg_proof_batch benchmark (64 blobs, 8192 cells)..."
  echo ""
  
  const Iters = 5
  benchVerifyCellKZGProofBatch_64Blobs(b, ctx, Iters)

  ctx.trusted_setup_delete()

when isMainModule:
  main()