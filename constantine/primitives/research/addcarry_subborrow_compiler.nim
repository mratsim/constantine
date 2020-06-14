# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#            Add-with-carry and Sub-with-borrow
#
# ############################################################
#
# This is a proof-of-concept optimal add-with-carry
# compiler implemented as Nim macros.
#
# This overcome the bad GCC codegen aven with addcary_u64 intrinsic.

import std/macros

func wordsRequired(bits: int): int {.compileTime.} =
  ## Compute the number of limbs required
  ## from the announced bit length
  (bits + 64 - 1) div 64

type
  BigInt[bits: static int] {.byref.} = object
    ## BigInt
    ## Enforce-passing by reference otherwise uint128 are passed by stack
    ## which causes issue with the inline assembly
    limbs: array[bits.wordsRequired, uint64]

macro addCarryGen_u64(a, b: untyped, bits: static int): untyped =
  var asmStmt = (block:
    "      movq %[b], %[tmp]\n" &
    "      addq %[tmp], %[a]\n"
  )

  let maxByteOffset = bits div 8
  const wsize = sizeof(uint64)

  when defined(gcc):
    for byteOffset in countup(wsize, maxByteOffset-1, wsize):
      asmStmt.add (block:
        "\n" &
        # movq 8+%[b], %[tmp]
        "      movq " & $byteOffset & "+%[b], %[tmp]\n" &
        # adcq %[tmp], 8+%[a]
        "      adcq %[tmp], " & $byteOffset & "+%[a]\n"
      )
  elif defined(clang):
    # https://lists.llvm.org/pipermail/llvm-dev/2017-August/116202.html
    for byteOffset in countup(wsize, maxByteOffset-1, wsize):
      asmStmt.add (block:
        "\n" &
        # movq 8+%[b], %[tmp]
        "      movq " & $byteOffset & "%[b], %[tmp]\n" &
        # adcq %[tmp], 8+%[a]
        "      adcq %[tmp], " & $byteOffset & "%[a]\n"
      )

  let tmp = ident("tmp")
  asmStmt.add (block:
    ": [tmp] \"+r\" (`" & $tmp & "`), [a] \"+m\" (`" & $a & "->limbs[0]`)\n" &
    ": [b] \"m\"(`" & $b & "->limbs[0]`)\n" &
    ": \"cc\""
  )

  result = newStmtList()
  result.add quote do:
    var `tmp`{.noinit.}: uint64

  result.add nnkAsmStmt.newTree(
    newEmptyNode(),
    newLit asmStmt
  )

  echo result.toStrLit

func `+=`(a: var BigInt, b: BigInt) {.noinline.}=
  # Depending on inline or noinline
  # the generated ASM addressing must be tweaked for Clang
  # https://lists.llvm.org/pipermail/llvm-dev/2017-August/116202.html
  addCarryGen_u64(a, b, BigInt.bits)

# #############################################
when isMainModule:
  import std/random
  proc rand(T: typedesc[BigInt]): T =
    for i in 0 ..< result.limbs.len:
      result.limbs[i] = uint64(rand(high(int)))

  proc main() =
    block:
      let a = BigInt[128](limbs: [high(uint64), 0])
      let b = BigInt[128](limbs: [1'u64, 0])

      echo "a:        ", a
      echo "b:        ", b
      echo "------------------------------------------------------"

      var a1 = a
      a1 += b
      echo a1
      echo "======================================================"

    block:
      let a = rand(BigInt[256])
      let b = rand(BigInt[256])

      echo "a:        ", a
      echo "b:        ", b
      echo "------------------------------------------------------"

      var a1 = a
      a1 += b
      echo a1
      echo "======================================================"

    block:
      let a = rand(BigInt[384])
      let b = rand(BigInt[384])

      echo "a:        ", a
      echo "b:        ", b
      echo "------------------------------------------------------"

      var a1 = a
      a1 += b
      echo a1

  main()
