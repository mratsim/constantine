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
  ../../primitives,
  ./limbs_asm_montred_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

# TODO, MCL has an implementation about 14% faster

static: doAssert UseASM_X86_64

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

# No exceptions allowed
{.push raises: [].}

# Montgomery reduction
# ------------------------------------------------------------

macro montyRedc2x_adx_gen*[N: static int](
       r_MR: var array[N, SecretWord],
       a_MR: array[N*2, SecretWord],
       M_MR: array[N, SecretWord],
       m0ninv_MR: BaseType,
       hasSpareBit: static bool
      ) =
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MR, N, PointerInReg, Input)

  let uSlots = N+1
  let vSlots = max(N-1, 5)

  var # Scratchspaces
    u = init(OperandArray, nimSymbol = ident"U", uSlots, ElemsInReg, InputOutput_EnsureClobber)
    v = init(OperandArray, nimSymbol = ident"V", vSlots, ElemsInReg, InputOutput_EnsureClobber)

  # Prologue
  let usym = u.nimSymbol
  let vsym = v.nimSymbol
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)
    var `usym`{.noinit.}: Limbs[`uSlots`]
    var `vsym` {.noInit.}: Limbs[`vSlots`]
    `vsym`[0] = cast[SecretWord](`r_MR`[0].unsafeAddr)
    `vsym`[1] = cast[SecretWord](`a_MR`[0].unsafeAddr)
    `vsym`[2] = SecretWord(`m0ninv_MR`)

  let r_temp = v[0].asArrayAddr(len = N)
  let a = v[1].asArrayAddr(len = 2*N)
  let m0ninv = v[2]
  let lo = v[3]
  let hi = v[4]

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   hi <- 0
  #   m <- a[i] * m0ninv mod 2^w (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (hi, lo) <- a[i+j] + m * M[j] + hi
  #     a[i+j] <- lo
  #   a[i+n] += hi
  # for i in 0 .. n-1:
  #   r[i] = a[i+n]
  # if r >= M:
  #   r -= M

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  ctx.mov rdx, m0ninv

  for i in 0 ..< N:
    ctx.mov u[i], a[i]

  for i in 0 ..< N:
    # RDX contains m0ninv at the start of each loop
    ctx.comment ""
    ctx.imul rdx, u[0] # m <- a[i] * m0ninv mod 2^w
    ctx.comment "---- Reduction " & $i
    ctx.`xor` u[N], u[N]

    for j in 0 ..< N-1:
      ctx.comment ""
      ctx.mulx hi, lo, M[j], rdx
      ctx.adcx u[j], lo
      ctx.adox u[j+1], hi

    # Last limb
    ctx.comment ""
    ctx.mulx hi, lo, M[N-1], rdx
    ctx.mov rdx, m0ninv # Reload m0ninv for next iter
    ctx.adcx u[N-1], lo
    ctx.adox hi, u[N]
    ctx.adcx u[N], hi

    u.rotateLeft()

  ctx.mov rdx, r_temp
  let r = rdx.asArrayAddr(len = N)

  # This does a[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = a[i+n]"
  for i in 0 ..< N:
    if i == 0:
      ctx.add u[i], a[i+N]
    else:
      ctx.adc u[i], a[i+N]

  let t = repackRegisters(v, u[N])

  if hasSpareBit:
    ctx.finalSubNoCarry(r, u, M, t)
  else:
    ctx.finalSubCanOverflow(r, u, M, t, hi)

  # Code generation
  result.add ctx.generate()

func montRed_asm_adx_bmi2*[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       hasSpareBit: static bool
      ) =
  ## Constant-time Montgomery reduction
  montyRedc2x_adx_gen(r, a, M, m0ninv, hasSpareBit)
