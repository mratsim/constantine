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

proc benchComputeCells(b: BenchSet, ctx: ptr EthereumKZGContext, iters: int) =
  bench("compute_cells", iters):
    var cells {.noInit.}: ref array[CELLS_PER_EXT_BLOB, Cell]
    new(cells)
    doAssert cttEthKzg_Success == ctx.compute_cells(cells[], b.blobs[0])

proc main() =
  echo "PeerDAS (EIP-7594) - compute_cells Benchmark"
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

  echo "Running compute_cells benchmark..."
  echo ""
  
  const Iters = 100
  benchComputeCells(b, ctx, Iters)

  ctx.trusted_setup_delete()

when isMainModule:
  main()