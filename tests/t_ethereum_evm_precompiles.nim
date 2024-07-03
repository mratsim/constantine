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
  constantine/serialization/codecs,
  constantine/ethereum_evm_precompiles

# Test vector source:
# - https://github.com/ethereum/go-ethereum/tree/release/1.14/core/vm/testdata/precompiles
# - https://github.com/ethereum/EIPs/tree/3b5fcad/assets/eip-2537

type
  HexString = string

  PrecompileTest = object
    Input: HexString
    Expected: HexString
    ExpectedError: string
    Name: string
    Gas: int
    NoBenchmark: bool

const
  TestVectorsDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / "protocol_ethereum_evm_precompiles"

proc loadVectors(TestType: typedesc, filename: string): TestType =
  let content = readFile(TestVectorsDir/filename)
  result = content.fromJson(TestType)

template runPrecompileTests(filename: string, funcname: untyped, outsize: int) =
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

        ## TODO: change to use `modexp_result_size` API after rebase
        let outs = if outsize > 0: outsize else: test.Expected.len div 2
        var r = newSeq[byte](outs)

        let status = funcname(r, inputbytes)
        if status != cttEVM_Success:
          doAssert test.ExpectedError.len > 0, "[Test Failure]\n" &
            "  " & test.Name & "\n" &
            "  " & funcname.astToStr & "\n" &
            "  " & "Nim proc returned failure, but test expected to pass.\n" &
            "  " & "Expected result: " & $expected.toHex()
        else:
          doAssert r == expected, "[Test Failure]\n" &
            "  " & test.Name & "\n" &
            "  " & funcname.astToStr & " status: " & $status & "\n" &
            "  " & "result:   " & r.toHex() & "\n" &
            "  " & "expected: " & expected.toHex() & '\n'

        stdout.write "Success\n"

    `PrecompileTestrunner _ funcname`()

proc testSha256() =
  # https://github.com/ethereum/go-ethereum/blob/v1.14.0/core/vm/contracts_test.go#L206-L214
  let input = "38d18acb67d25c8bb9942764b62f18e17054f66a817bd4295423adf9ed98873e000000000000000000000000000000000000000000000000000000000000001b38d18acb67d25c8bb9942764b62f18e17054f66a817bd4295423adf9ed98873e789d1dd423d25f0772d2748d60f7e4b81bb14d086eba8e8e8efb6dcff8a4ae02"
  let expected = "811c7003375852fabd0d362e40e68607a12bdabae61a7d068fe5fdd1dbbf2a5d"

  echo "Running SHA256 tests"
  stdout.write "    Testing SHA256 ... "

  var inputbytes = newSeq[byte](input.len div 2)
  inputbytes.fromHex(input)

  var expectedbytes = newSeq[byte](expected.len div 2)
  expectedbytes.fromHex(expected)

  var r = newSeq[byte](expected.len div 2)

  let status = eth_evm_sha256(r, inputbytes)
  if status != cttEVM_Success:
    reset(r)

  doAssert r == expectedbytes, "[Test Failure]\n" &
    "  eth_evm_sha256 status: " & $status & "\n" &
    "  " & "result:   " & r.toHex() & "\n" &
    "  " & "expected: " & expectedbytes.toHex() & '\n'

  stdout.write "Success\n"

# ----------------------------------------------------------------------

testSha256()

runPrecompileTests("modexp.json", eth_evm_modexp, 0)
runPrecompileTests("modexp_eip2565.json", eth_evm_modexp, 0)

runPrecompileTests("bn256Add.json", eth_evm_bn254_g1add, 64)
runPrecompileTests("bn256ScalarMul.json", eth_evm_bn254_g1mul, 64)
runPrecompileTests("bn256Pairing.json", eth_evm_bn254_ecpairingcheck, 32)

runPrecompileTests("eip-2537/add_G1_bls.json", eth_evm_bls12381_g1add, 128)
runPrecompileTests("eip-2537/fail-add_G1_bls.json", eth_evm_bls12381_g1add, 128)
runPrecompileTests("eip-2537/add_G2_bls.json", eth_evm_bls12381_g2add, 256)
runPrecompileTests("eip-2537/fail-add_G2_bls.json", eth_evm_bls12381_g2add, 256)

runPrecompileTests("eip-2537/mul_G1_bls.json", eth_evm_bls12381_g1mul, 128)
runPrecompileTests("eip-2537/fail-mul_G1_bls.json", eth_evm_bls12381_g1mul, 128)
runPrecompileTests("eip-2537/mul_G2_bls.json", eth_evm_bls12381_g2mul, 256)
runPrecompileTests("eip-2537/fail-mul_G2_bls.json", eth_evm_bls12381_g2mul, 256)

runPrecompileTests("eip-2537/multiexp_G1_bls.json", eth_evm_bls12381_g1msm, 128)
runPrecompileTests("eip-2537/fail-multiexp_G1_bls.json", eth_evm_bls12381_g1msm, 128)
runPrecompileTests("eip-2537/multiexp_G2_bls.json", eth_evm_bls12381_g2msm, 256)
runPrecompileTests("eip-2537/fail-multiexp_G2_bls.json", eth_evm_bls12381_g2msm, 256)

runPrecompileTests("eip-2537/pairing_check_bls.json", eth_evm_bls12381_pairingcheck, 32)
runPrecompileTests("eip-2537/fail-pairing_check_bls.json", eth_evm_bls12381_pairingcheck, 32)

runPrecompileTests("eip-2537/map_fp_to_G1_bls.json", eth_evm_bls12381_map_fp_to_g1, 128)
runPrecompileTests("eip-2537/fail-map_fp_to_G1_bls.json", eth_evm_bls12381_map_fp_to_g1, 128)
runPrecompileTests("eip-2537/map_fp2_to_G2_bls.json", eth_evm_bls12381_map_fp2_to_g2, 256)
runPrecompileTests("eip-2537/fail-map_fp2_to_G2_bls.json", eth_evm_bls12381_map_fp2_to_g2, 256)
