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
  ../limbs,
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

# Montgomery reduction
# ------------------------------------------------------------

macro montyRedx_gen[N: static int](
       r_MR: var array[N, SecretWord],
       t_MR: array[N*2, SecretWord],
       M_MR: array[N, SecretWord],
       m0ninv_MR: BaseType,
       canUseNoCarryMontyMul: static bool
      ) =
  # TODO, slower than Clang, in particular due to the shadowing

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MR, N, PointerInReg, Input)

    hi = Operand(
      desc: OperandDesc(
        asmId: "[hi]",
        nimSymbol: ident"hi",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "hi"
      )
    )

    lo = Operand(
      desc: OperandDesc(
        asmId: "[lo]",
        nimSymbol: ident"lo",
        rm: Reg,
        constraint: Output_EarlyClobber,
        cEmit: "lo"
      )
    )

    rRDX = Operand(
      desc: OperandDesc(
        asmId: "[rdx]",
        nimSymbol: ident"rdx",
        rm: RDX,
        constraint: InputOutput_EnsureClobber,
        cEmit: "rdx"
      )
    )

    m0ninv = Operand(
      desc: OperandDesc(
        asmId: "[m0ninv]",
        nimSymbol: m0ninv_MR,
        rm: Reg,
        constraint: Input,
        cEmit: "m0ninv"
      )
    )

  let scratchSlots = N+1
  var scratch = init(OperandArray, nimSymbol = ident"scratch", scratchSlots, ElemsInReg, InputOutput_EnsureClobber)

  # Prologue
  let edx = rRDX.desc.nimSymbol
  let hisym = hi.desc.nimSymbol
  let losym = lo.desc.nimSymbol
  let scratchSym = scratch.nimSymbol
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `hisym`{.noInit.}, `losym`{.noInit.}, `edx`{.noInit.}: BaseType
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   hi <- 0
  #   m <- t[i] * m0ninv mod 2^w (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (hi, lo) <- t[i+j] + m * M[j] + hi
  #     t[i+j] <- lo
  #   t[i+n] += hi
  # for i in 0 .. n-1:
  #   r[i] = t[i+n]
  # if r >= M:
  #   r -= M

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  result.add quote do:
    `edx` = BaseType(`m0ninv_MR`)
    `scratchSym`[0 .. `N`-1] = `t_MR`.toOpenArray(0, `N`-1)

  for i in 0 ..< N:
    # RDX contains m0ninv at the start of each loop
    ctx.comment ""
    ctx.imul rRDX, scratch[0] # m <- t[i] * m0ninv mod 2^w
    ctx.comment "---- Reduction " & $i
    ctx.`xor` scratch[N], scratch[N]

    for j in 0 ..< N-1:
      ctx.comment ""
      ctx.mulx hi, lo, M[j], rdx
      ctx.adcx scratch[j], lo
      ctx.adox scratch[j+1], hi

    # Last limb
    ctx.comment ""
    ctx.mulx hi, lo, M[N-1], rdx
    ctx.mov rRDX, m0ninv # Reload m0ninv for next iter
    ctx.adcx scratch[N-1], lo
    ctx.adox hi, scratch[N]
    ctx.adcx scratch[N], hi

    scratch.rotateLeft()

  # Code generation
  result.add ctx.generate()

  # New codegen
  ctx = init(Assembler_x86, BaseType)

  let r = init(OperandArray, nimSymbol = r_MR, N, PointerInReg, InputOutput_EnsureClobber)
  let t = init(OperandArray, nimSymbol = t_MR, N*2, PointerInReg, Input)
  let extraRegNeeded = N-1
  let tsub = init(OperandArray, nimSymbol = ident"tsub", extraRegNeeded, ElemsInReg, InputOutput_EnsureClobber)
  let tsubsym = tsub.nimSymbol
  result.add quote do:
    var `tsubsym` {.noInit.}: Limbs[`extraRegNeeded`]

  # This does t[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = t[i+n]"
  for i in 0 ..< N:
    if i == 0:
      ctx.add scratch[i], t[i+N]
    else:
      ctx.adc scratch[i], t[i+N]

  let reuse = repackRegisters(tsub, scratch[N])

  if canUseNoCarryMontyMul:
    ctx.finalSubNoCarry(r, scratch, M, reuse)
  else:
    ctx.finalSubCanOverflow(r, scratch, M, reuse, hi)

  # Code generation
  result.add ctx.generate()

func montRed_asm_adx_bmi2*[N: static int](
       r: var array[N, SecretWord],
       t: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       canUseNoCarryMontyMul: static bool
      ) =
  ## Constant-time Montgomery reduction
  montyRedx_gen(r, t, M, m0ninv, canUseNoCarryMontyMul)
