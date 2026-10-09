# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy Andre-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/ethereum_eip4844_kzg

# nim c -r -d:CTT_EMBEDDED_KZG tests/t_ethereum_kzg_embedded_full.nim
static:
  doAssert defined(CTT_EMBEDDED_KZG)
  doAssert not defined(CTT_KZG_VERIFICATION_ONLY)

proc testFullEmbeddedCommitment() =
  var ctx: ptr EthereumKZGContext
  doAssert ctx.newEmbedded() == tsSuccess
  defer: ctx.delete()

  var blob: Blob
  var commitment: array[BYTES_PER_COMMITMENT, byte]
  doAssert ctx.blob_to_kzg_commitment(commitment, blob) == cttEthKzg_Success
  doAssert commitment[0] == 0xc0
  for i in 1 ..< commitment.len:
    doAssert commitment[i] == 0

testFullEmbeddedCommitment()
