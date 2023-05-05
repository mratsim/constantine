# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[times, os, strutils, macros],
  # 3rd party
  pkg/jsony,
  # Internals
  ../constantine/serialization/codecs,
  ../constantine/ethereum_evm_precompiles

type
  PrecompileTests = object
    `func`: string
    fork: string
    data: seq[PrecompileTest]

  HexString = string

  PrecompileTest = object
    Input: HexString
    Expected: HexString
    Name: string
    Gas: int
    NoBenchmark: bool

const
  TestVectorsDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_evm_precompiles"

proc loadVectors(TestType: typedesc, filename: string): TestType =
  let content = readFile(TestVectorsDir/filename)
  result = content.fromJson(TestType)

template runPrecompileTests(filename: string, funcname: untyped) =
  block:
    proc `PrecompileTestrunner _ funcname`() =
      let vec = loadVectors(PrecompileTests, filename)
      echo "Running ", filename

      for test in vec.data:
        stdout.write "    Testing " & test.Name & " ... "

        # Length: 2 hex characters -> 1 byte
        var inputbytes = newSeq[byte](test.Input.len div 2)
        inputbytes.paddedFromHex(test.Input, bigEndian)

        var expected = newSeq[byte](test.Expected.len div 2)
        expected.paddedFromHex(test.Expected, bigEndian)

        var r = newSeq[byte](test.Expected.len div 2)

        let status = funcname(r, inputbytes)
        if status != cttEVM_Success:
          reset(r)

        doAssert r == expected, "[Test Failure]\n" &
          "  " & funcname.astToStr & " status: " & $status & "\n" &
          "  " & "result:   " & r.toHex() & "\n" &
          "  " & "expected: " & expected.toHex() & '\n'

        stdout.write "Success\n"

    `PrecompileTestrunner _ funcname`()

runPrecompileTests("bn256Add.json", eth_evm_ecadd)
runPrecompileTests("bn256mul.json", eth_evm_ecmul)
runPrecompileTests("pairing.json", eth_evm_ecpairing)
runPrecompileTests("modexp.json", eth_evm_modexp)
runPrecompileTests("modexp_eip2565.json", eth_evm_modexp)