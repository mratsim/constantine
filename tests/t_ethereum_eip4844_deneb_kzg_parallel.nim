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
  constantine/ethereum_eip4844_kzg_parallel,
  constantine/threadpool/threadpool,
  # Test utilities
  ./testutils/eth_consensus_utils

# Organization
#
# We choose not to use a type schema here, unlike with the other json-based tests
# like:
# - t_ethereum_bls_signatures
# - t_ethereum_evem_precompiles
#
# They'll add a lot of verbosity due to all the KZG types
# and failure modes (subgroups, ...)
# https://nimyaml.org/serialization.html

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

const
  TestVectorsDir =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_eip4844_deneb_kzg"

TestVectorsDir.testGenPar(blob_to_kzg_commitment, "kzg-mainnet", testVector):
  parseAssign(testVector, blob, 32*4096, testVector["input"]["blob"].content)

  var commitment: array[48, byte]

  let status = tp.blob_to_kzg_commitment_parallel(ctx, commitment, blob[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssign(testVector, expectedCommit, 48, testVector["output"].content)
    doAssert bool(commitment == expectedCommit[]), block:
      "\ncommitment: " & commitment.toHex() &
      "\nexpected:   " & expectedCommit[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGenPar(compute_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, blob, 32*4096, testVector["input"]["blob"].content)
  parseAssign(testVector, z, 32, testVector["input"]["z"].content)

  var proof: array[48, byte]
  var y: array[32, byte]

  let status = compute_kzg_proof_parallel(tp, ctx, proof, y, blob[], z[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssign(testVector, expectedEvalAtChallenge, 32, testVector["output"][1].content)
    parseAssign(testVector, expectedProof, 48, testVector["output"][0].content)

    doAssert bool(y == expectedEvalAtChallenge[]), block:
      "\ny (= p(z)): " & y.toHex() &
      "\nexpected:   " & expectedEvalAtChallenge[].toHex() & "\n"
    doAssert bool(proof == expectedProof[]), block:
      "\nproof:    " & proof.toHex() &
      "\nexpected: " & expectedProof[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

# Test is not parallel
# testGenPar(verify_kzg_proof, testVector):
#   parseAssign(testVector, commitment, 48, testVector["input"]["commitment"].content)
#   parseAssign(testVector, z,          32, testVector["input"]["z"].content)
#   parseAssign(testVector, y,          32, testVector["input"]["y"].content)
#   parseAssign(testVector, proof,      48, testVector["input"]["proof"].content)
#
#   let status = ctx.verify_kzg_proof(commitment[], z[], y[], proof[])
#   stdout.write "[" & $status & "]\n"
#
#   if status == cttEthKzg_Success:
#     doAssert testVector["output"].content == "true"
#   elif status == cttEthKzg_VerificationFailure:
#     doAssert testVector["output"].content == "false"
#   else:
#     doAssert testVector["output"].content == "null"

TestVectorsDir.testGenPar(compute_blob_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, blob,  32*4096, testVector["input"]["blob"].content)
  parseAssign(testVector, commitment, 48, testVector["input"]["commitment"].content)

  var proof: array[48, byte]

  let status = compute_blob_kzg_proof_parallel(tp, ctx, proof, blob[], commitment[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    parseAssign(testVector, expectedProof, 48, testVector["output"].content)

    doAssert bool(proof == expectedProof[]), block:
      "\nproof:    " & proof.toHex() &
      "\nexpected: " & expectedProof[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGenPar(verify_blob_kzg_proof, "kzg-mainnet", testVector):
  parseAssign(testVector, blob,  32*4096, testVector["input"]["blob"].content)
  parseAssign(testVector, commitment, 48, testVector["input"]["commitment"].content)
  parseAssign(testVector, proof,      48, testVector["input"]["proof"].content)

  let status = verify_blob_kzg_proof_parallel(tp, ctx, blob[], commitment[], proof[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKzg_Success:
    doAssert testVector["output"].content == "true"
  elif status == cttEthKzg_VerificationFailure:
    doAssert testVector["output"].content == "false"
  else:
    doAssert testVector["output"].content == "null"

TestVectorsDir.testGenPar(verify_blob_kzg_proof_batch, "kzg-mainnet", testVector):
  parseAssignList(testVector, blobs,  32*4096, testVector["input"]["blobs"])
  parseAssignList(testVector, commitments, 48, testVector["input"]["commitments"])
  parseAssignList(testVector, proofs,      48, testVector["input"]["proofs"])

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

  let status = verify_blob_kzg_proof_batch_parallel(
                 tp,
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
  suite "Ethereum Deneb Hardfork / EIP-4844 / Proto-Danksharding / KZG Polynomial Commitments (Parallel)":
    let ctx = trusted_setup()
    let tp = Threadpool.new()

    test "blob_to_kzg_commitment_parallel(dst: var array[48, byte], blob: ptr array[4096, byte])":
      test_blob_to_kzg_commitment(ctx, tp)

    test "compute_kzg_proof_parallel(proof: var array[48, byte], y: var array[32, byte], blob: ptr array[4096, byte], z: array[32, byte])":
      test_compute_kzg_proof(ctx, tp)

    # Not parallelized
    # test "verify_kzg_proof(commitment: array[48, byte], z, y: array[32, byte], proof: array[48, byte]) -> bool":
    #   ctx.test_verify_kzg_proof()

    test "compute_blob_kzg_proof_parallel(proof: var array[48, byte], blob: ptr array[4096, byte], commitment: array[48, byte])":
      test_compute_blob_kzg_proof(ctx, tp)

    test "verify_blob_kzg_proof_parallel(blob: ptr array[4096, byte], commitment, proof: array[48, byte])":
      test_verify_blob_kzg_proof(ctx, tp)

    test "verify_blob_kzg_proof_batch_parallel(blobs: ptr UncheckedArray[array[4096, byte]], commitments, proofs: ptr UncheckedArray[array[48, byte]], n: int, secureRandomBytes: array[32, byte])":
      test_verify_blob_kzg_proof_batch(ctx, tp)

    tp.shutdown()
    ctx.trusted_setup_delete()
