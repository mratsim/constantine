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
  constantine/platforms/isa_arm64/simd_neon

export simd_neon

# ############################################################
#
#        Carry-less multiplication with PMULL
#
# ############################################################
#
# PMULL is emitted as inline assembly so that callers can inline it
# without compiling for a CPU with the AES extension.
# Everything around it uses Advanced SIMD (NEON),
# which is part of the ARMv8-A baseline.
#
# Callers must check `hasPmull()` at runtime.

static: doAssert UseASM_ARM64

macro pmull_gen(r: var uint64x2_t, a, b: uint64x2_t, high: static bool): untyped =
  ## r <- a.d[i] ⊗ b.d[i], with i = 1 if high else 0
  result = newStmtList()

  var ctx = init(Assembler_arm64, uint64)
  let
    dst = asmValue(r, VecReg, asmOutputOverwrite)
    lhs = asmValue(a, VecReg, asmInput)
    rhs = asmValue(b, VecReg, asmInput)

  if high:
    ctx.pmull2(dst, lhs, rhs)
  else:
    ctx.pmull(dst, lhs, rhs)
  result.add ctx.generate()

func pmull_lo*(a, b: uint64x2_t): uint64x2_t {.inline, noInit.} =
  ## a[0] ⊗ b[0], the 128-bit carry-less product of the low lanes
  pmull_gen(result, a, b, high = false)

func pmull_hi*(a, b: uint64x2_t): uint64x2_t {.inline, noInit.} =
  ## a[1] ⊗ b[1], the 128-bit carry-less product of the high lanes
  pmull_gen(result, a, b, high = true)

macro fmov_gen(r: var uint64x2_t, a: uint64): untyped =
  ## r <- [a, 0]
  result = newStmtList()

  var ctx = init(Assembler_arm64, uint64)
  let
    dst = asmValue(r, VecReg, asmOutputOverwrite)
    src = asmValue(a, Reg, asmInput)

  ctx.fmov(dst, src)
  # A pure register move: let the compiler hoist it out of loops
  # and merge duplicates, as it would for an intrinsic
  result.add ctx.generate(isVolatile = false)

func lowLane*(a: uint64): uint64x2_t {.inline, noInit.} =
  ## [a, 0]: `a` in the low 64-bit lane and zero in the high lane (FMOV).
  ##
  ## For PMULL, which only reads the low lane, this is cheaper than
  ## `vdupq_n_u64` (DUP), about 2 cycles less latency on Apple M4.
  ## Clang compiles the intrinsic alternative, vcombine_u64(vcreate_u64(a), 0),
  ## to a zeroing plus an insertion instead, hence the assembly.
  fmov_gen(result, a)

func clmul_arm64*(hi, lo: var uint64, a, b: uint64) {.inline.} =
  ## (hi, lo) <- a ⊗ b, the 128-bit carry-less product
  let p = pmull_lo(lowLane(a), lowLane(b))
  lo = vgetq_lane_u64(p, 0)
  hi = vgetq_lane_u64(p, 1)

func clsquare_arm64*(hi, lo: var uint64, a: uint64) {.inline.} =
  ## (hi, lo) <- a ⊗ a
  let v = lowLane(a)
  let p = pmull_lo(v, v)
  lo = vgetq_lane_u64(p, 0)
  hi = vgetq_lane_u64(p, 1)
