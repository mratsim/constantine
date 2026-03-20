# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, strutils, unittest],
  # 3rd party
  pkg/yaml,
  # Internals
  constantine/eth_eip7594_peerdas,
  constantine/ethereum_eip4844_kzg,
  constantine/serialization/[codecs, codecs_bls12_381],
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/named/algebras,
  # Test utilities
  ./testutils/eth_consensus_utils

const
  TestVectorsDir =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_eip7594_fulu_peerdas"

proc toProofBytes[N: static int](a: array[N, KZGProof]): seq[array[BYTES_PER_PROOF, byte]] =
  type EC = EC_ShortW_Aff[Fp[BLS12_381], G1]
  result.setLen(N)
  for i in 0 ..< N:
    doAssert result[i].serialize_g1_compressed(EC(a[i])) == cttCodecEcc_Success

TestVectorsDir.testGen(compute_cells, "kzg-mainnet", testVector):
  parseAssign(blob, BYTES_PER_BLOB, testVector["input"]["blob"].content)

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = compute_cells(ctx, blob[], cells)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssignList(expectedCells, BYTES_PER_CELL, testVector["output"])
    doAssert cells.len == expectedCells.len, block:
      "\nExpected cells count: " & $expectedCells.len &
      "\nActual cells count:   " & $cells.len & "\n"
    doAssert @cells == expectedCells
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(compute_cells_and_kzg_proofs, "kzg-mainnet", testVector):
  parseAssign(blob, BYTES_PER_BLOB, testVector["input"]["blob"].content)

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  var proofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let status = compute_cells_and_kzg_proofs(ctx, blob[], cells, proofs)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssignList(expectedCells, BYTES_PER_CELL, testVector["output"][0])
    parseAssignList(expectedProofs, BYTES_PER_PROOF, testVector["output"][1])
    doAssert @cells == expectedCells
    doAssert proofs.toProofBytes() == expectedProofs
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(recover_cells_and_kzg_proofs, "kzg-mainnet", testVector):
  # Skip tests without cell data
  if testVector["input"]["cell_indices"].len == 0 or testVector["input"]["cells"].len == 0:
    stdout.write "[Skipped - no cell data]\n"
    return

  var cellIndices: seq[CellIndex] = @[]
  for idx in testVector["input"]["cell_indices"]:
    cellIndices.add(CellIndex(parseInt(idx.content)))

  parseAssignList(cells, BYTES_PER_CELL, testVector["input"]["cells"])

  var recoveredCells: array[CELLS_PER_EXT_BLOB, Cell]
  var recoveredProofs: array[CELLS_PER_EXT_BLOB, KZGProof]

  let status = recover_cells_and_kzg_proofs(ctx, cellIndices, cells, recoveredCells, recoveredProofs)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssignList(expectedCells, BYTES_PER_CELL, testVector["output"][0])
    parseAssignList(expectedProofs, BYTES_PER_PROOF, testVector["output"][1])
    doAssert @recoveredCells == expectedCells
    doAssert recoveredProofs.toProofBytes() == expectedProofs
  else:
    doAssert testVector["output"].content == "null"

block:
  suite "Ethereum Fulu Hardfork / EIP-7594 / PeerDAS / Data Availability Sampling":
    let ctx = getTrustedSetup()

    test "compute_cells":
      ctx.test_compute_cells()

    test "compute_cells_and_kzg_proofs":
      ctx.test_compute_cells_and_kzg_proofs()

    test "recover_cells_and_kzg_proofs":
      ctx.test_recover_cells_and_kzg_proofs()

    ctx.trusted_setup_delete()