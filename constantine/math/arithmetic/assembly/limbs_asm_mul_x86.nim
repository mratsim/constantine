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
  ../../../platforms/abstractions

# ############################################################
#
#        Assembly implementation of bigint multiplication
#
# ############################################################

static: doAssert UseASM_X86_64 # Need 8 registers just for mul
                               # and 32-bit only has 8 max.

# Multiplication
# -----------------------------------------------------------------------------------------------

macro mul_gen[rLen, aLen, bLen: static int](r_PIR: var Limbs[rLen], a_MEM: Limbs[aLen], b_MEM: Limbs[bLen]) =
  ## Comba multiplication generator
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## Assumes r doesn't aliases a or b

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, rLen, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    a = asmArray(a_MEM, aLen, MemOffsettable, asmInput)
    b = asmArray(b_MEM, bLen, MemOffsettable, asmInput)

    tSym = ident"t"
    t = asmValue(tSym, Reg, asmOutputEarlyClobber)
    uSym = ident"u"
    u = asmValue(uSym, Reg, asmOutputEarlyClobber)
    vSym = ident"v"
    v = asmValue(vSym, Reg, asmOutputEarlyClobber)

    # MUL requires RAX and RDX

  # Prologue
  result.add quote do:
    var `tSym`{.noInit.}, `uSym`{.noInit.}, `vSym`{.noInit.}: BaseType

  # Zero-init
  ctx.`xor` u, u
  ctx.`xor` v, v
  ctx.`xor` t, t

  # Algorithm
  let stopEx = min(aLen+bLen, rLen)

  for i in 0 ..< stopEx:
    # Invariant for product scanning:
    # if we multiply accumulate by a[k1] * b[k2]
    # we have k1+k2 == i
    let ib = min(bLen-1, i)
    let ia = i - ib
    for j in 0 ..< min(aLen - ia, ib+1):
      # (t, u, v) <- (t, u, v) + a[ia+j] * b[ib-j]
      ctx.mov rax, b[ib-j]
      ctx.mul rdx, rax, a[ia+j], rax
      ctx.add v, rax
      ctx.adc u, rdx
      ctx.adc t, 0

    ctx.mov r[i], v

    if i != stopEx - 1:
      ctx.mov v, u
      ctx.mov u, t
      ctx.`xor` t, t

  if aLen+bLen < rLen:
    ctx.`xor` rax, rax
    for i in aLen+bLen ..< rLen:
      ctx.mov r[i], rax

  # Codegen
  result.add ctx.generate()

func mul_asm*[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mul_gen(r, a, b)

# Squaring
# -----------------------------------------------------------------------------------------------

macro sqr_gen*[rLen, aLen: static int](r_PIR: var Limbs[rLen], a_MEM: Limbs[aLen]) =
  ## Comba squaring generator
  ## `a` and `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len * 2
  ## The result will be truncated, i.e. it will be
  ## a² (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## Assumes r doesn't aliases a

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, rLen, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    a = asmArray(a_MEM, aLen, MemOffsettable, asmInput)

    tSym = ident"t"
    t = asmValue(tSym, Reg, asmOutputEarlyClobber)
    uSym = ident"u"
    u = asmValue(uSym, Reg, asmOutputEarlyClobber)
    vSym = ident"v"
    v = asmValue(vSym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `tSym`{.noInit.}, `uSym`{.noInit.}, `vSym`{.noInit.}: BaseType

  # Zero-init
  ctx.`xor` u, u
  ctx.`xor` v, v
  ctx.`xor` t, t

  # Algorithm
  let stopEx = min(aLen*2, rLen)

  for i in 0 ..< stopEx:
    # Invariant for product scanning:
    # if we multiply accumulate by a[k1] * b[k2]
    # we have k1+k2 == i
    let ib = min(aLen-1, i)
    let ia = i - ib
    for j in 0 ..< min(aLen - ia, ib+1):
      let k1 = ia+j
      let k2 = ib-j
      if k1 < k2:
        # (t, u, v) <- (t, u, v) + 2 * a[k1] * a[k2]
        ctx.mov rax, a[k2]
        ctx.mul rdx, rax, a[k1], rax
        ctx.add rax, rax
        ctx.adc rdx, rdx
        ctx.adc t, 0
        ctx.add v, rax
        ctx.adc u, rdx
        ctx.adc t, 0
      elif k1 == k2:
        # (t, u, v) <- (t, u, v) + a[k1] * a[k2]
        ctx.mov rax, a[k2]
        ctx.mul rdx, rax, a[k1], rax
        ctx.add v, rax
        ctx.adc u, rdx
        ctx.adc t, 0
      else:
        discard

    ctx.mov r[i], v

    if i != stopEx - 1:
      ctx.mov v, u
      ctx.mov u, t
      ctx.`xor` t, t

  if aLen*2 < rLen:
    ctx.`xor` rax, rax
    for i in aLen*2 ..< rLen:
      ctx.mov r[i], rax

  # Codegen
  result.add ctx.generate()

func square_asm*[rLen, aLen: static int](r: var Limbs[rLen], a: Limbs[aLen]) =
  ## Multi-precision Squaring
  ## Assumes r doesn't alias a
  sqr_gen(r, a)
