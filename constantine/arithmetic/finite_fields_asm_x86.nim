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
    arrA = init(OperandArray, nimSymbol = a, N, PointerInReg, InputOutput)
    arrB = init(OperandArray, nimSymbol = b, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    arrT = init(OperandArray, nimSymbol = ident"t", N, ElemsInReg, Output_EarlyClobber)

    control = Operand(
      desc: OperandDesc(
        asmId: "[ctl]",
        nimSymbol: ctl,
        rm: Reg,
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
    arrA = init(OperandArray, nimSymbol = a, N, PointerInReg, InputOutput)
    # We reuse the reg used for B for overflow detection
    arrB = init(OperandArray, nimSymbol = b, N, PointerInReg, InputOutput)
    # We could force M as immediate by specializing per moduli
    arrM = init(OperandArray, nimSymbol = M, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    arrT = init(OperandArray, nimSymbol = ident"t", N, ElemsInReg, Output_EarlyClobber)
    arrTsub = init(OperandArray, nimSymbol = ident"tsub", N, ElemsInReg, Output_EarlyClobber)

  # Addition
  for i in 0 ..< N:
    ctx.mov arrT[i], arrA[i]
    if i == 0:
      ctx.add arrT[0], arrB[0]
    else:
      ctx.adc arrT[i], arrB[i]
    # Interleaved copy in a second buffer as well
    ctx.mov arrTsub[i], arrT[i]

  let overflowed = arrB.reuseRegister()
  ctx.sbb overflowed, overflowed

  # Now substract the modulus
  for i in 0 ..< N:
    if i == 0:
      ctx.sub arrTsub[0], arrM[0]
    else:
      ctx.sbb arrTsub[i], arrM[i]

  ctx.sbb overflowed, 0

  # Conditional Mov and
  # and store result
  for i in 0 ..< N:
    ctx.cmovnc arrT[i],  arrTsub[i]
    ctx.mov arrA[i], arrT[i]

  let t = arrT.nimSymbol
  let tsub = arrTsub.nimSymbol
  result.add quote do:
    var `t`{.noinit.}, `tsub` {.noInit.}: typeof(`a`)
  result.add ctx.generate

func addmod_asm*(a: var Limbs, b, M: Limbs) {.noinline.}=
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  addmod_gen(a, b, M)

# Sanity checks
# ----------------------------------------------------------

when isMainModule:
  import ../config/type_bigint, algorithm, strutils

  proc main() =
    var a = [SecretWord 0xE3DF60E8F6D0AF9A'u64, SecretWord 0x7B2665C2258A7625'u64, SecretWord 0x68FC9A1D0977C8E0'u64, SecretWord 0xF3DC61ED7DE76883'u64]
    var b = [SecretWord 0x78E9C2EF58BB6B78'u64, SecretWord 0x547F65BD19014254'u64, SecretWord 0x556A115819EAD4B5'u64, SecretWord 0x8CA844A546935DC3'u64]
    var M = [SecretWord 0xFFFFFFFF00000001'u64, SecretWord 0x0000000000000000'u64, SecretWord 0x00000000FFFFFFFF'u64, SecretWord 0xFFFFFFFFFFFFFFFF'u64]
    var s = "0x5cc923d94f8c1b11cfa5cb7f3e8bb879be66ab7423629d968084a692c47ac647"

    a.reverse()
    b.reverse()
    M.reverse()

    debugecho "--------------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", M.toHex()
    addmod_asm(a, b, M)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

    a = [SecretWord 0x00935a991ca215a6'u64, SecretWord 0x5fbdac6294679337'u64, SecretWord 0x1e41793877b80f12'u64, SecretWord 0x5724cd93cb32932d'u64]
    b = [SecretWord 0x19dd4ecfda64ef80'u64, SecretWord 0x92deeb1532169c3d'u64, SecretWord 0x69ce4ee28421cd30'u64, SecretWord 0x4d90ab5a40295321'u64]
    M = [SecretWord 0x2523648240000001'u64, SecretWord 0xba344d8000000008'u64, SecretWord 0x6121000000000013'u64, SecretWord 0xa700000000000013'u64]
    s = "0x1a70a968f7070526f29c9777c67e2f74880fc81afbd9dc42a4b578ee0b5be64e"

    a.reverse()
    b.reverse()
    M.reverse()

    debugecho "--------------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", M.toHex()
    addmod_asm(a, b, M)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

    a = [SecretWord 0x1c7d810f37fc6e0b'u64, SecretWord 0xb91aba4ce339cea3'u64, SecretWord 0xd9f5571ccc4dfd1a'u64, SecretWord 0xf5906ee9df91f554'u64]
    b = [SecretWord 0x18394ffe94874c9f'u64, SecretWord 0x6e8a8ad032fc5f15'u64, SecretWord 0x7533a2b46b7e9530'u64, SecretWord 0x2849996b4bb61b48'u64]
    M = [SecretWord 0x2523648240000001'u64, SecretWord 0xba344d8000000008'u64, SecretWord 0x6121000000000013'u64, SecretWord 0xa700000000000013'u64]
    s = "0x0f936c8b8c83baa96d70f79d16362db0ee07f9d137cc923776da08552b481089"

    a.reverse()
    b.reverse()
    M.reverse()

    debugecho "--------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", M.toHex()
    addmod_asm(a, b, M)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

    a = [SecretWord 0xe9d55643'u64, SecretWord 0x580ec4cc3f91cef3'u64, SecretWord 0x11ecbb7d35b36449'u64, SecretWord 0x35535ca31c5dc2ba'u64]
    b = [SecretWord 0x97f7ed94'u64, SecretWord 0xbad96eb98204a622'u64, SecretWord 0xbba94400f9a061d6'u64, SecretWord 0x60d3521a0d3dd9eb'u64]
    M = [SecretWord 0xffffffff'u64, SecretWord 0xffffffffffffffff'u64, SecretWord 0xffffffff00000000'u64, SecretWord 0x0000000000000001'u64]
    s = "0x0000000081cd43d812e83385c1967515cd95ff7f2f53c61f9626aebd299b9ca4"

    a.reverse()
    b.reverse()
    M.reverse()

    debugecho "--------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", M.toHex()
    addmod_asm(a, b, M)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

  main()
