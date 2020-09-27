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
  ../../config/common,
  ../../primitives

# ############################################################
#
#        Assembly implementation of bigint multiplication
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

# TODO: verify that assembly generated works for small arrays
#       that are passed by values

static: doAssert UseASM_X86_64 # Need 8 registers just for mul
                               # and 32-bit only has 8 max.

macro mul_gen[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Comba multiplication generator
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitwidth)^r.limbs.len)
  ##
  ## Assumes r doesn't aliases a or b

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    arrR = init(OperandArray, nimSymbol = r, rLen, PointerInReg, InputOutput_EnsureClobber)
    arrA = init(OperandArray, nimSymbol = a, aLen, PointerInReg, Input)
    arrB = init(OperandArray, nimSymbol = b, bLen, PointerInReg, Input)

    t = Operand(
      desc: OperandDesc(
        asmId: "[t]",
        nimSymbol: ident"t",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t"
      )
    )

    u = Operand(
      desc: OperandDesc(
        asmId: "[u]",
        nimSymbol: ident"u",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "u"
      )
    )

    v = Operand(
      desc: OperandDesc(
        asmId: "[v]",
        nimSymbol: ident"v",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "v"
      )
    )

    # MUL requires RAX and RDX
    rRAX = Operand(
      desc: OperandDesc(
        asmId: "[rax]",
        nimSymbol: ident"rax",
        rm: RAX,
        constraint: Output_EarlyClobber,
        cEmit: "rax"
      )
    )

    rRDX = Operand(
      desc: OperandDesc(
        asmId: "[rdx]",
        nimSymbol: ident"rdx",
        rm: RDX,
        constraint: Output_EarlyClobber,
        cEmit: "rdx"
      )
    )


  # Prologue
  let tsym = t.desc.nimSymbol
  let usym = u.desc.nimSymbol
  let vsym = v.desc.nimSymbol
  let eax = rRAX.desc.nimSymbol
  let edx = rRDX.desc.nimSymbol
  result.add quote do:
    var `tsym`{.noInit.}, `usym`{.noInit.}, `vsym`{.noInit.}: BaseType # zero-init
    var `eax`{.noInit.}, `edx`{.noInit.}: BaseType

  # Algorithm
  ctx.`xor` u, u
  ctx.`xor` v, v
  ctx.`xor` t, t

  for i in 0 ..< min(aLen+bLen, rLen):
    let ib = min(bLen-1, i)
    let ia = i - ib
    for j in 0 ..< min(aLen - ia, ib+1):
      # (t, u, v) <- (t, u, v) + a[ia+j] * b[ib-j]
      ctx.mov rRAX, arrB[ib-j]
      ctx.mul rdx, rax, arrA[ia+j], rax
      ctx.add v, rRAX
      ctx.adc u, rRDX
      ctx.adc t, 0

    ctx.mov arrR[i], v

    if i != min(aLen+bLen, rLen) - 1:
      ctx.mov v, u
      ctx.mov u, t
      ctx.`xor` t, t

  if aLen+bLen < rLen:
    ctx.`xor` rRAX, rRAX
    for i in aLen+bLen ..< rLen:
      ctx.mov arrR[i], rRAX

  # Codegen
  result.add ctx.generate

func mul_asm*[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mul_gen(r, a, b)
