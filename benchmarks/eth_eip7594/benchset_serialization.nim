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
  ../bench_blueprint,
  # Standard library
  std/[os, strutils, sequtils, monotimes, streams]

const NumBlobs* = 64  # Number of blobs for benchmarks (full scale)

type
  BenchSet* = ref object
    blobs*: array[NumBlobs, Blob]
    commitments*: array[NumBlobs, array[48, byte]]
    cells*: array[NumBlobs, array[CELLS_PER_EXT_BLOB, Cell]]
    proofs*: array[NumBlobs, array[CELLS_PER_EXT_BLOB, KZGProofBytes]]
    # For recovery benchmarks - half cells
    halfCellIndices*: array[NumBlobs, seq[CellIndex]]
    halfCells*: array[NumBlobs, seq[Cell]]

proc newBenchSet*(): BenchSet =
  new(result)

proc serialize*(B: BenchSet, filename: string) =
  ## Serialize BenchSet to binary file
  echo &"Serializing BenchSet to {filename}..."
  let stream = openFileStream(filename, fmWrite)
  defer: stream.close()

  # Write header for validation
  let header = "PEERDAS_BENCHSET_V2"
  stream.writeData(header[0].addr, header.len)

  # Write NumBlobs
  let numBlobs = NumBlobs
  stream.writeData(numBlobs.addr, numBlobs.sizeOf)

  # Write blobs
  echo "  Writing blobs..."
  stream.writeData(B.blobs[0].addr, B.blobs.len * B.blobs[0].sizeOf)

  # Write commitments
  echo "  Writing commitments..."
  stream.writeData(B.commitments[0].addr, B.commitments.len * B.commitments[0].sizeOf)

  # Write cells
  echo "  Writing cells..."
  stream.writeData(B.cells[0].addr, B.cells.len * B.cells[0].sizeOf)

  # Write proofs
  echo "  Writing proofs..."
  stream.writeData(B.proofs[0].addr, B.proofs.len * B.proofs[0].sizeOf)

  # Write halfCellIndices (variable length)
  echo "  Writing halfCellIndices..."
  for i in 0 ..< NumBlobs:
    let len = B.halfCellIndices[i].len
    stream.writeData(len.addr, len.sizeOf)
    if len > 0:
      stream.writeData(B.halfCellIndices[i][0].addr, len * B.halfCellIndices[i][0].sizeOf)

  # Write halfCells (variable length)
  echo "  Writing halfCells..."
  for i in 0 ..< NumBlobs:
    let len = B.halfCells[i].len
    stream.writeData(len.addr, len.sizeOf)
    if len > 0:
      stream.writeData(B.halfCells[i][0].addr, len * B.halfCells[i][0].sizeOf)

  echo &"Serialization complete: {filename}"

proc load*(T: type BenchSet, filename: string): T =
  ## Load BenchSet from binary file
  echo &"Loading BenchSet from {filename}..."
  let loadStart = getMonotime()

  result = newBenchSet()
  let stream = openFileStream(filename, fmRead)
  defer: stream.close()

  # Read and verify header
  var header: array[19, char]
  let headerRead = stream.readData(header[0].addr, header.len)
  doAssert headerRead == header.len, "Truncated benchset.dat: header"
  var headerStr = newStringOfCap(header.len)
  for i in 0 ..< header.len:
    headerStr.add(header[i])
  doAssert headerStr == "PEERDAS_BENCHSET_V2", &"Invalid header: {headerStr}"

  # Read NumBlobs
  var numBlobs: int
  let numBlobsRead = stream.readData(numBlobs.addr, numBlobs.sizeOf)
  doAssert numBlobsRead == numBlobs.sizeOf, "Truncated benchset.dat: NumBlobs"
  doAssert numBlobs == NumBlobs, &"Expected {NumBlobs} blobs, got {numBlobs}"

  # Read blobs
  echo "  Reading blobs..."
  let blobsRead = stream.readData(result.blobs[0].addr, result.blobs.len * result.blobs[0].sizeOf)
  doAssert blobsRead == result.blobs.len * result.blobs[0].sizeOf, "Truncated benchset.dat: blobs"

  # Read commitments
  echo "  Reading commitments..."
  let commitmentsRead = stream.readData(result.commitments[0].addr, result.commitments.len * result.commitments[0].sizeOf)
  doAssert commitmentsRead == result.commitments.len * result.commitments[0].sizeOf, "Truncated benchset.dat: commitments"

  # Read cells
  echo "  Reading cells..."
  let cellsRead = stream.readData(result.cells[0].addr, result.cells.len * result.cells[0].sizeOf)
  doAssert cellsRead == result.cells.len * result.cells[0].sizeOf, "Truncated benchset.dat: cells"

  # Read proofs
  echo "  Reading proofs..."
  let proofsRead = stream.readData(result.proofs[0].addr, result.proofs.len * result.proofs[0].sizeOf)
  doAssert proofsRead == result.proofs.len * result.proofs[0].sizeOf, "Truncated benchset.dat: proofs"

  # Read halfCellIndices
  echo "  Reading halfCellIndices..."
  for i in 0 ..< NumBlobs:
    var len: int
    let lenRead = stream.readData(len.addr, len.sizeOf)
    doAssert lenRead == len.sizeOf, &"Truncated benchset.dat at halfCellIndices[" & $i & "] length"
    doAssert 0 <= len and len <= CELLS_PER_EXT_BLOB,
      &"Invalid halfCellIndices length: " & $len & " (blob " & $i & ")"
    result.halfCellIndices[i] = newSeq[CellIndex](len)
    if len > 0:
      let payloadBytes = len * result.halfCellIndices[i][0].sizeOf
      let payloadRead = stream.readData(result.halfCellIndices[i][0].addr, payloadBytes)
      doAssert payloadRead == payloadBytes, &"Truncated benchset.dat at halfCellIndices[" & $i & "] payload"

  # Read halfCells
  echo "  Reading halfCells..."
  for i in 0 ..< NumBlobs:
    var len: int
    let lenRead = stream.readData(len.addr, len.sizeOf)
    doAssert lenRead == len.sizeOf, &"Truncated benchset.dat at halfCells[" & $i & "] length"
    doAssert 0 <= len and len <= CELLS_PER_EXT_BLOB,
      &"Invalid halfCells length: " & $len & " (blob " & $i & ")"
    result.halfCells[i] = newSeq[Cell](len)
    if len > 0:
      let payloadBytes = len * result.halfCells[i][0].sizeOf
      let payloadRead = stream.readData(result.halfCells[i][0].addr, payloadBytes)
      doAssert payloadRead == payloadBytes, &"Truncated benchset.dat at halfCells[" & $i & "] payload"

  let loadStop = getMonotime()
  let loadTime = (loadStop - loadStart).inNanoseconds() div 1_000_000
  echo &"Loading complete in {loadTime} ms\n"