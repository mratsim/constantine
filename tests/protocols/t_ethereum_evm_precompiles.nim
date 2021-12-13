# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times, os, strutils, macros],
  # 3rd party
  jsony,
  # Internals
  ../../constantine/io/io_bigints,
  ../../constantine/protocols/ethereum_evm_precompiles

type
  BN256AddTests = object
    `func`: string
    fork: string
    data: seq[BN256AddTest]

  BN256MulTests = object
    `func`: string
    fork: string
    data: seq[BN256MulTest]

  HexString = string

  BN256AddTest = object
    Input: HexString
    Expected: HexString
    Name: string
    Gas: int
    NoBenchmark: bool

  BN256MulTest = object
    Input: HexString
    Expected: HexString
    Name: string
    Gas: int
    NoBenchmark: bool

const
  TestVectorsDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / "ethereum_evm_precompiles"

proc loadVectors(TestType: typedesc, filename: string): TestType =
  let content = readFile(TestVectorsDir/filename)
  result = content.fromJson(TestType)

proc runBN256AddTests() =
  let test = "bn256Add.json"
  let vec = loadVectors(BN256AddTests, test)
  echo "Running ", test

  for test in vec.data:
    stdout.write "Testing " & test.Name & " ... "

    # Length: 2 hex characters -> 1 byte
    var inputbytes = newSeq[byte](test.Input.len div 2)
    test.Input.hexToPaddedByteArray(inputbytes, bigEndian)

    var r: array[64, byte]
    var expected: array[64, byte]

    let status = eth_evm_ecadd(r, inputbytes)
    if status != cttEVM_Success:
      reset(r)

    test.Expected.hexToPaddedByteArray(expected, bigEndian)

    doAssert r == expected
    stdout.write "Success\n"

proc runBN256MulTests() =
  let test = "bn256mul.json"
  let vec = loadVectors(BN256MulTests, test)
  echo "Running ", test

  for test in vec.data:
    stdout.write "Testing " & test.Name & " ... "

    # Length: 2 hex characters -> 1 byte
    var inputbytes = newSeq[byte](test.Input.len div 2)
    test.Input.hexToPaddedByteArray(inputbytes, bigEndian)

    var r: array[64, byte]
    var expected: array[64, byte]

    let status = eth_evm_ecmul(r, inputbytes)
    if status != cttEVM_Success:
      reset(r)

    test.Expected.hexToPaddedByteArray(expected, bigEndian)

    doAssert r == expected
    stdout.write "Success\n"

runBN256AddTests()
runBN256MulTests()