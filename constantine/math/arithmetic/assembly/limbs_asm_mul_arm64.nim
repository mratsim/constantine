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
  constantine/platforms/abstractions

# ############################################################
#
#        Assembly implementation of bigint multiplication
#
# ############################################################

static: doAssert UseASM_ARM64

macro mul_gen[rLen, aLen, bLen: static int](
        r_PIR: var Limbs[rLen],
        a_PIR: Limbs[aLen],
        b_PIR: Limbs[bLen]) =
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## Assumes r doesn't alias a or b

  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)
  let
    r = asmArray(r_PIR, rLen, PointerInReg, asmInput, memIndirect = memWrite)
    a = asmArray(a_PIR, aLen, PointerInReg, asmInput, memIndirect = memRead)
    b = asmArray(b_PIR, bLen, PointerInReg, asmInput, memIndirect = memRead)

    tSym = ident"t"
    tSlots = aLen+1 # Extra for high words

    biSym = ident"bi"
    bi = asmValue(biSym, Reg, asmOutputEarlyClobber)

    aaSym = ident"aa"
    aa = asmArray(aaSym, aLen, ElemsInReg, asmInputOutput)

    uSym = ident"u"
    vSym = ident"v"

  var t = asmArray(tSym, tSlots, ElemsInReg, asmOutputEarlyClobber)

  var # Break dependencies chain
    u = asmValue(uSym, Reg, asmOutputEarlyClobber)
    v = asmValue(vSym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `tSym`{.noInit, used.}: array[`tSlots`, BaseType]
    var `uSym`{.noinit.}, `vSym`{.noInit.}: BaseType
    var `biSym`{.noInit.}: BaseType
    var `aaSym`{.noInit, used.}: typeof(`a_PIR`)
    `aaSym` = `a_PIR`

  template mulloadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul u, lhs, rhs
    ctx.adds dst, addend, u
    swap(u, v)
  template mulloadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul u, lhs, rhs
    ctx.adcs dst, addend, u
    swap(u, v)

  template mulhiadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adds dst, addend, u
    swap(u, v)
  template mulhiadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adcs dst, addend, u
    swap(u, v)
  template mulhiadd_ci(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adc dst, addend, u
    swap(u, v)

  doAssert aLen >= 2

  for i in 0 ..< min(rLen, bLen):
    ctx.ldr bi, b[i]
    if i == 0:
      ctx.mul u, aa[0], bi
      ctx.str u, r[i]
      ctx.umulh t[0], aa[0], bi
      swap(u, v)
      for j in 1 ..< aLen:
        ctx.mul u, aa[j], bi
        ctx.umulh t[j], aa[j], bi
        if j == 1:
          ctx.adds t[j-1], t[j-1], u
        else:
          ctx.adcs t[j-1], t[j-1], u
        ctx.adc t[aLen-1], t[aLen-1], xzr
        swap(u, v)
    else:
      ctx.mulloadd_co(t[0], aa[0], bi, t[0])
      ctx.str t[0], r[i]
      for j in 1 ..< aLen:
        ctx.mulloadd_cio(t[j], aa[j], bi, t[j])
      ctx.adc t[aLen], xzr, xzr                    # assumes N > 1

      ctx.mulhiadd_co(t[1], aa[0], bi, t[1])
      for j in 2 ..< aLen:
        ctx.mulhiadd_cio(t[j], aa[j-1], bi, t[j])
      ctx.mulhiadd_ci(t[aLen], aa[aLen-1], bi, t[aLen])

      t.rotateLeft()

  # Copy upper-limbs to result
  for i in b.len ..< min(a.len+b.len, rLen):
    ctx.str t[i-b.len], r[i]

  # Zero the extra
  for i in aLen+bLen ..< rLen:
    ctx.str xzr, r[i]

  result.add ctx.generate()

func mul_asm*[rLen, aLen, bLen: static int](
       r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mul_gen(r, a, b)