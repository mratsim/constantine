# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy Andre-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://opensource.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/serialization/codecs,
  constantine/ethereum_evm_precompiles,
  constantine/ethereum_eip4844_kzg

# nim c -r -d:CTT_EMBEDDED_KZG -d:CTT_KZG_VERIFICATION_ONLY tests/t_ethereum_evm_kzg_embedded.nim
static:
  doAssert defined(CTT_EMBEDDED_KZG)
  doAssert defined(CTT_KZG_VERIFICATION_ONLY)
  doAssert sizeof(EthereumKZGContext) == 384

const
  pointEvaluationInput = "01e798154708fe7789429634053cbf9f99b619f9f084048927333fce637f549b564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d3630624d25032e67a7e6a4910df5834b8fe70e6bcfeeac0352434196bdf4b2485d5a18f59a8d2a1a625a17f3fea0fe5eb8c896db3764f3185481bc22f91b4aaffcca25f26936857bc3a7c2539ea8ec3a952b7873033e038326e87ed3e1276fd140253fa08e9fc25fb2d9a98527fc22a2c9612fbeafdad446cbc7bcdbdcd780af2c16a"
  pointEvaluationExpected = "000000000000000000000000000000000000000000000000000000000000100073eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"

proc testEmbeddedPointEvaluation() =
  var ctx: ptr EthereumKZGContext
  doAssert ctx.newEmbedded() == tsSuccess
  defer: ctx.delete()

  var input: array[192, byte]
  input.fromHex(pointEvaluationInput)
  var expected: array[64, byte]
  expected.fromHex(pointEvaluationExpected)
  var output: array[64, byte]

  doAssert ctx.eth_evm_kzg_point_evaluation(output, input) == cttEVM_Success
  doAssert output == expected

  var z, y: array[32, byte]
  var commitment, proof: array[48, byte]
  for i in 0 ..< 32:
    z[i] = input[32 + i]
    y[i] = input[64 + i]
  for i in 0 ..< 48:
    commitment[i] = input[96 + i]
    proof[i] = input[144 + i]
  doAssert ctx.verify_kzg_proof(commitment, z, y, proof) == cttEthKzg_Success

testEmbeddedPointEvaluation()
