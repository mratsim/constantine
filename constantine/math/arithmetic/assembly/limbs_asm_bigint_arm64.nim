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
#        Assembly implementation of bigints
#
# ############################################################

static: doAssert UseASM_ARM64

# Copy
# ------------------------------------------------------------

macro ccopy_gen[N: static int](a_PIR: var Limbs[N], b_PIR: Limbs[N], ctl: SecretBool): untyped =
  ## Generate an optimized conditional copy kernel
  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)

  let
    # MemOffsettable is the better constraint but
    # with ARM64 we cannot generate array offsets from it due to inline ASM auto-bracketings
    a = asmArray(a_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memReadWrite)
    b = asmArray(b_PIR, N, PointerInReg, asmInput, memIndirect = memRead)

    control = asmValue(ctl, Reg, asmInput)

    u0Sym = ident"u0"
    u1Sym = ident"u1"
    v0Sym = ident"v0"
    v1Sym = ident"v1"

  var # Swappable registers to break dependency chains
    u0 = asmValue(u0Sym, Reg, asmOutputEarlyClobber)
    u1 = asmValue(u1Sym, Reg, asmOutputEarlyClobber)
    v0 = asmValue(v0Sym, Reg, asmOutputEarlyClobber)
    v1 = asmValue(v1Sym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `u0sym`{.noinit.}, `u1sym`{.noinit.}: BaseType
    var `v0sym`{.noinit.}, `v1sym`{.noinit.}: BaseType

  # Algorithm
  if N >= 2:
    ctx.ldp u0, u1, a[0]
    ctx.ldp v0, v1, b[0]
  else:
    ctx.ldr u0, a[0]
    ctx.ldr v0, b[0]

  # Algorithm
  ctx.cmp control, xzr      # Check vs 0
  for i in 0 ..< N:
    ctx.csel u0, u0, v0, eq # Don't modify if eq 0
    ctx.str u0, a[i]

    # Next iteration
    if i != N-1:
      swap(u0, u1)
      swap(v0, v1)
      if i+2 < N:
        ctx.ldr u1, a[i+2]
        ctx.ldr v1, b[i+2]

  # Codegen
  result.add ctx.generate()

func ccopy_asm*(a: var Limbs, b: Limbs, ctl: SecretBool) =
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

  var ctx = init(Assembler_arm64, BaseType)
  let
    # MemOffsettable is the better constraint but
    # with ARM64 we cannot generate array offsets from it due to inline ASM auto-bracketings
    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite)
    a = asmArray(a_PIR, N, PointerInReg, asmInput, memIndirect = memRead)
    b = asmArray(b_PIR, N, PointerInReg, asmInput, memIndirect = memRead)

    u0Sym = ident"u0"
    u1Sym = ident"u1"
    v0Sym = ident"v0"
    v1Sym = ident"v1"

  var # Swappable registers to break dependency chains
    u0 = asmValue(u0Sym, Reg, asmOutputEarlyClobber)
    u1 = asmValue(u1Sym, Reg, asmOutputEarlyClobber)
    v0 = asmValue(v0Sym, Reg, asmOutputEarlyClobber)
    v1 = asmValue(v1Sym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `u0sym`{.noinit.}, `u1sym`{.noinit.}: BaseType
    var `v0sym`{.noinit.}, `v1sym`{.noinit.}: BaseType

  # Algorithm
  if N >= 2:
    ctx.ldp u0, u1, a[0]
    ctx.ldp v0, v1, b[0]
  else:
    ctx.ldr u0, a[0]
    ctx.ldr v0, b[0]

  for i in 0 ..< N:
    if i == 0:
      ctx.adds u0, u0, v0
    else:
      ctx.adcs u0, u0, v0
    ctx.str u0, r[i]

    # Next iteration
    if i != N-1:
      swap(u0, u1)
      swap(v0, v1)
      if i+2 < N:
        ctx.ldr u1, a[i+2]
        ctx.ldr v1, b[i+2]

  ctx.setOutputToFlag(carry, CarryFlag)

  # Codegen
  result.add ctx.generate()

func add_asm*(r: var Limbs, a, b: Limbs): Carry =
  ## Constant-time addition
  add_gen(result, r, a, b)

# Subtraction
# ------------------------------------------------------------

macro sub_gen[N: static int](borrow: var Borrow, r_PIR: var Limbs[N], a_PIR, b_PIR: Limbs[N]): untyped =
  ## Generate an optimized out-of-place subtraction kernel
  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)
  let
    # MemOffsettable is the better constraint but
    # with ARM64 we cannot generate array offsets from it due to inline ASM auto-bracketings
    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite)
    a = asmArray(a_PIR, N, PointerInReg, asmInput, memIndirect = memRead)
    b = asmArray(b_PIR, N, PointerInReg, asmInput, memIndirect = memRead)

    u0Sym = ident"u0"
    u1Sym = ident"u1"
    v0Sym = ident"v0"
    v1Sym = ident"v1"

  var # Swappable registers to break dependency chains
    u0 = asmValue(u0Sym, Reg, asmOutputEarlyClobber)
    u1 = asmValue(u1Sym, Reg, asmOutputEarlyClobber)
    v0 = asmValue(v0Sym, Reg, asmOutputEarlyClobber)
    v1 = asmValue(v1Sym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `u0sym`{.noinit.}, `u1sym`{.noinit.}: BaseType
    var `v0sym`{.noinit.}, `v1sym`{.noinit.}: BaseType

  # Algorithm
  if N >= 2:
    ctx.ldp u0, u1, a[0]
    ctx.ldp v0, v1, b[0]
  else:
    ctx.ldr u0, a[0]
    ctx.ldr v0, b[0]

  for i in 0 ..< N:
    if i == 0:
      ctx.subs u0, u0, v0
    else:
      ctx.sbcs u0, u0, v0
    ctx.str u0, r[i]

    # Next iteration
    if i != N-1:
      swap(u0, u1)
      swap(v0, v1)
      if i+2 < N:
        ctx.ldr u1, a[i+2]
        ctx.ldr v1, b[i+2]

  ctx.setOutputToFlag(borrow, BorrowFlag)

  # Codegen
  result.add ctx.generate()

func sub_asm*(r: var Limbs, a, b: Limbs): Carry =
  ## Constant-time subtraction
  sub_gen(result, r, a, b)