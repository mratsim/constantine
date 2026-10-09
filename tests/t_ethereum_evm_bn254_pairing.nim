# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/serialization/codecs,
  constantine/ethereum_evm_precompiles,
  std/unittest

# EIP-197: ecPairing precompile (address 0x08)
# Tests for pairing checks including identity / infinity handling.
#
# A point at infinity in a pair evaluates to the identity in GT: e(P, O) = 1, e(O, Q) = 1.
# In a multi-pairing prod_{i} e(P_i, Q_i) == 1, pairing with infinity must NOT cause
# the whole check to return 1 (success) if the remaining pairs evaluate to != 1.

const
  # Generator G1: (1, 2)
  G1_Gen = "0000000000000000000000000000000000000000000000000000000000000001" &
           "0000000000000000000000000000000000000000000000000000000000000002"

  # Generator G2 in EIP-197 (x1, x0, y1, y0)
  G2_Gen = "198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2" &
           "1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed" &
           "090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b" &
           "12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa"

  # -G2 generator (negated y coordinates: p - y)
  G2_Gen_Neg = "198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2" &
               "1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed" &
               "275dc4a288d1afb3cbb1ac09187524c7db36395df7be3b99e673b13a075a65ec" &
               "1d9befcd05a5323e6da4d435f3b617cdb3af83285c2df711ef39c01571827f9d"

  # Infinity points (all zero coordinates per EIP-197)
  G1_Infinity = "0000000000000000000000000000000000000000000000000000000000000000" &
                "0000000000000000000000000000000000000000000000000000000000000000"

  G2_Infinity = "0000000000000000000000000000000000000000000000000000000000000000" &
                "0000000000000000000000000000000000000000000000000000000000000000" &
                "0000000000000000000000000000000000000000000000000000000000000000" &
                "0000000000000000000000000000000000000000000000000000000000000000"

  Pair_Infinity = G1_Infinity & G2_Infinity
  Pair_NonTrivial_NonIdentity = G1_Gen & G2_Gen
  Pair_Cancelling = G1_Gen & G2_Gen_Neg

proc runPairing(hexInput: string): (CttEVMStatus, seq[byte]) =
  var inBytes = newSeq[byte](hexInput.len div 2)
  if hexInput.len > 0:
    inBytes.fromHex(hexInput)
  var outBytes = newSeq[byte](32)
  let status = eth_evm_bn254_ecpairingcheck(outBytes, inBytes)
  return (status, outBytes)

proc expectResult(hexInput: string, expectedVal: byte) =
  let (status, outBytes) = runPairing(hexInput)
  check status == cttEVM_Success
  var expected = newSeq[byte](32)
  expected[31] = expectedVal
  check outBytes == expected

suite "EVM BN254 Pairing precompile (EIP-197) - Infinity handling regression":
  test "Single non-identity pair e(G1, G2) != 1 returns 0":
    expectResult(Pair_NonTrivial_NonIdentity, 0)

  test "REGRESSION: Failing pair + appended infinity pair e(G1,G2)*e(O,O) != 1 must return 0":
    # Under the bug, foundInfinity was set to true, causing the function to return 1.
    expectResult(Pair_NonTrivial_NonIdentity & Pair_Infinity, 0)

  test "REGRESSION: Prepended infinity pair + failing pair e(O,O)*e(G1,G2) != 1 must return 0":
    expectResult(Pair_Infinity & Pair_NonTrivial_NonIdentity, 0)

  test "REGRESSION: Failing pair + infinity on G1 e(G1,G2)*e(O,G2) != 1 must return 0":
    expectResult(Pair_NonTrivial_NonIdentity & G1_Infinity & G2_Gen, 0)

  test "REGRESSION: Failing pair + infinity on G2 e(G1,G2)*e(G1,O) != 1 must return 0":
    expectResult(Pair_NonTrivial_NonIdentity & G1_Gen & G2_Infinity, 0)

  test "Valid cancelling pair e(G1,G2)*e(G1,-G2) == 1 returns 1":
    expectResult(Pair_NonTrivial_NonIdentity & Pair_Cancelling, 1)

  test "Valid cancelling pair + infinity pair e(G1,G2)*e(G1,-G2)*e(O,O) == 1 returns 1":
    expectResult(Pair_NonTrivial_NonIdentity & Pair_Cancelling & Pair_Infinity, 1)

  test "Only infinity pair e(O,O) == 1 returns 1":
    expectResult(Pair_Infinity, 1)

  test "Multiple infinity pairs e(O,O)*e(O,O) == 1 returns 1":
    expectResult(Pair_Infinity & Pair_Infinity, 1)

  test "Empty input (0 pairs) returns 1 per EIP-197":
    expectResult("", 1)
