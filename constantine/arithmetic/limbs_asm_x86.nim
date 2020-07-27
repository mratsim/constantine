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
  ../config/common,
  ../primitives

# ############################################################
#
#        Assembly implementation of bigints
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

# TODO: verify that assembly generated works for small arrays
#       that are passed by values

static: doAssert UseASM_X86_32

# Copy
# ------------------------------------------------------------
macro ccopy_gen[N: static int](a: var Limbs[N], b: Limbs[N], ctl: SecretBool): untyped =
  ## Generate an optimized conditional copy kernel
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)

  let
    arrA = init(OperandArray, nimSymbol = a, N, PointerInReg, InputOutput)
    arrB = init(OperandArray, nimSymbol = b, N, PointerInReg, Input)

    control = Operand(
      desc: OperandDesc(
        asmId: "[ctl]",
        nimSymbol: ctl,
        rm: Reg,
        constraint: Input,
        cEmit: "ctl"
      )
    )

  var # Swappable registers to break dependency chains
    t0 = Operand(
      desc: OperandDesc(
        asmId: "[t0]",
        nimSymbol: ident"t0",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t0"
      )
    )

    t1 = Operand(
      desc: OperandDesc(
        asmId: "[t1]",
        nimSymbol: ident"t1",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t1"
      )
    )

  # Prologue
  let t0sym = t0.desc.nimSymbol
  let t1sym = t1.desc.nimSymbol
  result.add quote do:
    var `t0sym`{.noinit.}, `t1sym`{.noinit.}: BaseType

  # Algorithm
  ctx.test control, control
  for i in 0 ..< N:
    ctx.mov t0, arrA[i]
    ctx.cmovnz t0, arrB[i]
    ctx.mov arrA[i], t0
    swap(t0, t1)

  # Codegen
  result.add ctx.generate()

func ccopy_asm*(a: var Limbs, b: Limbs, ctl: SecretBool) {.inline.}=
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  ccopy_gen(a, b, ctl)

# Addition
# ------------------------------------------------------------

macro add_gen[N: static int](carry: var Carry, r: var Limbs[N], a, b: Limbs[N]): untyped =
  ## Generate an optimized out-of-place addition kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    arrR = init(OperandArray, nimSymbol = r, N, PointerInReg, InputOutput)
    arrA = init(OperandArray, nimSymbol = a, N, PointerInReg, Input)
    arrB = init(OperandArray, nimSymbol = b, N, PointerInReg, Input)

  var # Swappable registers to break dependency chains
    t0 = Operand(
      desc: OperandDesc(
        asmId: "[t0]",
        nimSymbol: ident"t0",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t0"
      )
    )

    t1 = Operand(
      desc: OperandDesc(
        asmId: "[t1]",
        nimSymbol: ident"t1",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t1"
      )
    )

  # Prologue
  let t0sym = t0.desc.nimSymbol
  let t1sym = t1.desc.nimSymbol
  result.add quote do:
    var `t0sym`{.noinit.}, `t1sym`{.noinit.}: BaseType

  # Algorithm
  for i in 0 ..< N:
    ctx.mov t0, arrA[i]
    if i == 0:
      ctx.add t0, arrB[0]
    else:
      ctx.adc t0, arrB[i]
    ctx.mov arrR[i], t0
    swap(t0, t1)
  ctx.setToCarryFlag(carry)

  # Codegen
  result.add ctx.generate

func add_asm*(r: var Limbs, a, b: Limbs): Carry {.inline.}=
  ## Constant-time addition
  add_gen(result, r, a, b)

# Substraction
# ------------------------------------------------------------

macro sub_gen[N: static int](borrow: var Borrow, r: var Limbs[N], a, b: Limbs[N]): untyped =
  ## Generate an optimized out-of-place addition kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    arrR = init(OperandArray, nimSymbol = r, N, PointerInReg, InputOutput)
    arrA = init(OperandArray, nimSymbol = a, N, PointerInReg, Input)
    arrB = init(OperandArray, nimSymbol = b, N, PointerInReg, Input)

  var # Swappable registers to break dependency chains
    t0 = Operand(
      desc: OperandDesc(
        asmId: "[t0]",
        nimSymbol: ident"t0",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t0"
      )
    )

    t1 = Operand(
      desc: OperandDesc(
        asmId: "[t1]",
        nimSymbol: ident"t1",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "t1"
      )
    )

  # Prologue
  let t0sym = t0.desc.nimSymbol
  let t1sym = t1.desc.nimSymbol
  result.add quote do:
    var `t0sym`{.noinit.}, `t1sym`{.noinit.}: BaseType

  # Algorithm
  for i in 0 ..< N:
    ctx.mov t0, arrA[i]
    if i == 0:
      ctx.sub t0, arrB[0]
    else:
      ctx.sbb t0, arrB[i]
    ctx.mov arrR[i], t0
    swap(t0, t1)
  ctx.setToCarryFlag(borrow)

  # Codegen
  result.add ctx.generate

func sub_asm*(r: var Limbs, a, b: Limbs): Borrow {.inline.}=
  ## Constant-time addition
  sub_gen(result, r, a, b)

# Multiplication
# ------------------------------------------------------------

macro mul_gen[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) {.inline.} =
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

func mul_asm*[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) {.inline.} =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mul_gen(r, a, b)
