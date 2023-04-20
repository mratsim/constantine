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
#        Assembly implementation of bigints
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseASM_X86_32

# Copy
# ------------------------------------------------------------
macro ccopy_gen[N: static int](a_PIR: var Limbs[N], b_PIR: Limbs[N], ctl: SecretBool): untyped =
  ## Generate an optimized conditional copy kernel
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)

  let
    a = asmArray(a_PIR, N, PointerInReg, UnmutatedPointerToReadWriteMem)
    b = asmArray(b_PIR, N, PointerInReg, Input)

    control = asmValue(ctl, Reg, Input)

    t0Sym = ident"t0"
    t1Sym = ident"t1"

  var # Swappable registers to break dependency chains
    t0 = asmValue(t0Sym, Reg, Output_EarlyClobber)
    t1 = asmValue(t1Sym, Reg, Output_EarlyClobber)

  # Prologue
  result.add quote do:
    var `t0sym`{.noinit.}, `t1sym`{.noinit.}: BaseType

  # Algorithm
  ctx.test control, control
  for i in 0 ..< N:
    ctx.mov t0, a[i]
    ctx.cmovnz t0, b[i]
    ctx.mov a[i], t0
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

macro add_gen[N: static int](carry: var Carry, r_PIR: var Limbs[N], a_PIR, b_PIR: Limbs[N]): untyped =
  ## Generate an optimized out-of-place addition kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, N, PointerInReg, InputOutput) # TODO: otherwise wrong Poly1305 results
    a = asmArray(a_PIR, N, PointerInReg, Input)
    b = asmArray(b_PIR, N, PointerInReg, Input)

    t0Sym = ident"t0"
    t1Sym = ident"t1"

  var # Swappable registers to break dependency chains
    t0 = asmValue(t0Sym, Reg, Output_EarlyClobber)
    t1 = asmValue(t1Sym, Reg, Output_EarlyClobber)

  # Prologue
  result.add quote do:
    var `t0sym`{.noinit.}, `t1sym`{.noinit.}: BaseType

  # Algorithm
  ctx.mov t0, a[0]     # Prologue
  ctx.add t0, b[0]

  for i in 1 ..< N:
    ctx.mov t1, a[i]   # Prepare the next iteration
    ctx.mov r[i-1], t0 # Save the previous result in an interleaved manner
    ctx.adc t1, b[i]   # Compute
    swap(t0, t1)       # Break dependency chain

  ctx.mov r[N-1], t0   # Epilogue
  ctx.setToCarryFlag(carry)

  # Codegen
  result.add ctx.generate()

func add_asm*(r: var Limbs, a, b: Limbs): Carry {.inline.}=
  ## Constant-time addition
  add_gen(result, r, a, b)

# Substraction
# ------------------------------------------------------------

macro sub_gen[N: static int](borrow: var Borrow, r_PIR: var Limbs[N], a_PIR, b_PIR: Limbs[N]): untyped =
  ## Generate an optimized out-of-place substraction kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, N, PointerInReg, InputOutput) # TODO: otherwise wrong endomorphism acceleration results
    a = asmArray(a_PIR, N, PointerInReg, Input)
    b = asmArray(b_PIR, N, PointerInReg, Input)

    t0Sym = ident"t0"
    t1Sym = ident"t1"

  var # Swappable registers to break dependency chains
    t0 = asmValue(t0Sym, Reg, Output_EarlyClobber)
    t1 = asmValue(t1Sym, Reg, Output_EarlyClobber)

  # Prologue
  result.add quote do:
    var `t0sym`{.noinit.}, `t1sym`{.noinit.}: BaseType

  # Algorithm
  ctx.mov t0, a[0]     # Prologue
  ctx.sub t0, b[0]

  for i in 1 ..< N:
    ctx.mov t1, a[i]   # Prepare the next iteration
    ctx.mov r[i-1], t0 # Save the previous reult in an interleaved manner
    ctx.sbb t1, b[i]   # Compute
    swap(t0, t1)       # Break dependency chain

  ctx.mov r[N-1], t0   # Epilogue
  ctx.setToCarryFlag(borrow)

  # Codegen
  result.add ctx.generate()

func sub_asm*(r: var Limbs, a, b: Limbs): Borrow {.inline.}=
  ## Constant-time substraction
  sub_gen(result, r, a, b)
