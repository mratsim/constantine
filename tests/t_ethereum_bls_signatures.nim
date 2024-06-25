# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[os, unittest, strutils],
  pkg/jsony,
  constantine/ethereum_bls_signatures_parallel,
  constantine/serialization/codecs,
  constantine/hashes,
  constantine/threadpool/threadpool

type
  # https://github.com/ethereum/bls12-381-tests/blob/master/formats/

  PubkeyField = object
    pubkey: array[48, byte]
  DeserG1_test = object
    input: PubkeyField
    output: bool

  SignatureField =object
    signature: array[96, byte]
  DeserG2_test = object
    input: SignatureField
    output: bool

  InputSign = object
    privkey: array[32, byte]
    message: array[32, byte]
  Sign_test = object
    input: InputSign
    output: array[96, byte]

  InputVerify = object
    pubkey: array[48, byte]
    message: array[32, byte]
    signature: array[96, byte]
  Verify_test = object
    input: InputVerify
    output: bool

  InputFastAggregateVerify = object
    pubkeys: seq[array[48, byte]]
    message: array[32, byte]
    signature: array[96, byte]
  FastAggregateVerify_test = object
    input: InputFastAggregateVerify
    output: bool

  InputAggregateVerify = object
    pubkeys: seq[array[48, byte]]
    messages: seq[array[32, byte]]
    signature: array[96, byte]
  AggregateVerify_test = object
    input: InputAggregateVerify
    output: bool

  InputBatchVerify = object
    pubkeys: seq[array[48, byte]]
    messages: seq[array[32, byte]]
    signatures: seq[array[96, byte]]
  BatchVerify_test = object
    input: InputBatchVerify
    output: bool

proc parseHook*[N: static int](src: string, pos: var int, value: var array[N, byte]) =
  var str: string
  parseHook(src, pos, str)
  value.paddedFromHex(str, bigEndian)

const SkippedTests = [
  # By construction, input MUST be 48 bytes, which is enforced at the type-system level.
  "deserialization_fails_too_many_bytes.json"
]

const TestDir = currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_blssig_pop_on_bls12381_g2_test_vectors_v0.1.1"

iterator walkTests*(category: string, skipped: var int): (string, string) =
  let testDir = TestDir/category

  for file in walkDirRec(testDir, relative = true):
    if file in SkippedTests:
      echo "[WARNING] Skipping - ", file
      inc skipped
      continue

    yield (testDir, file)

template testGen*(name, testData, TestType, body: untyped): untyped =
  ## Generates a test proc
  ## with identifier "test_name"
  ## The test vector data is available as JsonNode under the
  ## the variable passed as `testData`
  proc `test _ name`() =
    var count = 0 # Need to fail if walkDir doesn't return anything
    var skipped = 0
    for dir, file in walkTests(astToStr(name), skipped):
      stdout.write("       " & astToStr(name) & " test: " & alignLeft(file, 70))
      let testFile = readFile(dir/file)
      let testData = testFile.fromJson(TestType)

      body

      stdout.write "[" & $status & "]\n"
      inc count

    doAssert count > 0, "Empty or inexisting test folder: " & astToStr(name)
    if skipped > 0:
      echo "[Warning]: ", skipped, " tests skipped."

testGen(deserialization_G1, testVector, DeserG1_test):
  var pubkey{.noInit.}: PublicKey

  let status = pubkey.deserialize_pubkey_compressed(testVector.input.pubkey)
  let success = status == cttCodecEcc_Success or status == cttCodecEcc_PointAtInfinity

  doAssert success == testVector.output, block:
    "\nDeserialization differs from expected \n" &
    "   deserializable? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

  if success: # Roundtrip
    var s{.noInit.}: array[48, byte]

    let status2 = s.serialize_pubkey_compressed(pubkey)
    doAssert status2 == cttCodecEcc_Success
    doAssert s == testVector.input.pubkey, block:
      "\nSerialization roundtrip differs from expected \n" &
      "   serialized: 0x" & $s.toHex() & " (" & $status2 & ")\n" &
      "   expected:   0x" & $testVector.input.pubkey.toHex()

testGen(deserialization_G2, testVector, DeserG2_test):
  var sig{.noInit.}: Signature

  let status = sig.deserialize_signature_compressed(testVector.input.signature)
  let success = status == cttCodecEcc_Success or status == cttCodecEcc_PointAtInfinity

  doAssert success == testVector.output, block:
    "\nDeserialization differs from expected \n" &
    "   deserializable? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

  if success: # Roundtrip
    var s{.noInit.}: array[96, byte]

    let status2 = s.serialize_signature_compressed(sig)
    doAssert status2 == cttCodecEcc_Success
    doAssert s == testVector.input.signature, block:
      "\nSerialization roundtrip differs from expected \n" &
      "   serialized: 0x" & $s.toHex() & " (" & $status2 & ")\n" &
      "   expected:   0x" & $testVector.input.signature.toHex()

testGen(sign, testVector, Sign_test):
  var seckey{.noInit.}: SecretKey
  var sig{.noInit.}: Signature

  let status = seckey.deserialize_seckey(testVector.input.privkey)
  if status != cttCodecScalar_Success:
    doAssert testVector.output == default(array[96, byte])
    sig.sign(seckey, testVector.input.message)
  else:
    sig.sign(seckey, testVector.input.message)

    block: # deserialize the output for extra codec testing
      var output{.noInit.}: Signature
      let status2 = output.deserialize_signature_compressed(testVector.output)
      doAssert status2 == cttCodecEcc_Success
      doAssert signatures_are_equal(sig, output), block:
        var sig_bytes{.noInit.}: array[96, byte]
        var roundtrip{.noInit.}: array[96, byte]
        let sb_status = sig_bytes.serialize_signature_compressed(sig)
        let rt_status = roundtrip.serialize_signature_compressed(output)

        "\nResult signature differs from expected \n" &
        "   computed:  0x" & $sig_bytes.toHex() & " (" & $sb_status & ")\n" &
        "   roundtrip: 0x" & $roundtrip.toHex() & " (" & $rt_status & ")\n" &
        "   expected:  0x" & $testVector.output.toHex()

    block: # serialize the result for extra codec testing
      var sig_bytes{.noInit.}: array[96, byte]
      let status2 = sig_bytes.serialize_signature_compressed(sig)
      doAssert status2 == cttCodecEcc_Success
      doAssert sig_bytes == testVector.output, block:
         "\nResult signature differs from expected \n" &
         "   computed: 0x" & $sig_bytes.toHex() & " (" & $status2 & ")\n" &
         "   expected: 0x" & $testVector.output.toHex()

testGen(verify, testVector, Verify_test):
  var
    pubkey{.noInit.}: PublicKey
    signature{.noInit.}: Signature
    status = (cttEthBls_VerificationFailure, cttCodecEcc_InvalidEncoding)

  block testChecks:
    status[1] = pubkey.deserialize_pubkey_compressed(testVector.input.pubkey)
    if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
      # For point at infinity, we want to make sure that "verify" itself handles them.
      break testChecks
    status[1] = signature.deserialize_signature_compressed(testVector.input.signature)
    if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
      # For point at infinity, we want to make sure that "verify" itself handles them.
      break testChecks

    status[0] = pubkey.verify(testVector.input.message, signature)

  let success = status == (cttEthBls_Success, cttCodecEcc_Success)
  doAssert success == testVector.output, block:
    "Verification differs from expected \n" &
    "   valid sig? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

  if success: # Extra codec testing
    block:
      var output{.noInit.}: array[48, byte]
      let s = output.serialize_pubkey_compressed(pubkey)
      doAssert s == cttCodecEcc_Success
      doAssert output == testVector.input.pubkey

    block:
      var output{.noInit.}: array[96, byte]
      let s = output.serialize_signature_compressed(signature)
      doAssert s == cttCodecEcc_Success
      doAssert output == testVector.input.signature

testGen(fast_aggregate_verify, testVector, FastAggregateVerify_test):
  var
    pubkeys = newSeq[PublicKey](testVector.input.pubkeys.len)
    signature{.noInit.}: Signature
    status = (cttEthBls_VerificationFailure, cttCodecEcc_InvalidEncoding)

  block testChecks:
    for i in 0 ..< testVector.input.pubkeys.len:
      status[1] = pubkeys[i].deserialize_pubkey_compressed(testVector.input.pubkeys[i])
      if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
        # For point at infinity, we want to make sure that "verify" itself handles them.
        break testChecks

    status[1] = signature.deserialize_signature_compressed(testVector.input.signature)
    if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
      # For point at infinity, we want to make sure that "verify" itself handles them.
      break testChecks

    status[0] = pubkeys.fast_aggregate_verify(testVector.input.message, signature)

  let success = status == (cttEthBls_Success, cttCodecEcc_Success)
  doAssert success == testVector.output, block:
    "Verification differs from expected \n" &
    "   valid sig? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

testGen(aggregate_verify, testVector, AggregateVerify_test):
  var
    pubkeys = newSeq[PublicKey](testVector.input.pubkeys.len)
    signature{.noInit.}: Signature
    status = (cttEthBls_VerificationFailure, cttCodecEcc_InvalidEncoding)

  block testChecks:
    for i in 0 ..< testVector.input.pubkeys.len:
      status[1] = pubkeys[i].deserialize_pubkey_compressed(testVector.input.pubkeys[i])
      if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
        # For point at infinity, we want to make sure that "verify" itself handles them.
        break testChecks

    status[1] = signature.deserialize_signature_compressed(testVector.input.signature)
    if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
      # For point at infinity, we want to make sure that "verify" itself handles them.
      break testChecks

    status[0] = pubkeys.aggregate_verify(testVector.input.messages, signature)

  let success = status == (cttEthBls_Success, cttCodecEcc_Success)
  doAssert success == testVector.output, block:
    "Verification differs from expected \n" &
    "   valid sig? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

testGen(batch_verify, testVector, BatchVerify_test):
  var
    pubkeys = newSeq[PublicKey](testVector.input.pubkeys.len)
    signatures = newSeq[Signature](testVector.input.signatures.len)
    status = (cttEthBls_VerificationFailure, cttCodecEcc_InvalidEncoding)

  block testChecks:
    for i in 0 ..< testVector.input.pubkeys.len:
      status[1] = pubkeys[i].deserialize_pubkey_compressed(testVector.input.pubkeys[i])
      if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
        # For point at infinity, we want to make sure that "verify" itself handles them.
        break testChecks

    for i in 0 ..< testVector.input.signatures.len:
      status[1] = signatures[i].deserialize_signature_compressed(testVector.input.signatures[i])
      if status[1] notin {cttCodecEcc_Success, cttCodecEcc_PointAtInfinity}:
        # For point at infinity, we want to make sure that "verify" itself handles them.
        break testChecks

    let randomBytes = sha256.hash("totally non-secure source of entropy")

    status[0] = pubkeys.batch_verify(testVector.input.messages, signatures, randomBytes)

    let tp = Threadpool.new(numThreads = 4)
    let parallelStatus = tp.batch_verify_parallel(pubkeys, testVector.input.messages, signatures, randomBytes)
    doAssert status[0] == parallelStatus, block:
      "\nSerial status:   " & $status[0] &
      "\nParallel status: " & $parallelStatus & '\n'
    tp.shutdown()

  let success = status == (cttEthBls_Success, cttCodecEcc_Success)
  doAssert success == testVector.output, block:
    "Verification differs from expected \n" &
    "   valid sig? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

suite "BLS signature on BLS12381G3 - ETH 2.0 test vectors":
  test "Deserialization_G1(PublicKey) -> bool":
    test_deserialization_G1()
  test "Deserialization_G2(Signature) -> bool":
    test_deserialization_G2()
  test "sign(SecretKey, message) -> Signature":
    test_sign()
  test "verify(PublicKey, message, Signature) -> bool":
    test_verify()
  test "fast_aggregate_verify(seq[PublicKey], message, Signature) -> bool":
    test_fast_aggregate_verify()
  test "aggregate_verify(seq[PublicKey], seq[message], Signature) -> bool":
    test_aggregate_verify()
  test "batch_verify(seq[PublicKey], seq[message], seq[Signature]) -> bool":
    test_batch_verify()
