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
  ../bench_blueprint,
  std/[os, strutils, monotimes]

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

proc benchRecoverCellsAndKZGProofs(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  bench("recover_cells_and_kzg_proofs (50% availability)", iters):
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

proc main() =
  echo "PeerDAS (EIP-7594) - recover_cells_and_kzg_proofs Benchmark"
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
  let tsStatus = ctx.new(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess

  let b = BenchSet.load(benchsetFile)

  echo "Running recover_cells_and_kzg_proofs benchmark (worst case: 50% availability)..."
  echo ""

  const Iters = 10
  benchRecoverCellsAndKZGProofs(b, ctx, Iters)

  ctx.delete()

when isMainModule:
  main()