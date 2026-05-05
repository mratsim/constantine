# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, strutils, streams],
  # Internal
  constantine/commitments_setups/ethereum_kzg_srs,
  # 3rd party
  pkg/yaml

export yaml

const TrustedSetupMainnet* =
    currentSourcePath.rsplit(DirSep, 1)[0] /
    ".." / ".." / "constantine" /
    "commitments_setups" /
    "trusted_setup_ethereum_kzg4844_reference.dat"

proc getTrustedSetup*(): ptr EthereumKZGContext =
  ## This is a convenience function for the Ethereum mainnet testing trusted setups.
  var ctx: ptr EthereumKZGContext
  let tsStatus = ctx.new(TrustedSetupMainnet, kReferenceCKzg4844)
  doAssert tsStatus == tsSuccess, "\n[Trusted Setup Error] " & $tsStatus
  echo "Trusted Setup loaded successfully"
  return ctx

const SkippedTests = [
  ""
]

iterator walkTests(testDir: string, skipped: var int): (string, string) =
  for file in walkDirRec(testDir, relative = true):
    if file in SkippedTests:
      echo "[WARNING] Skipping - ", file
      inc skipped
      continue

    yield (testDir, file)

proc loadVectors*(filename: string): YamlNode =
  var s = filename.openFileStream()
  defer: s.close()
  load(s, result)

template testGen*(testDirPrefix: string, name: untyped, testDirSuffix: string, injectedTestVectorIdentifier: untyped, body: untyped): untyped {.dirty.} =
  ## Generates a test proc(ctx: ptr EthereumKZGContext)
  ## with identifier "test_name"
  ## The test vector data is available as YamlNode under the
  ## the variable passed as `injectedTestVectorIdentifier`
  bind walkTests, loadVectors

  proc `test _ name`(ctx: ptr EthereumKZGContext) =
    var count = 0 # Need to fail if walkDir doesn't return anything
    var skipped = 0
    let testDir = testDirPrefix / astToStr(name) / testDirSuffix
    for dir, file in walkTests(testDir, skipped):
      stdout.write("       " & alignLeft(astToStr(name) & " test:", 36) & alignLeft(file, 90))
      let `injectedTestVectorIdentifier` = loadVectors(dir/file)

      # Wrap body in closure proc to isolate returns
      proc runTest {.closure.} =
        body
      runTest()

      inc count

    doAssert count > 0, "Empty or inexisting test folder: " & astToStr(name)
    if skipped > 0:
      echo "[Warning]: ", skipped, " tests skipped."

template testGenPar*(testDirPrefix: string, name: untyped, testDirSuffix: string, injectedTestVectorIdentifier: untyped, body: untyped): untyped {.dirty.} =
  ## Generates a test proc(ctx: ptr EthereumKZGContext, tp: Threadpool)
  ## with identifier "test_name"
  ## The test vector data is available as YamlNode under the
  ## the variable passed as `injectedTestVectorIdentifier`
  bind walkTests, loadVectors

  proc `test _ name`(ctx: ptr EthereumKZGContext, tp: Threadpool) =
    var count = 0 # Need to fail if walkDir doesn't return anything
    var skipped = 0
    let testDir = testDirPrefix / astToStr(name) / testDirSuffix
    for dir, file in walkTests(testDir, skipped):
      stdout.write("       " & alignLeft(astToStr(name) & " test:", 36) & alignLeft(file, 90))
      let `injectedTestVectorIdentifier` = loadVectors(dir/file)

      # Wrap body in closure proc to isolate returns
      proc runTest {.closure.} =
        body
      runTest()

      inc count

    doAssert count > 0, "Empty or inexisting test folder: " & astToStr(name)
    if skipped > 0:
      echo "[Warning]: ", skipped, " tests skipped."

template parseAssign*(testVectorNode: YamlNode, dstVariable: untyped, size: static int, hexInput: string) =
  block:
    let prefixBytes = 2*int(hexInput.startsWith("0x"))
    let expectedLength = size*2 + prefixBytes
    if hexInput.len != expectedLength:
      let encodedBytes = (hexInput.len - prefixBytes) div 2
      stdout.write "[ Incorrect input length for '" &
                      astToStr(dstVariable) &
                      "': encoding " & $encodedBytes & " bytes" &
                      " instead of expected " & $size & " ]\n"

      doAssert testVectorNode["output"].content == "null"
      # We're in a template, this exits the wrapping `runTest` closure
      return

  var dstVariable{.inject.} = new(array[size, byte])
  dstVariable[].fromHex(hexInput)
template parseAssignList*(testVectorNode: YamlNode, dstVariable: untyped, elemSize: static int, hexListInput: YamlNode) =

  var dstVariable{.inject.} = newSeq[array[elemSize, byte]]()

  block exitHappyPath:
    block exitException:
      for elem in hexListInput:
        let hexInput = elem.content

        let prefixBytes = 2*int(hexInput.startsWith("0x"))
        let expectedLength = elemSize*2 + prefixBytes
        if hexInput.len != expectedLength:
          let encodedBytes = (hexInput.len - prefixBytes) div 2
          stdout.write "[ Incorrect input length for '" &
                          astToStr(dstVariable) &
                          "': encoding " & $encodedBytes & " bytes" &
                          " instead of expected " & $elemSize & " ]\n"

          doAssert testVectorNode["output"].content == "null"
          break exitException
        else:
          dstVariable.setLen(dstVariable.len + 1)
          dstVariable[^1].fromHex(hexInput)

      break exitHappyPath

    # We're in a template, this exits the wrapping `runTest` closure
    return