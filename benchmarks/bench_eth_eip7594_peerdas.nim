# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## Run with
##   nim c -r --cc:clang -d:danger --hints:off --warnings:off --outdir:build/wip --nimcache:nimcache/wip benchmarks/bench_eth_eip7594_peerdas.nim
##
## Or via nimble:
##   CC=clang nimble bench_eth_eip7594_peerdas

import
  # Internals
  constantine/eth_eip7594_peerdas {.all.},
  constantine/commitments/kzg_multiproofs,
  constantine/commitments_setups/ethereum_kzg_srs,
  constantine/ethereum_eip4844_kzg_parallel,
  constantine/named/algebras,
  constantine/math/[ec_shortweierstrass, io/io_fields, elliptic/ec_multi_scalar_mul_precomp],
  constantine/serialization/codecs_bls12_381,
  constantine/csprngs/sysrand,
  constantine/platforms/primitives,
  constantine/threadpool/threadpool,
  std/importutils,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint,
  # Standard library
  std/[os, strutils, sequtils, monotimes]

importutils.privateAccess(ec_multi_scalar_mul_precomp.PrecomputedMSM)

const NumBlobs* = 64  # Number of blobs for benchmarks (matches c-kzg-4844 config)
                      # Parallel initialization uses all available threads (~20 on modern CPUs)
                      # Initialization time: ~2-3s for 64 blobs

proc separator*() = separator(180)

proc report(op: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo fmt"{op:<72} {throughput:>15.3f} ops/s {ns:>16} ns/op {(stopClk - startClk) div iters:>14} CPU cycles (approx)"
  else:
    echo fmt"{op:<72} {throughput:>15.3f} ops/s {ns:>16} ns/op"

template bench(op: string, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, startTime, stopTime, startClk, stopClk, iters)

type
  BenchSet[N: static int] = ref object
    blobs: array[N, Blob]
    commitments: array[N, array[48, byte]]
    cells: array[N, array[CELLS_PER_EXT_BLOB, Cell]]
    proofs: array[N, array[CELLS_PER_EXT_BLOB, KZGProofBytes]]
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
  tempProofs: ptr array[CELLS_PER_EXT_BLOB, KZGProofBytes],
  rng: ptr RngState
) {.raises: [].} =
  ## Compute blob, commitment, cells and proofs in parallel
  # Randomize blob using thread-local RNG
  rng[].randomize(tempBlobs[])

  # Compute commitment
  doAssert cttEthKzg_Success == ctx.blob_to_kzg_commitment(tempCommitments[], tempBlobs[])

  # Compute all cells and proofs (this is the expensive part!)
  doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(
    tempCells[].asUnchecked(),
    tempProofs[].asUnchecked(),
    tempBlobs[])

proc new(T: type BenchSet, ctx: ptr EthereumKZGContext): T =
  new(result)

  echo "Initializing benchmark data (this may take a while)..."
  let initStart = getMonotime()

  # Create threadpool for parallel initialization
  let tp = Threadpool.new()
  let numThreads = tp.numThreads
  echo &"  Using {numThreads} threads for parallel initialization"

  # Use one RNG per blob to avoid sharing across spawned tasks
  # (prevents data race when NumBlobs > numThreads)
  var taskRngs = newSeq[RngState](T.N)
  for t in 0 ..< T.N:
    # Use different seed for each blob based on index and current time
    let seed = uint32(getTime().toUnix() + t * 1000000)
    taskRngs[t].seed(seed)

  # Allocate temporary storage for parallel computation
  let tempBlobs = allocHeapArrayAligned(Blob, T.N, 64)
  let tempCommitments = allocHeapArrayAligned(array[48, byte], T.N, 64)
  let tempCells = allocHeapArrayAligned(array[CELLS_PER_EXT_BLOB, Cell], T.N, 64)
  let tempProofs = allocHeapArrayAligned(array[CELLS_PER_EXT_BLOB, KZGProofBytes], T.N, 64)

  # Initialize blobs in parallel using spawnAwaitable pattern
  echo "  Computing cells and proofs in parallel..."
  for i in 0 ..< T.N:
    let taskRng = taskRngs[i].addr
    let blobIdx = i

    discard tp.spawnAwaitable(
      computeBlobParallel(
        ctx,
        tempBlobs[blobIdx].addr,
        tempCommitments[blobIdx].addr,
        tempCells[blobIdx].addr,
        tempProofs[blobIdx].addr,
        taskRng
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
    var cells: ref array[CELLS_PER_EXT_BLOB, Cell]
    new(cells)
    doAssert cttEthKzg_Success == ctx.compute_cells(cells[], b.blobs[0])

proc benchComputeCellsAndKZGProofs(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Compute cells and proofs together using FK20 algorithm
  ## Corresponds to:
  ## - go-eth-kzg: ComputeCellsAndKZGProofs benchmark
  ## - rust-eth-kzg: "computing cells_and_kzg_proofs" benchmark
  ## - rust-kzg: compute_cells_and_kzg_proofs benchmark

  type EC_Aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
  type EC_Jac = EC_ShortW_Jac[Fp[BLS12_381], G1]

  # No precompute baseline
  proc runNoPrecomp() =
    ctx.polyphaseSpectrumBank.kind = kNoPrecompute
    bench("compute_cells_and_kzg_proofs (no precompute, 1.8 MiB)", iters):
      var cells: ref array[CELLS_PER_EXT_BLOB, Cell]
      var proofs: ref array[CELLS_PER_EXT_BLOB, KZGProofBytes]
      new(cells)
      new(proofs)
      doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(
        cells[].asUnchecked(),
        proofs[].asUnchecked(),
        b.blobs[0])

  # Precompute with given (t, b) config
  proc runPrecomp(t, bitWidth: int) =
    for pos in 0 ..< CELLS_PER_EXT_BLOB:
      ctx.polyphaseSpectrumBank.precompPoints[pos].init(ctx.polyphaseSpectrumBank.rawPoints[pos], t = t, b = bitWidth)
    ctx.polyphaseSpectrumBank.kind = kPrecompute

    let memMiB = float64(msmPrecompSize(EC_Jac, FIELD_ELEMENTS_PER_CELL, t, bitWidth) *
                          CELLS_PER_EXT_BLOB * sizeof(EC_Aff)) / (1024.0 * 1024.0)

    bench(fmt"compute_cells_and_kzg_proofs (t={t:>3}, b={bitWidth:>2}, ~{memMiB:>7.1f} MiB)", iters):
      var cells: ref array[CELLS_PER_EXT_BLOB, Cell]
      var proofs: ref array[CELLS_PER_EXT_BLOB, KZGProofBytes]
      new(cells)
      new(proofs)
      doAssert cttEthKzg_Success == ctx.compute_cells_and_kzg_proofs(
        cells[].asUnchecked(),
        proofs[].asUnchecked(),
        b.blobs[0])

  # Run benchmarks
  runNoPrecomp()

  # Parametric precompute configurations
  const PrecompConfigs: array[12, tuple[t, b: int]] = [
    (64, 6), (64, 8), (64, 10), (64, 12),
    (128, 6), (128, 8), (128, 10), (128, 12),
    (256, 6), (256, 8), (256, 10), (256, 12),
  ]

  for cfg in PrecompConfigs:
    runPrecomp(cfg.t, cfg.b)

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
    var commitments_bytes: ref array[MaxCount, array[48, byte]]
    var cell_indices: ref array[MaxCount, CellIndex]
    var cells_array: ref array[MaxCount, Cell]
    var proofs_bytes: ref array[MaxCount, KZGProofBytes]
    new(commitments_bytes)
    new(cell_indices)
    new(cells_array)
    new(proofs_bytes)
    bench(&"verify_cell_kzg_proof_batch (count={count}, 1 blob)", iters):
      for i in 0 ..< count:
        commitments_bytes[i] = b.commitments[0]
        cell_indices[i] = CellIndex(i)
        cells_array[i] = b.cells[0][i]
        proofs_bytes[i] = b.proofs[0][i]

      discard verify_cell_kzg_proof_batch(
        ctx,
        commitments_bytes[].asUnchecked(),
        cell_indices[].asUnchecked(),
        cells_array[].asUnchecked(),
        proofs_bytes[].asUnchecked(),
        count,
        secureRandomBytes)

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
    let totalCount = i * CELLS_PER_EXT_BLOB
    const MaxTotal = NumBlobs * CELLS_PER_EXT_BLOB
    var commitments_bytes: ref array[MaxTotal, array[48, byte]]
    var cell_indices: ref array[MaxTotal, CellIndex]
    var cells_array: ref array[MaxTotal, Cell]
    var proofs_bytes: ref array[MaxTotal, KZGProofBytes]
    new(commitments_bytes)
    new(cell_indices)
    new(cells_array)
    new(proofs_bytes)
    bench(&"verify_cell_kzg_proof_batch (128 cells, {i} blobs)", iters):
      var idx = 0
      for blobIdx in 0 ..< i:
        for cellIdx in 0 ..< CELLS_PER_EXT_BLOB:
          commitments_bytes[idx] = b.commitments[blobIdx]
          cell_indices[idx] = CellIndex(cellIdx)
          cells_array[idx] = b.cells[blobIdx][cellIdx]
          proofs_bytes[idx] = b.proofs[blobIdx][cellIdx]
          inc idx
      discard verify_cell_kzg_proof_batch(
        ctx,
        commitments_bytes[].asUnchecked(),
        cell_indices[].asUnchecked(),
        cells_array[].asUnchecked(),
        proofs_bytes[].asUnchecked(),
        totalCount,
        secureRandomBytes)

    i *= 2

proc benchRecoverCellsAndKZGProofs_WorstCase(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Recover from exactly 50% of cells (worst case)
  ## Corresponds to:
  ## - go-eth-kzg: RecoverCellsAndComputeKZGProofs benchmark
  ## - rust-eth-kzg: "worse-case recover_cells_and_kzg_proofs" benchmark
  ## - rust-kzg: recover_cells_and_kzg_proofs (% missing) benchmark

  bench("recover_cells_and_kzg_proofs (50% cells)", iters):
    var recovered_cells: ref array[CELLS_PER_EXT_BLOB, Cell]
    var recovered_proofs: ref array[CELLS_PER_EXT_BLOB, KZGProofBytes]
    new(recovered_cells)
    new(recovered_proofs)
    doAssert cttEthKzg_Success == recover_cells_and_kzg_proofs(
      ctx,
      recovered_cells[].asUnchecked(),
      recovered_proofs[].asUnchecked(),
      b.halfCellIndices[0].asUnchecked(),
      b.halfCells[0].asUnchecked(),
      b.halfCells[0].len)

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

      var recovered_cells: ref array[CELLS_PER_EXT_BLOB, Cell]
      var recovered_proofs: ref array[CELLS_PER_EXT_BLOB, KZGProofBytes]
      new(recovered_cells)
      new(recovered_proofs)
      doAssert cttEthKzg_Success == recover_cells_and_kzg_proofs(
        ctx,
        recovered_cells[].asUnchecked(),
        recovered_proofs[].asUnchecked(),
        cell_indices.asUnchecked(),
        cells.asUnchecked(),
        numCells)

proc benchBatchVerification_ChallengeComputation(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  ## Fiat-Shamir challenge computation for batch verification
  ## Corresponds to:
  ## - go-eth-kzg: Internal to VerifyCellKZGProofBatch
  ## - rust-eth-kzg: Internal
  ## - rust-kzg: Internal

  var secureRandomBytes {.noInit.}: array[32, byte]
  discard sysrand(secureRandomBytes)

  # Use 128 cells from first blob
  var commitments_bytes: ref array[128, array[48, byte]]
  var commitment_indices: ref array[128, int]
  var cell_indices: ref array[128, CellIndex]
  var cosets_evals: ref array[128, array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]
  var proofs_bytes: ref array[128, KZGProofBytes]
  new(commitments_bytes)
  new(commitment_indices)
  new(cell_indices)
  new(cosets_evals)
  new(proofs_bytes)

  for i in 0 ..< 128:
    commitments_bytes[i] = b.commitments[0]
    commitment_indices[i] = 0
    cell_indices[i] = CellIndex(i)
    proofs_bytes[i] = b.proofs[0][i]

  # Deserialize cells to coset evaluations
  for i in 0 ..< 128:
    let status = cellToCosetEvals(cosets_evals[i], b.cells[0][i])
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
  let tsStatus = ctx.new(TrustedSetupMainnet, kReferenceCKzg4844)
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

  ctx.delete()

when isMainModule:
  main()
