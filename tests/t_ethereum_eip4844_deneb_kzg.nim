# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, strutils, streams, unittest],
  # 3rd party
  pkg/yaml,
  # Internals
  ../constantine/serialization/codecs,
  ../constantine/ethereum_eip4844_kzg_polynomial_commitments

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

const
  TestVectorsDir =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_eip4844_deneb_kzg"

const SkippedTests = [
  ""
]

iterator walkTests*(testDir: string, skipped: var int): (string, string) =
  for file in walkDirRec(testDir, relative = true):
    if file in SkippedTests:
      echo "[WARNING] Skipping - ", file
      inc skipped
      continue

    yield (testDir, file)

proc loadVectors(filename: string): YamlNode =
  var s = filename.openFileStream()
  defer: s.close()
  load(s, result)

template testGen*(name, testData: untyped, body: untyped): untyped {.dirty.} =
  ## Generates a test proc
  ## with identifier "test_name"
  ## The test vector data is available as JsonNode under the
  ## the variable passed as `testData`
  proc `test _ name`(ctx: ptr EthereumKZGContext) =
    var count = 0 # Need to fail if walkDir doesn't return anything
    var skipped = 0
    const testdir = TestVectorsDir / astToStr(name)/"small"
    for dir, file in walkTests(testdir, skipped):
      stdout.write("       " & alignLeft(astToStr(name) & " test:", 36) & alignLeft(file, 90))
      let testData = loadVectors(dir/file)

      body

      inc count

    doAssert count > 0, "Empty or inexisting test folder: " & astToStr(name)
    if skipped > 0:
      echo "[Warning]: ", skipped, " tests skipped."

template parseAssign(dstVariable: untyped, size: static int, hexInput: string) =
  block:
    let prefixBytes = 2*int(hexInput.startsWith("0x"))
    let expectedLength = size*2 + prefixBytes
    if hexInput.len != expectedLength:
      let encodedBytes = (hexInput.len - prefixBytes) div 2
      stdout.write "[ Incorrect input length for '" &
                      astToStr(dstVariable) &
                      "': encoding " & $encodedBytes & " bytes" &
                      " instead of expected " & $size & " ]\n"

      doAssert testVector["output"].content == "null"
      # We're in a template, this shortcuts the caller `walkTests`
      continue

  var dstVariable{.inject.} = new(array[size, byte])
  dstVariable[].fromHex(hexInput)

testGen(blob_to_kzg_commitment, testVector):
  parseAssign(blob, 32*4096, testVector["input"]["blob"].content)

  var commitment: array[48, byte]

  let status = blob_to_kzg_commitment(ctx, commitment, blob[].addr)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKZG_Success:
    parseAssign(expectedCommit, 48, testVector["output"].content)
    doAssert bool(commitment == expectedCommit[]), block:
      "\ncommitment: " & commitment.toHex() &
      "\nexpected:   " & expectedCommit[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

testGen(compute_kzg_proof, testVector):
  parseAssign(blob, 32*4096, testVector["input"]["blob"].content)
  parseAssign(z, 32, testVector["input"]["z"].content)

  var proof: array[48, byte]
  var y: array[32, byte]

  let status = compute_kzg_proof(ctx, proof, y, blob[].addr, z[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKZG_Success:
    parseAssign(expectedEvalAtChallenge, 32, testVector["output"][1].content)
    parseAssign(expectedProof, 48, testVector["output"][0].content)

    doAssert bool(y == expectedEvalAtChallenge[]), block:
      "\ny (= p(z)): " & y.toHex() &
      "\nexpected:   " & expectedEvalAtChallenge[].toHex() & "\n"
    doAssert bool(proof == expectedProof[]), block:
      "\nproof:    " & proof.toHex() &
      "\nexpected: " & expectedProof[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

testGen(verify_kzg_proof, testVector):
  parseAssign(commitment, 48, testVector["input"]["commitment"].content)
  parseAssign(z,          32, testVector["input"]["z"].content)
  parseAssign(y,          32, testVector["input"]["y"].content)
  parseAssign(proof,      48, testVector["input"]["proof"].content)

  let status = verify_kzg_proof(ctx, commitment[], z[], y[], proof[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKZG_Success:
    doAssert testVector["output"].content == "true"
  elif status == cttEthKZG_VerificationFailure:
    doAssert testVector["output"].content == "false"
  else:
    doAssert testVector["output"].content == "null"

testGen(compute_blob_kzg_proof, testVector):
  parseAssign(blob,  32*4096, testVector["input"]["blob"].content)
  parseAssign(commitment, 48, testVector["input"]["commitment"].content)

  var proof: array[48, byte]

  let status = compute_blob_kzg_proof(ctx, proof, blob[].addr, commitment[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKZG_Success:
    parseAssign(expectedProof, 48, testVector["output"].content)

    doAssert bool(proof == expectedProof[]), block:
      "\nproof:    " & proof.toHex() &
      "\nexpected: " & expectedProof[].toHex() & "\n"
  else:
    doAssert testVector["output"].content == "null"

testGen(verify_blob_kzg_proof, testVector):
  parseAssign(blob,  32*4096, testVector["input"]["blob"].content)
  parseAssign(commitment, 48, testVector["input"]["commitment"].content)
  parseAssign(proof,      48, testVector["input"]["proof"].content)

  let status = verify_blob_kzg_proof(ctx, blob[].addr, commitment[], proof[])
  stdout.write "[" & $status & "]\n"

  if status == cttEthKZG_Success:
    doAssert testVector["output"].content == "true"
  elif status == cttEthKZG_VerificationFailure:
    doAssert testVector["output"].content == "false"
  else:
    doAssert testVector["output"].content == "null"

block:
  suite "Ethereum Deneb Hardfork / EIP-4844 / Proto-Danksharding / KZG Polynomial Commitments":
    let ctx = load_ethereum_kzg_test_trusted_setup_mainnet()

    test "blob_to_kzg_commitment(dst: var array[48, byte], blob: ptr array[4096, byte])":
      ctx.test_blob_to_kzg_commitment()

    test "compute_kzg_proof(proof: var array[48, byte], y: var array[32, byte], blob: ptr array[4096, byte], z: array[32, byte])":
      ctx.test_compute_kzg_proof()

    test "verify_kzg_proof(commitment: array[48, byte], z, y: array[32, byte], proof: array[48, byte]) -> bool":
      ctx.test_verify_kzg_proof()

    test "compute_blob_kzg_proof(proof: var array[48, byte], blob: ptr array[4096, byte], commitment: array[48, byte])":
      ctx.test_compute_blob_kzg_proof()

    test "verify_blob_kzg_proof(blob: ptr array[4096, byte], commitment: array[48, byte], proof: var array[48, byte])":
      ctx.test_verify_blob_kzg_proof()

    ctx.delete()
