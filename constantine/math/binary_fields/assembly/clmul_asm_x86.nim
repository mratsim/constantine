# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  constantine/platforms/abstractions,
  constantine/platforms/isa_x86/simd_x86

export simd_x86

# ############################################################
#
#        Carry-less multiplication with PCLMULQDQ
#
# ############################################################
#
# PCLMULQDQ is emitted as inline assembly so that callers can inline it
# without compiling with -mpclmul. Everything around it uses SSE2,
# which is part of the x86-64 baseline.
#
# Callers must check `hasCLMUL()` at runtime.

static: doAssert UseASM_X86_64

macro pclmul_gen(r: var m128i, b: m128i, imm: static int): untyped =
  ## r <- r.qword[imm and 1] ⊗ b.qword[(imm shr 4) and 1]
  result = newStmtList()

  var ctx = init(Assembler_x86, uint64)
  let
    dst = asmValue(r, XmmReg, asmInputOutput)
    src = asmValue(b, XmmReg, asmInput)

  ctx.pclmulqdq(dst, src, imm)
  result.add ctx.generate()

func pclmul*(a, b: m128i, imm: static int): m128i {.inline, noInit.} =
  ## Carry-less product of the qword of `a` selected by bit 0 of `imm`
  ## and the qword of `b` selected by bit 4 of `imm`:
  ## - 0x00: a[0] ⊗ b[0]
  ## - 0x01: a[1] ⊗ b[0]
  ## - 0x10: a[0] ⊗ b[1]
  ## - 0x11: a[1] ⊗ b[1]
  result = a
  pclmul_gen(result, b, imm)

func clmul_x86*(hi, lo: var uint64, a, b: uint64) {.inline.} =
  ## (hi, lo) <- a ⊗ b, the 128-bit carry-less product
  let p = pclmul(movq_to_u128(a), movq_to_u128(b), 0x00)
  lo = movq_from_u128(p)
  hi = movq_from_u128(unpackhi_u64x2(p, p))
