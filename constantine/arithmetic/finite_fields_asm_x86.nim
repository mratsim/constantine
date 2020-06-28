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
  ../primitives,
  ./limbs

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

# Note: We can use at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseASM

# Copy
# ------------------------------------------------------------
macro ccopy_gen[N: static int](a: var Limbs[N], b: Limbs[N], ctl: SecretBool): untyped =
  ## Generate an optimized conditional copy kernel
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)

  let
    arrA = init(OperandArray, nimSymbol = a, N, MemoryOffsettable, InputOutput)
    arrB = init(OperandArray, nimSymbol = b, N, AnyMemOffImm, Input)
    # If N is too big, we need to spill registers. TODO.
    arrT = init(OperandArray, nimSymbol = ident"t", N, Register, Output_EarlyClobber)

    control = Operand(
      desc: OperandDesc(
        asmId: "[ctl]",
        nimSymbol: ctl,
        rm: Register,
        constraint: Input,
        cEmit: "ctl"
      )
    )

  ctx.test control, control
  for i in 0 ..< N:
    ctx.mov arrT[i], arrA[i]
    ctx.cmovnz arrT[i], arrB[i]
    ctx.mov arrA[i], arrT[i]

  let t = arrT.nimSymbol
  let c = control.desc.nimSymbol
  result.add quote do:
    var `t` {.noInit.}: typeof(`a`)
  result.add ctx.generate()

func ccopy_asm*(a: var Limbs, b: Limbs, ctl: SecretBool) {.inline.}=
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  ccopy_gen(a, b, ctl)

# Field addition
# ------------------------------------------------------------

macro addmod_gen[N: static int](a: var Limbs[N], b, M: Limbs[N]): untyped =
  ## Generate an optimized modular addition kernel
  # Register pressure note:
  #   We could generate a kernel per modulus M by hardocing it as immediate
  #   however this requires
  #     - duplicating the kernel and also
  #     - 64-bit immediate encoding is quite large

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    arrA = init(OperandArray, nimSymbol = a, N, MemoryOffsettable, InputOutput)
    arrB = init(OperandArray, nimSymbol = b, N, AnyMemOffImm, Input)
    # We could force M as immediate by specializing per moduli
    arrM = init(OperandArray, nimSymbol = M, N, AnyMemOffImm, Input)
    # If N is too big, we need to spill registers. TODO.
    arrT = init(OperandArray, nimSymbol = ident"t", N, Register, Output_EarlyClobber)
    arrTsub = init(OperandArray, nimSymbol = ident"tsub", N, Register, Output_EarlyClobber)

  # Addition
  for i in 0 ..< N:
    ctx.mov arrT[i], arrA[i]
    if i == 0:
      ctx.add arrT[0], arrB[0]
    else:
      ctx.adc arrT[i], arrB[i]
    # Interleaved copy in a second buffer as well
    ctx.mov arrTsub[i], arrT[i]

  # Now substract the modulus
  for i in 0 ..< N:
    if i == 0:
      ctx.sub arrTsub[0], arrM[0]
    else:
      ctx.sbb arrTsub[i], arrM[i]

  # Conditional Mov and
  # and store result
  for i in 0 ..< N:
    ctx.cmovnc arrT[i], arrTsub[i]
    ctx.mov arrA[i], arrT[i]

  let t = arrT.nimSymbol
  let tsub = arrTsub.nimSymbol
  result.add quote do:
    var `t`{.noinit.}, `tsub` {.noInit.}: typeof(`a`)
  result.add ctx.generate

func addmod_asm*(a: var Limbs, b, M: Limbs) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  addmod_gen(a, b, M)
