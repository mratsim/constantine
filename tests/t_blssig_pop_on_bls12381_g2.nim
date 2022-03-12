# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[json, os, unittest, strutils],
  jsony, stew/byteutils,
  ../src/constantine/blssig_pop_on_bls12381_g2,
  ../src/constantine/math/io/io_bigints

type
  PubkeyField = object
    pubkey: array[48, byte]
  SignatureField =object
    signature: array[96, byte]
  DeserG1_test = object
    input: PubkeyField
    output: bool
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

proc parseHook*[N: static int](src: string, pos: var int, value: var array[N, byte]) =
  var str: string
  parseHook(src, pos, str)
  str.hexToPaddedByteArray(value, bigEndian)

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
      stdout.write("       " & astToStr(name) & " test: " & alignLeft(file, 60))
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

  let status = pubkey.deserialize_public_key_compressed(testVector.input.pubkey)
  let success = status == cttBLS_Success or status == cttBLS_PointAtInfinity

  doAssert success == testVector.output, block:
    "\nDeserialization differs from expected \n" &
    "   deserializable? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

  if success: # Roundtrip
    var s{.noInit.}: array[48, byte]

    let status2 = s.serialize_public_key_compressed(pubkey)
    doAssert status2 == cttBLS_Success
    doAssert s == testVector.input.pubkey, block:
      "\nSerialization roundtrip differs from expected \n" &
      "   serialized: 0x" & $s.toHex() & " (" & $status2 & ")\n" &
      "   expected:   0x" & $testVector.input.pubkey.toHex()

testGen(deserialization_G2, testVector, DeserG2_test):
  var sig{.noInit.}: Signature

  let status = sig.deserialize_signature_compressed(testVector.input.signature)
  let success = status == cttBLS_Success or status == cttBLS_PointAtInfinity

  doAssert success == testVector.output, block:
    "\nDeserialization differs from expected \n" &
    "   deserializable? " & $success & " (" & $status & ")\n" &
    "   expected: " & $testVector.output

  if success: # Roundtrip
    var s{.noInit.}: array[96, byte]

    let status2 = s.serialize_signature_compressed(sig)
    doAssert status2 == cttBLS_Success
    doAssert s == testVector.input.signature, block:
      "\nSerialization roundtrip differs from expected \n" &
      "   serialized: 0x" & $s.toHex() & " (" & $status2 & ")\n" &
      "   expected:   0x" & $testVector.input.signature.toHex()

testGen(sign, testVector, Sign_test):
  var seckey{.noInit.}: SecretKey
  var sig{.noInit.}: Signature

  let status = seckey.deserialize_secret_key(testVector.input.privkey)
  if status != cttBLS_Success:
    doAssert testVector.output == default(array[96, byte])
    let status2 = sig.sign(seckey, testVector.input.message)
    doAssert status2 != cttBLS_Success
  else:
    let status2 = sig.sign(seckey, testVector.input.message)
    doAssert status2 == cttBLS_Success

    block: # deserialize the output for extra codec testing
      var output{.noInit.}: Signature
      let status3 = output.deserialize_signature_compressed(testVector.output)
      doAssert status3 == cttBLS_Success
      doAssert sig == output, block:
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
      let status3 = sig_bytes.serialize_signature_compressed(sig)
      doAssert status3 == cttBLS_Success
      doAssert sig_bytes == testVector.output, block:
         "\nResult signature differs from expected \n" &
         "   computed: 0x" & $sig_bytes.toHex() & " (" & $status3 & ")\n" &
         "   expected: 0x" & $testVector.output.toHex()

testGen(verify, testVector, Verify_test):
  var
    pubkey{.noInit.}: PublicKey
    signature{.noInit.}: Signature
    status = cttBLS_Success

  block testChecks:
    status = pubkey.deserialize_public_key_compressed(testVector.input.pubkey)
    if status notin {cttBLS_Success, cttBLS_PointAtInfinity}:
      # For point at infinity, we want to make sure that "verify" itself handles them.
      break testChecks
    status = signature.deserialize_signature_compressed(testVector.input.signature)
    if status notin {cttBLS_Success, cttBLS_PointAtInfinity}:
      # For point at infinity, we want to make sure that "verify" itself handles them.
      break testChecks


    status = pubkey.verify(testVector.input.message, signature)
    let success = status == cttBLS_Success
    doAssert success == testVector.output, block:
      "\Verification differs from expected \n" &
      "   valid sig? " & $success & " (" & $status & ")\n" &
      "   expected: " & $testVector.output

    if success: # Extra codec testing
      block:
        var output{.noInit.}: array[48, byte]
        let s = output.serialize_public_key_compressed(pubkey)
        doAssert s == cttBLS_Success
        doAssert output == testVector.input.pubkey

      block:
        var output{.noInit.}: array[96, byte]
        let s = output.serialize_signature_compressed(signature)
        doAssert s == cttBLS_Success
        doAssert output == testVector.input.signature

suite "BLS signature on BLS12381G3 - ETH 2.0 test vectors":
  test "Deserialization_G1(PublicKey) -> bool":
    test_deserialization_G1()
  test "Deserialization_G2(Signature) -> bool":
    test_deserialization_G2()
  test "sign(SecretKey, message) -> Signature":
    test_sign()
  test "verify(PublicKey, message, Signature) -> bool":
    test_verify()