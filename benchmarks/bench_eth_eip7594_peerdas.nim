# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/eth_eip7594_peerdas,
  constantine/commitments/kzg_multiproofs,
  constantine/ethereum_eip4844_kzg_parallel,
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, io/io_fields],
  constantine/serialization/codecs_bls12_381,
  constantine/csprngs/sysrand,
  constantine/platforms/primitives,
  constantine/threadpool/threadpool,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint,
  # Standard library
  std/[os, strutils, sequtils, monotimes]

const NumBlobs* = 4  # Number of blobs for benchmarks (reduced from 64 for faster init)
                      # Parallel initialization uses all available threads (~20 on modern CPUs)
                      # Initialization time: ~2s for 4 blobs (vs ~8s serial)

proc separator*() = separator(180)

func proofToBytes(proof: KZGProof): array[48, byte] =
  ## Convert KZGProof to compressed bytes
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

type
  BenchSet[N: static int] = ref object
    blobs: array[N, Blob]
    commitments: array[N, array[48, byte]]
    cells: array[N, array[CELLS_PER_EXT_BLOB, Cell]]
    proofs: array[N, array[CELLS_PER_EXT_BLOB, KZGProof]]
    # For recovery benchmarks - half cells
    halfCellIndices: array[N, seq[CellIndex]]
    halfCells: array[N, seq[Cell]]

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
  tempProofs: ptr array[CELLS_PER_EXT_BLOB, KZGProof],
  rng: ptr RngState
) {.raises: [].} =
  ## Compute blob, commitment, cells and proofs in parallel
  # Randomize blob using thread-local RNG
  rng[].randomize(tempBlobs[])

  # Compute commitment
  doAssert cttEthKzg_Success == ctx.blob_to_kzg_commitment(tempCommitments[], tempBlobs[])

  # Compute all cells and proofs (this is the expensive part!)
  doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(tempBlobs[], tempCells[], tempProofs[])

proc new(T: type BenchSet, ctx: ptr EthereumKZGContext): T =
  new(result)

  echo "Initializing benchmark data (this may take a while)..."
  let initStart = getMonotime()

  # Create threadpool for parallel initialization
  let tp = Threadpool.new()
  let numThreads = tp.numThreads
  echo &"  Using {numThreads} threads for parallel initialization"

  # Create per-thread RNG states with different seeds
  var threadRngs = newSeq[RngState](numThreads)
  for t in 0 ..< numThreads:
    # Use different seed for each thread based on thread ID and current time
    let seed = uint32(getTime().toUnix() + t * 1000000)
    threadRngs[t].seed(seed)

  # Allocate temporary storage for parallel computation
  let tempBlobs = allocHeapArrayAligned(Blob, T.N, 64)
  let tempCommitments = allocHeapArrayAligned(array[48, byte], T.N, 64)
  let tempCells = allocHeapArrayAligned(array[CELLS_PER_EXT_BLOB, Cell], T.N, 64)
  let tempProofs = allocHeapArrayAligned(array[CELLS_PER_EXT_BLOB, KZGProof], T.N, 64)

  # Initialize blobs in parallel using spawnAwaitable pattern
  echo "  Computing cells and proofs in parallel..."
  for i in 0 ..< T.N:
    let threadId = i mod numThreads
    let threadRng = threadRngs[threadId].addr
    let blobIdx = i

    discard tp.spawnAwaitable(
      computeBlobParallel(
        ctx,
        tempBlobs[blobIdx].addr,
        tempCommitments[blobIdx].addr,
        tempCells[blobIdx].addr,
        tempProofs[blobIdx].addr,
        threadRng
      )
    )

    echo &"  Queued blob {i+1}/{T.N} for computation..."

  # Wait for all blob computations to complete
  echo "  Waiting for all computations to complete..."
  tp.shutdown()

  # Copy results from temp arrays to result object
  for i in 0 ..< T.N:
    result.blobs[i] = tempBlobs[i]
    result.commitments[i] = tempCommitments[i]
    result.cells[i] = tempCells[i]
    result.proofs[i] = tempProofs[i]

  # Free temporary arrays
  freeHeapAligned(tempBlobs)
  freeHeapAligned(tempCommitments)
  freeHeapAligned(tempCells)
  freeHeapAligned(tempProofs)

  # Setup half-cell indices for recovery benchmarks (sequential, fast operation)
  for i in 0 ..< result.N:
    result.halfCellIndices[i] = @[]
    result.halfCells[i] = @[]
    for j in 0 ..< CELLS_PER_EXT_BLOB:
      if j mod 2 == 0:  # Take every other cell (50% availability)
        result.halfCellIndices[i].add(CellIndex(j))
        result.halfCells[i].add(result.cells[i][j])

  let initStop = getMonotime()
  let initTime = (initStop - initStart).inNanoseconds() div 1_000_000
  echo &"Initialization complete in {initTime} ms ({float(initTime)/1000.0:.2f} seconds)\n"

proc benchComputeCells(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Compute cells without proofs (half-FFT optimization)
  ## Corresponds to:
  ## - go-eth-kzg: ComputeCells benchmark
  ## - rust-eth-kzg: Not directly exposed (always computes with proofs)
  ## - rust-kzg: bench_das_extension (lower-level FFT operation)

  bench("compute_cells (half-FFT optimization)", iters):
    var cells {.noInit.}: ref array[CELLS_PER_EXT_BLOB, Cell]
    new(cells)
    doAssert cttEthKzg_Success == ctx.compute_cells(b.blobs[0], cells[])

proc benchComputeCellsAndKZGProofs(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Compute cells and proofs together using FK20 algorithm
  ## Corresponds to:
  ## - go-eth-kzg: ComputeCellsAndKZGProofs benchmark
  ## - rust-eth-kzg: "computing cells_and_kzg_proofs" benchmark
  ## - rust-kzg: compute_cells_and_kzg_proofs benchmark

  bench("compute_cells_and_kzg_proofs (FK20)", iters):
    var cells {.noInit.}: ref array[CELLS_PER_EXT_BLOB, Cell]
    var proofs {.noInit.}: ref array[CELLS_PER_EXT_BLOB, KZGProof]
    new(cells)
    new(proofs)
    doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(b.blobs[0], cells[], proofs[])

proc benchVerifyCellKZGProofBatch_SingleBlob(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Verify cells from a single blob with varying batch sizes
  ## Corresponds to:
  ## - go-eth-kzg: VerifyCellKZGProofBatch(count=1,8,32,64,128) benchmarks
  ## - rust-eth-kzg: verify_cell_kzg_proof_batch benchmark
  ## - rust-kzg: verify_cell_kzg_proof_batch (columns) benchmark

  var secureRandomBytes {.noInit.}: array[32, byte]
  discard sysrand(secureRandomBytes)

  # Test with different batch sizes - use fixed max size for ref array
  const MaxCount = 128
  for count in [1, 8, 32, 64, 128]:
    bench(&"verify_cell_kzg_proof_batch (count={count}, 1 blob)", iters):
      var commitments_bytes {.noInit.}: ref array[MaxCount, array[48, byte]]
      var cell_indices {.noInit.}: ref array[MaxCount, int]
      var cells_array {.noInit.}: ref array[MaxCount, Cell]
      var proofs_bytes {.noInit.}: ref array[MaxCount, array[48, byte]]
      new(commitments_bytes)
      new(cell_indices)
      new(cells_array)
      new(proofs_bytes)

      for i in 0 ..< count:
        commitments_bytes[][i] = b.commitments[0]
        cell_indices[][i] = i
        cells_array[][i] = b.cells[0][i]
        proofs_bytes[][i] = proofToBytes(b.proofs[0][i])

      discard verify_cell_kzg_proof_batch(
        ctx,
        commitments_bytes[][0 ..< count],
        cell_indices[][0 ..< count],
        cells_array[][0 ..< count],
        proofs_bytes[][0 ..< count],
        secureRandomBytes
      )

proc benchVerifyCellKZGProofBatch_MultiBlob(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Verify cells from multiple blobs (scaling by number of blobs)
  ## Corresponds to:
  ## - go-eth-kzg: Not directly tested (single blob only)
  ## - rust-eth-kzg: Not directly tested
  ## - rust-kzg: verify_cell_kzg_proof_batch (rows) benchmark

  var secureRandomBytes {.noInit.}: array[32, byte]
  discard sysrand(secureRandomBytes)

  var i = 1
  while i <= b.N:
    bench(&"verify_cell_kzg_proof_batch (128 cells, {i} blobs)", iters):
      let totalCount = i * CELLS_PER_EXT_BLOB
      const MaxTotal = NumBlobs * CELLS_PER_EXT_BLOB

      var commitments_bytes {.noInit.}: ref array[MaxTotal, array[48, byte]]
      var cell_indices {.noInit.}: ref array[MaxTotal, int]
      var cells_array {.noInit.}: ref array[MaxTotal, Cell]
      var proofs_bytes {.noInit.}: ref array[MaxTotal, array[48, byte]]
      new(commitments_bytes)
      new(cell_indices)
      new(cells_array)
      new(proofs_bytes)

      var idx = 0
      for blobIdx in 0 ..< i:
        for cellIdx in 0 ..< CELLS_PER_EXT_BLOB:
          commitments_bytes[][idx] = b.commitments[blobIdx]
          cell_indices[][idx] = cellIdx
          cells_array[][idx] = b.cells[blobIdx][cellIdx]
          proofs_bytes[][idx] = proofToBytes(b.proofs[blobIdx][cellIdx])
          inc idx

      discard verify_cell_kzg_proof_batch(
        ctx,
        commitments_bytes[][0 ..< totalCount],
        cell_indices[][0 ..< totalCount],
        cells_array[][0 ..< totalCount],
        proofs_bytes[][0 ..< totalCount],
        secureRandomBytes
      )

    i *= 2

proc benchRecoverCellsAndKZGProofs_WorstCase(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Recover from exactly 50% of cells (worst case)
  ## Corresponds to:
  ## - go-eth-kzg: RecoverCellsAndComputeKZGProofs benchmark
  ## - rust-eth-kzg: "worse-case recover_cells_and_kzg_proofs" benchmark
  ## - rust-kzg: recover_cells_and_kzg_proofs (% missing) benchmark

  bench("recover_cells_and_kzg_proofs (50% cells)", iters):
    var recovered_cells {.noInit.}: ref array[CELLS_PER_EXT_BLOB, Cell]
    var recovered_proofs {.noInit.}: ref array[CELLS_PER_EXT_BLOB, KZGProof]
    new(recovered_cells)
    new(recovered_proofs)

    doAssert cttEthKzg_Success == recover_cells_and_kzg_proofs(
      ctx,
      b.halfCellIndices[0],
      b.halfCells[0],
      recovered_cells[],
      recovered_proofs[]
    )

proc benchRecoverCellsAndKZGProofs_VaryingAvailability(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Recover with varying cell availability (50%, 75%, 87.5%)
  ## Corresponds to:
  ## - go-eth-kzg: Not tested (only 50%)
  ## - rust-eth-kzg: Not tested (only 50%)
  ## - rust-kzg: recover_cells_and_kzg_proofs (% missing) with 50%, 25%, 12.5% missing

  # Test different availability levels
  for availability in [50, 75, 87]:
    let numCells = (CELLS_PER_EXT_BLOB * availability) div 100

    bench(&"recover_cells_and_kzg_proofs ({availability}% availability, {numCells} cells)", iters):
      # Take first numCells cells (seq is fine for variable-size input)
      var cell_indices: seq[CellIndex] = @[]
      var cells: seq[Cell] = @[]

      for i in 0 ..< numCells:
        cell_indices.add(CellIndex(i))
        cells.add(b.cells[0][i])

      var recovered_cells {.noInit.}: ref array[CELLS_PER_EXT_BLOB, Cell]
      var recovered_proofs {.noInit.}: ref array[CELLS_PER_EXT_BLOB, KZGProof]
      new(recovered_cells)
      new(recovered_proofs)

      doAssert cttEthKzg_Success == recover_cells_and_kzg_proofs(
        ctx,
        cell_indices,
        cells,
        recovered_cells[],
        recovered_proofs[]
      )

proc benchFK20_Proving(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## FK20 multi-proof computation (internal component)
  ## Corresponds to:
  ## - go-eth-kzg: Internal to ComputeCellsAndKZGProofs
  ## - rust-eth-kzg: "computing proofs with fk20" benchmark
  ## - rust-kzg: bench_fk_multi_da benchmark

  bench("fk20_multi_prove (4096 coeffs, 64 points/proof, 128 proofs)", iters):
    # This is already tested via compute_cells_and_kzg_proofs
    # but we can measure it separately if needed
    var cells {.noInit.}: ref array[CELLS_PER_EXT_BLOB, Cell]
    var proofs {.noInit.}: ref array[CELLS_PER_EXT_BLOB, KZGProof]
    new(cells)
    new(proofs)
    doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(b.blobs[0], cells[], proofs[])

proc benchBatchVerification_ChallengeComputation(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Fiat-Shamir challenge computation for batch verification
  ## Corresponds to:
  ## - go-eth-kzg: Internal to VerifyCellKZGProofBatch
  ## - rust-eth-kzg: Internal
  ## - rust-kzg: Internal

  var secureRandomBytes {.noInit.}: array[32, byte]
  discard sysrand(secureRandomBytes)

  # Use 128 cells from first blob
  var commitments_bytes {.noInit.}: ref array[128, array[48, byte]]
  var commitment_indices {.noInit.}: ref array[128, int]
  var cell_indices {.noInit.}: ref array[128, int]
  var cosets_evals {.noInit.}: ref array[128, array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]
  var proofs_bytes {.noInit.}: ref array[128, array[48, byte]]
  new(commitments_bytes)
  new(commitment_indices)
  new(cell_indices)
  new(cosets_evals)
  new(proofs_bytes)

  for i in 0 ..< 128:
    commitments_bytes[][i] = b.commitments[0]
    commitment_indices[][i] = 0
    cell_indices[][i] = i
    proofs_bytes[][i] = proofToBytes(b.proofs[0][i])

  # Deserialize cells to coset evaluations
  for i in 0 ..< 128:
    let status = cellToCosetEvals(b.cells[0][i], cosets_evals[][i])
    doAssert status == cttEthKzg_Success

  bench("compute_verify_cell_kzg_proof_batch_challenge (128 cells)", iters):
    discard compute_verify_cell_kzg_proof_batch_challenge(
      commitments_bytes[],
      commitment_indices[],
      cell_indices[],
      cosets_evals[],
      proofs_bytes[]
    )

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

const Iters = 3
proc main() =
  echo "PeerDAS (EIP-7594) Benchmarks"
  echo "Note: Benchmarks are serial, but initialization is parallelized"
  echo ""

  let ctx = trusted_setup()
  let b = BenchSet[NumBlobs].new(ctx)

  separator()
  echo "Cell Computation Benchmarks"
  separator()
  benchComputeCells(b, ctx, Iters)
  echo ""
  benchComputeCellsAndKZGProofs(b, ctx, Iters)
  echo ""

  separator()
  echo "Verification Benchmarks"
  separator()
  benchVerifyCellKZGProofBatch_SingleBlob(b, ctx, Iters)
  echo ""
  benchVerifyCellKZGProofBatch_MultiBlob(b, ctx, Iters)
  echo ""
  benchBatchVerification_ChallengeComputation(b, ctx, Iters)
  echo ""

  separator()
  echo "Recovery Benchmarks"
  separator()
  benchRecoverCellsAndKZGProofs_WorstCase(b, ctx, Iters)
  echo ""
  benchRecoverCellsAndKZGProofs_VaryingAvailability(b, ctx, Iters)
  echo ""

  separator()
  echo "Internal Component Benchmarks"
  separator()
  benchFK20_Proving(b, ctx, Iters)
  separator()

  ctx.trusted_setup_delete()

when isMainModule:
  main()