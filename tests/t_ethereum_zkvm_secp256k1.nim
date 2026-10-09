# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/LICENSE-2.0).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[importutils, unittest],
  constantine/ethereum_evm_precompiles,
  constantine/ethereum_ecdsa_signatures,
  constantine/hashes,
  constantine/math/arithmetic/finite_fields,
  constantine/math/io/[io_bigints, io_fields],
  constantine/named/algebras,
  constantine/platforms/abstractions

type ZkvmSecp256k1Fixture = object
  recoveryInput: array[97, byte]
  verifyInput: array[160, byte]
  publicKey: array[64, byte]

proc fixture(): ZkvmSecp256k1Fixture =
  privateAccess(SecretKey)
  privateAccess(PublicKey)
  privateAccess(Signature)

  var secretKey {.noinit.}: SecretKey
  secretKey.raw = Fr[Secp256k1].fromInt(1)
  var publicKey {.noinit.}: PublicKey
  publicKey.derive_pubkey(secretKey)

  let message = "Constantine zkVM secp256k1 ABI"
  var signature {.noinit.}: Signature
  signature.sign(secretKey, message.toOpenArrayByte(0, message.high), nsRfc6979)

  var digest {.noinit.}: array[32, byte]
  keccak256.hash(digest, message.toOpenArrayByte(0, message.high))
  result.publicKey.toOpenArray(0, 31).marshal(publicKey.raw.x.toBig(), bigEndian)
  result.publicKey.toOpenArray(32, 63).marshal(publicKey.raw.y.toBig(), bigEndian)
  var signatureBytes {.noinit.}: array[64, byte]
  signatureBytes.toOpenArray(0, 31).marshal(signature.r.toBig(), bigEndian)
  signatureBytes.toOpenArray(32, 63).marshal(signature.s.toBig(), bigEndian)

  result.recoveryInput.toOpenArray(0, 31).rawCopy(0, digest, 0, 32)
  result.recoveryInput.toOpenArray(33, 96).rawCopy(0, signatureBytes, 0, 64)
  result.verifyInput.toOpenArray(0, 31).rawCopy(0, digest, 0, 32)
  result.verifyInput.toOpenArray(32, 95).rawCopy(0, result.publicKey, 0, 64)
  result.verifyInput.toOpenArray(96, 159).rawCopy(0, signatureBytes, 0, 64)

proc curveOrder(): array[32, byte] =
  discard result.marshal(Fr[Secp256k1].getModulus(), bigEndian)

suite "zkVM secp256k1 ABI":
  test "happy path: deterministic sign -> ecrecover -> verify":
    let data = fixture()
    var recoveryInput = data.recoveryInput
    var recovered: array[64, byte]
    var recoveredKey: array[64, byte]

    for recid in 0'u8 .. 1'u8:
      recoveryInput[32] = recid
      check eth_zkvm_secp256k1_ecrecover(recovered, recoveryInput) == cttEVM_Success
      if recovered == data.publicKey:
        recoveredKey = recovered

    check recoveredKey == data.publicKey
    var verifyInput = data.verifyInput
    verifyInput.toOpenArray(32, 95).rawCopy(0, recoveredKey, 0, 64)
    var verified: array[1, byte]
    check eth_zkvm_secp256k1_verify(verified, verifyInput) == cttEVM_Success
    check verified[0] == 1

  test "ecrecover invalid recid not in {0,1}":
    var input = fixture().recoveryInput
    input[32] = 2
    var recovered: array[64, byte]
    check eth_zkvm_secp256k1_ecrecover(recovered, input) == cttEVM_MalformedSignature

  test "ecrecover rejects r=0":
    var input = fixture().recoveryInput
    var recovered: array[64, byte]
    input.toOpenArray(33, 64).setZero()
    check eth_zkvm_secp256k1_ecrecover(recovered, input) == cttEVM_MalformedSignature

  test "ecrecover rejects s=0":
    var input = fixture().recoveryInput
    var recovered: array[64, byte]
    input.toOpenArray(65, 96).setZero()
    check eth_zkvm_secp256k1_ecrecover(recovered, input) == cttEVM_MalformedSignature

  test "ecrecover rejects r=n":
    var input = fixture().recoveryInput
    var recovered: array[64, byte]
    input.toOpenArray(33, 64).rawCopy(0, curveOrder(), 0, 32)
    check eth_zkvm_secp256k1_ecrecover(recovered, input) == cttEVM_MalformedSignature

  test "ecrecover rejects s=n":
    var input = fixture().recoveryInput
    var recovered: array[64, byte]
    input.toOpenArray(65, 96).rawCopy(0, curveOrder(), 0, 32)
    check eth_zkvm_secp256k1_ecrecover(recovered, input) == cttEVM_MalformedSignature

  test "ecrecover rejects a canonical x without a curve point":
    var input: array[97, byte]
    input[64] = 5
    input[96] = 1
    var recovered: array[64, byte]
    check eth_zkvm_secp256k1_ecrecover(recovered, input) == cttEVM_MalformedSignature

  test "verify rejects r=0":
    var input = fixture().verifyInput
    var verified: array[1, byte]
    input.toOpenArray(96, 127).setZero()
    check eth_zkvm_secp256k1_verify(verified, input) == cttEVM_MalformedSignature

  test "verify rejects s=0":
    var input = fixture().verifyInput
    var verified: array[1, byte]
    input.toOpenArray(128, 159).setZero()
    check eth_zkvm_secp256k1_verify(verified, input) == cttEVM_MalformedSignature

  test "verify rejects r=n":
    var input = fixture().verifyInput
    var verified: array[1, byte]
    input.toOpenArray(96, 127).rawCopy(0, curveOrder(), 0, 32)
    check eth_zkvm_secp256k1_verify(verified, input) == cttEVM_MalformedSignature

  test "verify rejects s=n":
    var input = fixture().verifyInput
    var verified: array[1, byte]
    input.toOpenArray(128, 159).rawCopy(0, curveOrder(), 0, 32)
    check eth_zkvm_secp256k1_verify(verified, input) == cttEVM_MalformedSignature

  test "verify rejects off-curve public key (0,1)":
    var input = fixture().verifyInput
    input.toOpenArray(32, 95).setZero()
    input[95] = 1
    var verified: array[1, byte]
    check eth_zkvm_secp256k1_verify(verified, input) == cttEVM_PointNotOnCurve
