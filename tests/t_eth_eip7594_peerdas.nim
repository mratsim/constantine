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
  constantine/eth_eip7594_peerdas {.all.},
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

TestVectorsDir.testGen(compute_cells, "kzg-mainnet", testVector):
  parseAssign(testVector, blob, BYTES_PER_BLOB, testVector["input"]["blob"].content)

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  let status = compute_cells(ctx, cells, blob[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssignList(testVector, expectedCells, BYTES_PER_CELL, testVector["output"])
    doAssert cells.len == expectedCells.len, block:
      "\nExpected cells count: " & $expectedCells.len &
      "\nActual cells count:   " & $cells.len & "\n"
    doAssert @cells == expectedCells
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(compute_cells_and_kzg_proofs, "kzg-mainnet", testVector):
  parseAssign(testVector, blob, BYTES_PER_BLOB, testVector["input"]["blob"].content)

  var cells: array[CELLS_PER_EXT_BLOB, Cell]
  var proofs: array[CELLS_PER_EXT_BLOB, KZGProofBytes]

  let status = compute_cells_and_kzg_proofs(ctx, cells.asUnchecked(), proofs.asUnchecked(), blob[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssignList(testVector, expectedCells, BYTES_PER_CELL, testVector["output"][0])
    parseAssignList(testVector, expectedProofs, BYTES_PER_PROOF, testVector["output"][1])
    doAssert @cells == expectedCells
    doAssert @proofs == expectedProofs

  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(recover_cells_and_kzg_proofs, "kzg-mainnet", testVector):
  var cellIndices: seq[CellIndex] = @[]
  for idx in testVector["input"]["cell_indices"]:
    cellIndices.add(CellIndex(parseInt(idx.content)))

  parseAssignList(testVector, cells, BYTES_PER_CELL, testVector["input"]["cells"])

  # Input length mismatch (cells vs cell_indices) = invalid input
  if cellIndices.len != cells.len:
    stdout.write "[ cttEthKzg_InputsLengthsMismatch]\n"
    doAssert testVector["output"].content == "null",
      "Expected null output for length mismatch"
    return

  var recoveredCells: array[CELLS_PER_EXT_BLOB, Cell]
  var recoveredProofs: array[CELLS_PER_EXT_BLOB, KZGProofBytes]

  let status = recover_cells_and_kzg_proofs(ctx, recoveredCells.asUnchecked(), recoveredProofs.asUnchecked(), cellIndices.asUnchecked(), cells.asUnchecked(), cellIndices.len)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssignList(testVector, expectedCells, BYTES_PER_CELL, testVector["output"][0])
    parseAssignList(testVector, expectedProofs, BYTES_PER_PROOF, testVector["output"][1])
    doAssert @recoveredCells == expectedCells
    doAssert @recoveredProofs == expectedProofs
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(verify_cell_kzg_proof_batch, "kzg-mainnet", testVector):
  # Parse inputs
  parseAssignList(testVector, commitmentsBytes, BYTES_PER_COMMITMENT, testVector["input"]["commitments"])

  var cellIndices: seq[CellIndex] = @[]
  for idx in testVector["input"]["cell_indices"]:
    cellIndices.add(CellIndex(parseInt(idx.content)))

  parseAssignList(testVector, cells, BYTES_PER_CELL, testVector["input"]["cells"])
  parseAssignList(testVector, proofsBytes, BYTES_PER_PROOF, testVector["input"]["proofs"])

  # Input length mismatch = invalid input
  # Library receives ptr UncheckedArray and cannot know multiple array lengths
  if commitmentsBytes.len != cellIndices.len or
     commitmentsBytes.len != cells.len or
     commitmentsBytes.len != proofsBytes.len:
    stdout.write "[ cttEthKzg_InputsLengthsMismatch]\n"
    doAssert testVector["output"].content == "null",
      "\nTest case: " & file &
      "\nExpected: invalid input error (output=\"null\")" &
      "\nActual: length mismatch detected in test harness\n"
    return

  # Generate secure random bytes for batch verification
  var secureRandomBytes: array[32, byte]
  for i in 0..31:
    secureRandomBytes[i] = byte(i + 1)  # Deterministic for testing

  let status = verify_cell_kzg_proof_batch(
    ctx,
    commitmentsBytes.asUnchecked(),
    cellIndices.asUnchecked(),
    cells.asUnchecked(),
    proofsBytes.asUnchecked(),
    cells.len,
    secureRandomBytes
  )
  stdout.write "[" & $status & "]\n"

  # Check output - tri-state: "true" (success), "false" (verification failure), "null" (invalid input)
  let outputStr = testVector["output"].content
  if outputStr == "true":
    doAssert status == cttEthKzg_Success, block:
      "\nTest case: " & file &
      "\nExpected: verification success (output=\"true\")" &
      "\nActual:   status=" & $status & "\n"
  elif outputStr == "false":
    # Verification failure - some proofs/cells/commitments are incorrect
    doAssert status == cttEthKzg_VerificationFailure, block:
      "\nTest case: " & file &
      "\nExpected: verification failure (output=\"false\")" &
      "\nActual:   status=" & $status & "\n"
  elif outputStr == "null":
    # Invalid input (malformed data, length mismatch, deserialization errors)
    # Note: Empty input is valid per EIP-7594 spec (returns Success), so should not be labeled "null"
    doAssert status != cttEthKzg_Success and status != cttEthKzg_VerificationFailure, block:
      "\nTest case: " & file &
      "\nExpected: invalid input error (output=\"null\")" &
      "\nActual:   status=" & $status &
      "\nExpected status: one of the input/deserialization error codes\n"
  else:
    doAssert false, "\nTest case: " & file & "\nUnexpected output value: " & outputStr

TestVectorsDir.testGen(compute_verify_cell_kzg_proof_batch_challenge, "kzg-mainnet", testVector):
  parseAssignList(testVector, commitments, BYTES_PER_COMMITMENT, testVector["input"]["commitments"])

  var commitmentIndices: seq[int] = @[]
  for idx in testVector["input"]["commitment_indices"]:
    commitmentIndices.add(parseInt(idx.content))

  var cellIndices: seq[CellIndex] = @[]
  for idx in testVector["input"]["cell_indices"]:
    cellIndices.add(CellIndex(parseInt(idx.content)))

  var cosetsEvals: seq[array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]]
  for cosetEvalsHex in testVector["input"]["cosets_evals"]:
    var evals: array[FIELD_ELEMENTS_PER_CELL, Fr[BLS12_381]]
    for idx in 0 ..< FIELD_ELEMENTS_PER_CELL:
      evals[idx].fromHex(cosetEvalsHex[idx].content)
    cosetsEvals.add(evals)

  parseAssignList(testVector, proofs, BYTES_PER_PROOF, testVector["input"]["proofs"])

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


# Dedicated tests for deduplicateCommitments function
suite "deduplicateCommitments":
  # Helper to create test commitments (48-byte arrays)
  proc makeTestCommitment(seed: uint8): array[BYTES_PER_COMMITMENT, byte] =
    # Create deterministic 48-byte commitment from seed
    # In production these would be real KZG commitments
    result[0] = seed
    for i in 1 ..< BYTES_PER_COMMITMENT:
      result[i] = byte((seed + uint8(i)) * 31)  # Simple mixing

  test "Empty input":
    var commitmentIdx: array[0, int]
    var firstOccurrence: array[0, int]
    var commitments: array[0, array[BYTES_PER_COMMITMENT, byte]]
    check deduplicateCommitments(commitmentIdx, commitments, firstOccurrence) == 0

  test "Single commitment":
    var commitmentIdx: array[1, int]
    var firstOccurrence: array[1, int]
    var commitments = [makeTestCommitment(1)]
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == 1
    check commitmentIdx[0] == 0
    check firstOccurrence[0] == 0

  test "All identical commitments":
    var commitmentIdx: array[4, int]
    var firstOccurrence: array[4, int]
    var commitments = [
      makeTestCommitment(1),
      makeTestCommitment(1),
      makeTestCommitment(1),
      makeTestCommitment(1)
    ]
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == 1
    check commitmentIdx == [0, 0, 0, 0]
    check firstOccurrence[0] == 0

  test "All unique commitments":
    var commitmentIdx: array[4, int]
    var firstOccurrence: array[4, int]
    var commitments = [
      makeTestCommitment(1),
      makeTestCommitment(2),
      makeTestCommitment(3),
      makeTestCommitment(4)
    ]
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == 4
    check commitmentIdx == [0, 1, 2, 3]
    check firstOccurrence == [0, 1, 2, 3]

  test "Non-consecutive duplicates":
    # Input: [A, A, B, B] should produce unique=[A, B], indices=[0, 0, 1, 1]
    var commitmentIdx: array[4, int]
    var firstOccurrence: array[4, int]
    let A = makeTestCommitment(1)
    let B = makeTestCommitment(2)
    var commitments = [A, A, B, B]
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == 2
    check commitmentIdx == [0, 0, 1, 1]
    check firstOccurrence[0] == 0
    check firstOccurrence[1] == 2

  test "Interleaved duplicates":
    # Input: [A, B, A, B, C, A] should produce unique=[A, B, C], indices=[0, 1, 0, 1, 2, 0]
    var commitmentIdx: array[6, int]
    var firstOccurrence: array[6, int]
    let A = makeTestCommitment(1)
    let B = makeTestCommitment(2)
    let C = makeTestCommitment(3)
    var commitments = [A, B, A, B, C, A]
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == 3
    check commitmentIdx == [0, 1, 0, 1, 2, 0]
    check firstOccurrence[0] == 0
    check firstOccurrence[1] == 1
    check firstOccurrence[2] == 4

  test "Duplicates at end":
    # Input: [A, B, C, A, A] should produce unique=[A, B, C], indices=[0, 1, 2, 0, 0]
    var commitmentIdx: array[5, int]
    var firstOccurrence: array[5, int]
    let A = makeTestCommitment(1)
    let B = makeTestCommitment(2)
    let C = makeTestCommitment(3)
    var commitments = [A, B, C, A, A]
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == 3
    check commitmentIdx == [0, 1, 2, 0, 0]
    check firstOccurrence[0] == 0
    check firstOccurrence[1] == 1
    check firstOccurrence[2] == 2

  test "Large input with many duplicates":
    # Simulate realistic PeerDAS scenario: 32 cells, 8 unique commitments
    const N = 32
    const M = 8
    var commitmentIdx: array[N, int]
    var firstOccurrence: array[N, int]
    var commitments: array[N, array[BYTES_PER_COMMITMENT, byte]]

    # Create pattern: each commitment repeated 4 times
    for i in 0 ..< N:
      commitments[i] = makeTestCommitment(uint8(i mod M))
    let numUnique = deduplicateCommitments(commitmentIdx, commitments, firstOccurrence)
    check numUnique == M

    # Verify indices are correct
    for i in 0 ..< N:
      check commitmentIdx[i] == (i mod M)

    # Verify first occurrence indices
    for j in 0 ..< M:
      check firstOccurrence[j] == j


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
