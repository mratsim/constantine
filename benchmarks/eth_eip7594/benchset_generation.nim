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
  constantine/platforms/primitives,
  constantine/platforms/views,
  constantine/ethereum_eip4844_kzg_parallel,
  constantine/threadpool/threadpool,
  constantine/platforms/allocs,
  constantine/named/algebras,
  constantine/math/io/io_fields,
  helpers/prng_unsafe,
  ../bench_blueprint,
  std/[os, strutils, sequtils, monotimes]

const TrustedSetupMainnet =
  currentSourcePath.rsplit(DirSep, 1)[0] /
  ".." / ".." / "constantine" /
  "commitments_setups" /
  "trusted_setup_ethereum_kzg4844_reference.dat"

proc trusted_setup*(): ptr EthereumKZGContext =
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.new(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "\n[Trusted Setup Error] " & $tsStatus
  echo "Trusted Setup loaded successfully"
  return ctx

proc randomize(rng: var RngState, blob: var Blob) =
  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let t {.noInit.} = rng.random_unsafe(Fr[BLS12_381])
    let offset = i*BYTES_PER_FIELD_ELEMENT
    blob.toOpenArray(offset, offset+BYTES_PER_FIELD_ELEMENT-1)
        .marshal(t, bigEndian)

proc computeBlobParallel(
  ctx: ptr EthereumKZGContext,
  tempBlobs: ptr Blob,
  tempCommitments: ptr array[48, byte],
  tempCells: ptr array[CELLS_PER_EXT_BLOB, Cell],
  tempProofs: ptr array[CELLS_PER_EXT_BLOB, KZGProofBytes],
  rng: ptr RngState
) {.raises: [].} =
  rng[].randomize(tempBlobs[])
  doAssert cttEthKzg_Success == ctx.blob_to_kzg_commitment(tempCommitments[], tempBlobs[])
  doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(
    tempCells[].asUnchecked(),
    tempProofs[].asUnchecked(),
    tempBlobs[])

proc new*(T: type BenchSet, ctx: ptr EthereumKZGContext): T =
  result = newBenchSet()

  echo "Initializing benchmark data (this may take a while)..."
  let initStart = getMonotime()

  let tp = Threadpool.new()
  let numThreads = tp.numThreads
  echo &"  Using {numThreads} threads for parallel initialization"

  var blobRngs = newSeq[RngState](NumBlobs)
  const baseSeed = 0x7594_DA5'u32  # PeerDAS marker; override via env if needed
  for i in 0 ..< NumBlobs:
    blobRngs[i].seed(baseSeed + uint32(i))

  let tempBlobs = allocHeapArrayAligned(Blob, NumBlobs, 64)
  let tempCommitments = allocHeapArrayAligned(array[48, byte], NumBlobs, 64)
  let tempCells = allocHeapArrayAligned(array[CELLS_PER_EXT_BLOB, Cell], NumBlobs, 64)
  let tempProofs = allocHeapArrayAligned(array[CELLS_PER_EXT_BLOB, KZGProofBytes], NumBlobs, 64)

  echo "  Computing cells and proofs in parallel..."
  for i in 0 ..< NumBlobs:
    let blobIdx = i
    let blobRng = blobRngs[blobIdx].addr

    discard tp.spawnAwaitable(
      computeBlobParallel(
        ctx,
        tempBlobs[blobIdx].addr,
        tempCommitments[blobIdx].addr,
        tempCells[blobIdx].addr,
        tempProofs[blobIdx].addr,
        blobRng
      )
    )

    if (i + 1) mod 8 == 0:
      echo &"  Queued blob {i+1}/{NumBlobs} for computation..."

  echo "  Waiting for all computations to complete..."
  tp.shutdown()

  for i in 0 ..< NumBlobs:
    result.blobs[i] = tempBlobs[i]
    result.commitments[i] = tempCommitments[i]
    result.cells[i] = tempCells[i]
    result.proofs[i] = tempProofs[i]

  freeHeapAligned(tempBlobs)
  freeHeapAligned(tempCommitments)
  freeHeapAligned(tempCells)
  freeHeapAligned(tempProofs)

  for i in 0 ..< NumBlobs:
    result.halfCellIndices[i] = @[]
    result.halfCells[i] = @[]
    for j in 0 ..< CELLS_PER_EXT_BLOB:
      if j mod 2 == 0:
        result.halfCellIndices[i].add(CellIndex(j))
        result.halfCells[i].add(result.cells[i][j])

  let initStop = getMonotime()
  let initTime = (initStop - initStart).inNanoseconds() div 1_000_000
  echo &"Initialization complete in {initTime} ms ({float(initTime)/1000.0:.2f} seconds)\n"

proc main() =
  echo "PeerDAS (EIP-7594) BenchSet Generator"
  echo "Creating BenchSet[64] for perf/VTune profiling\n"

  let ctx = trusted_setup()
  let b = BenchSet.new(ctx)

  # Serialize to binary file
  let outputDir = currentSourcePath.rsplit(DirSep, 1)[0]
  let outputFile = outputDir / "benchset.dat"
  b.serialize(outputFile)

  ctx.delete()

  echo "\nBenchSet saved to: " & outputFile
  echo "Use this file with perf_* benchmarks for fast loading."

when isMainModule:
  main()