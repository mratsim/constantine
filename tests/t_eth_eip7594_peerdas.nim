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
  constantine/math/io/io_fields,
  constantine/math/io/io_bigints,
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

TestVectorsDir.testGen(verify_cell_kzg_proof_batch, "kzg-mainnet", testVector):
  # Parse inputs
  parseAssignList(commitmentsBytes, BYTES_PER_COMMITMENT, testVector["input"]["commitments"])

  var cellIndices: seq[int] = @[]
  for idx in testVector["input"]["cell_indices"]:
    cellIndices.add(parseInt(idx.content))

  parseAssignList(cells, BYTES_PER_CELL, testVector["input"]["cells"])
  parseAssignList(proofsBytes, BYTES_PER_PROOF, testVector["input"]["proofs"])

  # Generate secure random bytes for batch verification
  var secureRandomBytes: array[32, byte]
  for i in 0..31:
    secureRandomBytes[i] = byte(i + 1)  # Deterministic for testing

  # Call verify_cell_kzg_proof_batch
  let ok = verify_cell_kzg_proof_batch(
    ctx,
    commitmentsBytes,
    cellIndices,
    cells,
    proofsBytes,
    secureRandomBytes
  )

  stdout.write "[" & $ok & "]\n"

  # Check output
  let expectedOk = testVector["output"].content == "true"
  doAssert ok == expectedOk, block:
    "\nTest case: " & file &
    "\nExpected: " & $expectedOk &
    "\nActual:   " & $ok & "\n"

TestVectorsDir.testGen(compute_verify_cell_kzg_proof_batch_challenge, "kzg-mainnet", testVector):
  parseAssignList(commitments, BYTES_PER_COMMITMENT, testVector["input"]["commitments"])

  var commitmentIndices: seq[int] = @[]
  for idx in testVector["input"]["commitment_indices"]:
    commitmentIndices.add(parseInt(idx.content))

  var cellIndices: seq[int] = @[]
  for idx in testVector["input"]["cell_indices"]:
    cellIndices.add(parseInt(idx.content))

  var cosetsEvals: seq[array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]
  for cosetEvalsHex in testVector["input"]["cosets_evals"]:
    var evals: array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    for idx in 0 ..< FIELD_ELEMENTS_PER_CELL:
      evals[idx].fromHex(cosetEvalsHex[idx].content)
    cosetsEvals.add(evals)

  parseAssignList(proofs, BYTES_PER_PROOF, testVector["input"]["proofs"])

  let challenge = compute_verify_cell_kzg_proof_batch_challenge(
    commitments,
    commitmentIndices,
    cellIndices,
    cosetsEvals,
    proofs
  )

  stdout.write "[ok]\n"

  var expectedChallenge: Fr[BLS12_381]
  expectedChallenge.fromHex(testVector["output"].content)

  doAssert (challenge == expectedChallenge).bool, block:
    "\nTest case: " & file &
    "\nExpected: " & testVector["output"].content &
    "\nActual:   " & $challenge & "\n"

block:
  suite "Ethereum Fulu Hardfork / EIP-7594 / PeerDAS / Data Availability Sampling":
    let ctx = getTrustedSetup()

    test "compute_cells":
      ctx.test_compute_cells()

    test "compute_cells_and_kzg_proofs":
      ctx.test_compute_cells_and_kzg_proofs()

    test "recover_cells_and_kzg_proofs":
      ctx.test_recover_cells_and_kzg_proofs()

    test "verify_cell_kzg_proof_batch":
      ctx.test_verify_cell_kzg_proof_batch()

    test "compute_verify_cell_kzg_proof_batch_challenge":
      ctx.test_compute_verify_cell_kzg_proof_batch_challenge()

    ctx.trusted_setup_delete()