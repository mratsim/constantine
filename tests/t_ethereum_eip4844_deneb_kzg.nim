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
  # Internals
  constantine/hashes,
  constantine/serialization/codecs,
  constantine/ethereum_eip4844_kzg,
  # Test utilities
  ./testutils/eth_consensus_utils

# Organization
#
# We choose not to use a type schema here, unlike with the other json-based tests
# like:
# - t_ethereum_bls_signatures
# - t_ethereum_evm_precompiles
#
# They'll add a lot of verbosity due to all the KZG types
# and failure modes (subgroups, ...)
# https://nimyaml.org/serialization.html

const
  TestVectorsDir =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_eip4844_deneb_kzg"

TestVectorsDir.testGen(blob_to_kzg_commitment, "kzg-mainnet", testVector):
  parseAssign(testVector, blob, BYTES_PER_BLOB, testVector["input"]["blob"].content)

  var commitment: array[BYTES_PER_COMMITMENT, byte]

  let status = blob_to_kzg_commitment(ctx, commitment, blob[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssign(testVector, expectedCommit, 48, testVector["output"].content)
    doAssert bool(commitment == expectedCommit[]), block:
      "\ncommitment: " & commitment.toHex() &
      "\nexpected:   " & expectedCommit[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(compute_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, blob, BYTES_PER_BLOB, testVector["input"]["blob"].content)
  parseAssign(testVector, z, BYTES_PER_FIELD_ELEMENT, testVector["input"]["z"].content)

  var proof: array[BYTES_PER_PROOF, byte]
  var y: array[BYTES_PER_FIELD_ELEMENT, byte]

  let status = compute_kzg_proof(ctx, proof, y, blob[], z[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssign(testVector, expectedProof, BYTES_PER_PROOF, testVector["output"][0].content)
    parseAssign(testVector, expectedEvalAtChallenge, BYTES_PER_FIELD_ELEMENT, testVector["output"][1].content)

    doAssert bool(proof == expectedProof[]), block:
      "\nproof:    " & proof.toHex() &
      "\nexpected: " & expectedProof[].toHex() & "\n"
    doAssert bool(y == expectedEvalAtChallenge[]), block:
      "\ny (= p(z)): " & y.toHex() &
      "\nexpected:   " & expectedEvalAtChallenge[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(verify_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, commitment, BYTES_PER_COMMITMENT, testVector["input"]["commitment"].content)
  parseAssign(testVector, z,          BYTES_PER_FIELD_ELEMENT, testVector["input"]["z"].content)
  parseAssign(testVector, y,          BYTES_PER_FIELD_ELEMENT, testVector["input"]["y"].content)
  parseAssign(testVector, proof,      BYTES_PER_PROOF, testVector["input"]["proof"].content)

  let status = verify_kzg_proof(ctx, commitment[], z[], y[], proof[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    doAssert testVector["output"].content == "true"
  elif status == cttEthKzg_VerificationFailure:
    doAssert testVector["output"].content == "false"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(compute_blob_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, blob,  BYTES_PER_BLOB, testVector["input"]["blob"].content)
  parseAssign(testVector, commitment, BYTES_PER_COMMITMENT, testVector["input"]["commitment"].content)

  var proof: array[BYTES_PER_PROOF, byte]

  let status = compute_blob_kzg_proof(ctx, proof, blob[], commitment[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssign(testVector, expectedProof, 48, testVector["output"].content)

    doAssert bool(proof == expectedProof[]), block:
      "\nproof:    " & proof.toHex() &
      "\nexpected: " & expectedProof[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(verify_blob_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, blob,  BYTES_PER_BLOB, testVector["input"]["blob"].content)
  parseAssign(testVector, commitment, BYTES_PER_COMMITMENT, testVector["input"]["commitment"].content)
  parseAssign(testVector, proof,      BYTES_PER_PROOF, testVector["input"]["proof"].content)

  let status = verify_blob_kzg_proof(ctx, blob[], commitment[], proof[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    doAssert testVector["output"].content == "true"
  elif status == cttEthKzg_VerificationFailure:
    doAssert testVector["output"].content == "false"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGen(verify_blob_kzg_proof_batch, "kzg-mainnet", testVector):
  parseAssignList(testVector, blobs,  BYTES_PER_BLOB, testVector["input"]["blobs"])
  parseAssignList(testVector, commitments, BYTES_PER_COMMITMENT, testVector["input"]["commitments"])
  parseAssignList(testVector, proofs,      BYTES_PER_PROOF, testVector["input"]["proofs"])

  if blobs.len != commitments.len:
    stdout.write "[ Length mismatch between blobs and commitments ]\n"
    doAssert testVector["output"].content == "null"
    return
  if blobs.len != proofs.len:
    stdout.write "[ Length mismatch between blobs and proofs ]\n"
    doAssert testVector["output"].content == "null"
    return

  # For reproducibility/debugging we don't use the CSPRNG here
  var randomBlinding {.noInit.}: array[32, byte]
  sha256.hash(randomBlinding, "The wizard quickly jinxed the gnomes before they vaporized.")

  template asUnchecked[T](a: openArray[T]): ptr UncheckedArray[T] =
    if a.len > 0:
      cast[ptr UncheckedArray[T]](a[0].unsafeAddr)
    else:
      nil

  let status = verify_blob_kzg_proof_batch(
                 ctx,
                 blobs.asUnchecked(),
                 commitments.asUnchecked(),
                 proofs.asUnchecked(),
                 blobs.len,
                 randomBlinding)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    doAssert testVector["output"].content == "true"
  elif status == cttEthKzg_VerificationFailure:
    doAssert testVector["output"].content == "false"
  else:
    doAssert testVector["output"].content == "null"

block:
  suite "Ethereum Deneb Hardfork / EIP-4844 / Proto-Danksharding / KZG Polynomial Commitments":
    let ctx = getTrustedSetup()

    test "blob_to_kzg_commitment(dst: var array[48, byte], blob: ptr array[4096, byte])":
      ctx.test_blob_to_kzg_commitment()

    test "compute_kzg_proof(proof: var array[48, byte], y: var array[32, byte], blob: ptr array[4096, byte], z: array[32, byte])":
      ctx.test_compute_kzg_proof()

    test "verify_kzg_proof(commitment: array[48, byte], z, y: array[32, byte], proof: array[48, byte]) -> bool":
      ctx.test_verify_kzg_proof()

    test "compute_blob_kzg_proof(proof: var array[48, byte], blob: ptr array[4096, byte], commitment: array[48, byte])":
      ctx.test_compute_blob_kzg_proof()

    test "verify_blob_kzg_proof(blob: ptr array[4096, byte], commitment, proof: array[48, byte])":
      ctx.test_verify_blob_kzg_proof()

    test "verify_blob_kzg_proof_batch(blobs: ptr UncheckedArray[array[4096, byte]], commitments, proofs: ptr UncheckedArray[array[48, byte]], n: int, secureRandomBytes: array[32, byte])":
      ctx.test_verify_blob_kzg_proof_batch()

    ctx.trusted_setup_delete()
