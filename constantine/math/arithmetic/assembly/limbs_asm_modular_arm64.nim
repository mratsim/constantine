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
#        Assembly implementation of finite fields
#
# ############################################################

static: doAssert UseASM_ARM64


# Field addition
# ------------------------------------------------------------

macro addmod_gen[N: static int](r_PIR: var Limbs[N], a_PIR, b_PIR, M_PIR: Limbs[N], spareBits: static int): untyped =
  ## Generate an optimized modular addition kernel
  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)
  let
    # MemOffsettable is the better constraint but
    # with ARM64 we cannot generate array offsets from it due to inline ASM auto-bracketings
    r = asmArray(r_PIR, N, PointerInReg, asmInput, memIndirect = memWrite)
    a = asmArray(a_PIR, N, PointerInReg, asmInput, memIndirect = memRead)
    b = asmArray(b_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memRead)
    # We could force m as immediate by specializing per moduli
    M = asmArray(M_PIR, N, PointerInReg, asmInput, memIndirect = memRead)

    # Temp storage
    uSym = ident"u"
    vSym = ident"v"
    u = asmArray(uSym, N, ElemsInReg, asmOutputEarlyClobber)
    v = asmArray(vSym, N, ElemsInReg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `usym`{.noinit, used.}, `vsym` {.noInit, used.}: typeof(`a_PIR`)

  # Algorithm
  if N >= 2:
    ctx.ldp u[0], u[1], a[0]
    ctx.ldp v[0], v[1], b[0]
  else:
    ctx.ldr u[0], a[0]
    ctx.ldr v[0], b[0]

  # u = a + b
  for i in 0 ..< N:
    if i == 0:
      ctx.adds u[i], u[i], v[i]
    elif i == N-1 and spareBits >= 1:
      ctx.adc u[i], u[i], v[i]
    else:
      ctx.adcs u[i], u[i], v[i]

    # Next iteration
    if i+2 < N:
      ctx.ldr u[i+2], a[i+2]
      ctx.ldr v[i+2], b[i+2]
    elif 0 <= i-(N-2):
      # Preload M
      if i-(N-2) >= N:
        # This can only occur if N == 1, for example in t_multilinear_extensions
        ctx.ldr v[0], M[0]
      else:
        ctx.ldr v[i-(N-2)], M[i-(N-2)]

  # M[0], M[1] is loaded into v[0], v[1]
  if spareBits >= 1:
    # Addition cannot overflow u256, u384, ...
    # v = u - M
    for i in 0 ..< N:
      if i == 0:
        ctx.subs v[i], u[i], v[i]
      else:
        ctx.sbcs v[i], u[i], v[i]

      # Next iteration
      if i+2 < N:
        ctx.ldr v[i+2], M[i+2]

    # if carry clear u < M, so pick u
    for i in 0 ..< N:
      ctx.csel u[i], u[i], v[i], cc
      ctx.str u[i], r[i]
  else:
    # Addition can overflow u256, u384, ...
    let carryReg = b.reuseRegister()
    ctx.adc carryReg, xzr, xzr

    # v = u - M
    for i in 0 ..< N:
      if i == 0:
        ctx.subs v[i], u[i], v[i]
      else:
        ctx.sbcs v[i], u[i], v[i]

      # Next iteration
      if i+2 < N:
        ctx.ldr v[i+2], M[i+2]

    # If it underflows here, it means that it was
    # smaller than the modulus and we don't need `v`
    ctx.sbcs xzr, carryReg, xzr

    # if carry clear u < M, so pick u
    for i in 0 ..< N:
      ctx.csel u[i], u[i], v[i], cc
      ctx.str u[i], r[i]

  result.add ctx.generate()

func addmod_asm*(r: var Limbs, a, b, M: Limbs, spareBits: static int) =
  ## Constant-time modular addition
  addmod_gen(r, a, b, M, spareBits)