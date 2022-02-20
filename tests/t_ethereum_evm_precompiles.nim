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
  # Status
  stew/byteutils,
  # 3rd party
  jsony,
  # Internals
  ../constantine/backend/io/io_bigints,
  ../constantine/backend/protocols/ethereum_evm_precompiles

type
  BN256Tests = object
    `func`: string
    fork: string
    data: seq[BN256Test]

  HexString = string

  BN256Test = object
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

template runBN256Tests(filename: string, funcname: untyped, osize: static int) =
  proc `bn256testrunner _ funcname`() =
    let vec = loadVectors(BN256Tests, filename)
    echo "Running ", filename

    for test in vec.data:
      stdout.write "    Testing " & test.Name & " ... "

      # Length: 2 hex characters -> 1 byte
      var inputbytes = newSeq[byte](test.Input.len div 2)
      test.Input.hexToPaddedByteArray(inputbytes, bigEndian)

      var r: array[osize, byte]
      var expected: array[osize, byte]

      let status = funcname(r, inputbytes)
      if status != cttEVM_Success:
        reset(r)

      test.Expected.hexToPaddedByteArray(expected, bigEndian)

      doAssert r == expected, "[Test Failure]\n" &
        "  " & funcname.astToStr & " status: " & $status & "\n" &
        "  " & "result:   " & r.toHex() & "\n" &
        "  " & "expected: " & expected.toHex() & '\n'   
      
      stdout.write "Success\n"
  
  `bn256testrunner _ funcname`()

runBN256Tests("bn256Add.json", eth_evm_ecadd, 64)
runBN256Tests("bn256mul.json", eth_evm_ecmul, 64)
runBN256Tests("pairing.json", eth_evm_ecpairing, 32)