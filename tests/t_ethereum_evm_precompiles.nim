# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, strutils],
  # 3rd party
  pkg/jsony,
  # Internals
  ../constantine/serialization/codecs,
  ../constantine/ethereum_evm_precompiles

# Test vector source:
# - https://github.com/ethereum/go-ethereum/tree/release/1.14/core/vm/testdata/precompiles
# - https://github.com/ethereum/EIPs/tree/3b5fcad/assets/eip-2537

type
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
      let vec = seq[PrecompileTest].loadVectors(filename)
      echo "Running ", filename

      for test in vec:
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

runPrecompileTests("modexp.json", eth_evm_modexp)
runPrecompileTests("modexp_eip2565.json", eth_evm_modexp)

runPrecompileTests("bn256Add.json", eth_evm_bn254_g1add)
runPrecompileTests("bn256ScalarMul.json", eth_evm_bn254_g1mul)
runPrecompileTests("bn256Pairing.json", eth_evm_bn254_ecpairingcheck)

runPrecompileTests("eip-2537/add_G1_bls.json", eth_evm_bls12381_g1add)
runPrecompileTests("eip-2537/fail-add_G1_bls.json", eth_evm_bls12381_g1add)
runPrecompileTests("eip-2537/add_G2_bls.json", eth_evm_bls12381_g2add)
runPrecompileTests("eip-2537/fail-add_G2_bls.json", eth_evm_bls12381_g2add)

runPrecompileTests("eip-2537/mul_G1_bls.json", eth_evm_bls12381_g1mul)
runPrecompileTests("eip-2537/fail-mul_G1_bls.json", eth_evm_bls12381_g1mul)
runPrecompileTests("eip-2537/mul_G2_bls.json", eth_evm_bls12381_g2mul)
runPrecompileTests("eip-2537/fail-mul_G2_bls.json", eth_evm_bls12381_g2mul)

runPrecompileTests("eip-2537/multiexp_G1_bls.json", eth_evm_bls12381_g1msm)
runPrecompileTests("eip-2537/fail-multiexp_G1_bls.json", eth_evm_bls12381_g1msm)
runPrecompileTests("eip-2537/multiexp_G2_bls.json", eth_evm_bls12381_g2msm)
runPrecompileTests("eip-2537/fail-multiexp_G2_bls.json", eth_evm_bls12381_g2msm)