# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, strutils, streams],
  # 3rd party
  pkg/yaml,
  # Internals
  ../constantine/serialization/codecs,
  ../constantine/ethereum_kzg_polynomial_commitments

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
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_deneb_kzg"
  VerifyKzgTestDir =
    TestVectorsDir / "verify_kzg_proof" / "small"

proc loadVectors(filename: string): YamlNode =
  var s = filename.openFileStream()
  defer: s.close()
  load(s, result)

proc testVerifyKzgProof(ctx: ptr EthereumKZGContext, filename: string) =
  let tv = loadVectors(VerifyKzgTestDir / filename / "data.yaml")

  let
    commitment = array[48, byte].fromHex(tv["input"]["commitment"].content)
    z = array[32, byte].fromHex(tv["input"]["z"].content)
    y = array[32, byte].fromHex(tv["input"]["y"].content)
    proof = array[48, byte].fromHex(tv["input"]["proof"].content)

  stdout.write("       " & "verify_kzg_proof" & " test: " & alignLeft(filename, 70))
  let status = ctx.verify_kzg_proof(commitment, z, y, proof)
  stdout.write "[" & $status & "]\n"

  if status == cttEthKZG_Success:
    doAssert tv["output"].content == "true"
  elif status == cttEthKZG_VerificationFailure:
    doAssert tv["output"].content == "false"
  else:
    doAssert tv["output"].content == "null"

block:
  let ctx = load_ethereum_kzg_test_trusted_setup_mainnet()

  ctx.testVerifyKzgProof("verify_kzg_proof_case_correct_proof_0b16242de3e9c686")
  ctx.testVerifyKzgProof("verify_kzg_proof_case_incorrect_proof_0b16242de3e9c686")

  ctx.delete()
