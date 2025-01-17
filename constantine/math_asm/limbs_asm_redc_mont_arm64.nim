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

# No exceptions allowed
{.push raises: [].}

# Montgomery reduction
# ------------------------------------------------------------

macro redc2xMont_gen[N: static int](
       r_PIR: var array[N, SecretWord],
       a_PIR: array[N*2, SecretWord],
       M_REG: array[N, SecretWord],
       m0ninv_REG: BaseType,
       spareBits: static int, lazyReduce: static bool) =

  # No register spilling handling
  doAssert N in {3..8}, "The Assembly-optimized montgomery multiplication requires at most 12 limbs."

  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)

  let
    r = asmArray(r_PIR, N, PointerInReg, asmInput, memIndirect = memWrite)
    M = asmArray(M_REG, N, ElemsInReg, asmInput)
    uSlots = N+1
    vSlots = max(N, 5)
    uSym = ident"u"
    vSym = ident"v"

  var # Scratchspaces
    u = asmArray(uSym, uSlots, ElemsInReg, asmInputOutputEarlyClobber)
    v = asmArray(vSym, vSlots, ElemsInReg, asmInputOutputEarlyClobber)

  # Prologue
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)
    var `uSym`{.noinit, used.}: Limbs[`uSlots`]
    var `vSym` {.noInit.}: Limbs[`vSlots`]
    `vSym`[0] = cast[SecretWord](`a_PIR`[0].unsafeAddr)
    `vSym`[1] = SecretWord(`m0ninv_REG`)

  let a = v[0].asArrayAddr(a_PIR, len = 2*N, memIndirect = memRead)
  let m0ninv = v[1]
  let m = v[2]
  var t0 = v[3]
  var t1 = v[4]

  template mulloadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul t0, lhs, rhs
    ctx.adcs dst, addend, t0
    swap(t0, t1)

  template mulhiadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh t0, lhs, rhs
    ctx.adds dst, addend, t0
    swap(t0, t1)
  template mulhiadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh t0, lhs, rhs
    ctx.adcs dst, addend, t0
    swap(t0, t1)
  template mulhiadd_ci(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh t0, lhs, rhs
    ctx.adc dst, addend, t0
    swap(t0, t1)

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   hi <- 0
  #   m <- a[i] * m0ninv mod 2ʷ (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (hi, lo) <- a[i+j] + m * M[j] + hi
  #     a[i+j] <- lo
  #   a[i+n] += hi
  # for i in 0 .. n-1:
  #   r[i] = a[i+n]
  # if r >= M:
  #   r -= M

  result.add quote do:
    staticFor i, 0, `N`:
      `uSym`[i] = `a_PIR`[i]

  for i in 0 ..< N:
    ctx.comment ""
    ctx.mul m, u[0], m0ninv # m <- a[i] * m0ninv mod 2ʷ
    ctx.comment "---- Reduction " & $i
    ctx.mul t0, m, M[0]
    ctx.cmn u[0], t0
    swap(t0, t1)
    ctx.mov u[N], xzr

    for j in 0 ..< N:
      ctx.comment ""
      ctx.mulloadd_cio(u[j], m, M[j], u[j])
    ctx.adc u[N], xzr, xzr

    # assumes N > 1
    ctx.mulhiadd_co(u[1], m, M[0], u[1])
    for j in 1 ..< N-1:
      ctx.mulhiadd_cio(u[j+1], m, M[j], u[j+1])
    ctx.mulhiadd_ci(u[N], m, M[N-1], u[N])

    u.rotateLeft()

  # This does a[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = a[i+n]"
  for i in 0 ..< N:
    ctx.ldr t0, a[i+N]
    if i == 0:
      ctx.adds u[i], u[i], t0
    elif i == N-1:
      ctx.adc u[i], u[i], t0
    else:
      ctx.adcs u[i], u[i], t0
    swap(t0, t1)

  if spareBits >= 2 and lazyReduce:
    for i in 0 ..< N:
      ctx.str u[i], r[i]
  elif spareBits >= 1: # finalSubNoOverflow
    for i in 0 ..< N:
      if i == 0:
        ctx.subs v[i], u[i], M[i]
      else:
        ctx.sbcs v[i], u[i], M[i]

    # if carry clear t < M, so pick t
    for i in 0 ..< N:
      ctx.csel u[i], u[i], v[i], cc
      ctx.str u[i], r[i]
  else:                # finalSubMayOverflow
    let carryReg = u[N]
    ctx.adc carryReg, xzr, xzr

    # v = u - M
    for i in 0 ..< N:
      if i == 0:
        ctx.subs v[i], u[i], M[i]
      else:
        ctx.sbcs v[i], u[i], M[i]

    # If it underflows here, it means that it was
    # smaller than the modulus and we don't need `v`
    ctx.sbcs xzr, carryReg, xzr

    # if carry clear u < M, so pick u
    for i in 0 ..< N:
      ctx.csel u[i], u[i], v[i], cc
      ctx.str u[i], r[i]

  # Code generation
  result.add ctx.generate()

func redcMont_asm*[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       spareBits: static int,
       lazyReduce: static bool = false) =
  ## Constant-time Montgomery reduction
  redc2xMont_gen(r, a, M, m0ninv, spareBits, lazyReduce)
