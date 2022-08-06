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
#        Assembly implementation of finite fields
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseASM_X86_32

{.localPassC:"-fomit-frame-pointer".} # Needed so that the compiler finds enough registers

proc finalSubNoCarryImpl*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       a, M, scratch: OperandArray
     ) =
  ## Reduce `a` into `r` modulo `M`
  ## 
  ## r, a, scratch, scratchReg are mutated
  ## M is read-only
  let N = M.len
  ctx.comment "Final substraction (no carry)"
  for i in 0 ..< N:
    ctx.mov scratch[i], a[i]
    if i == 0:
      ctx.sub scratch[i], M[i]
    else:
      ctx.sbb scratch[i], M[i]

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc a[i], scratch[i]
    ctx.mov r[i], a[i]

proc finalSubMayCarryImpl*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       a, M, scratch: OperandArray,
       scratchReg: Operand or Register or OperandReuse
     ) =
  ## Reduce `a` into `r` modulo `M`
  ## To be used when the final substraction can
  ## also depend on the carry flag
  ## 
  ## r, a, scratch, scratchReg are mutated
  ## M is read-only

  ctx.comment "Final substraction (may carry)"

  # Mask: scratchReg contains 0xFFFF or 0x0000
  ctx.sbb scratchReg, scratchReg

  # Now substract the modulus to test a < p
  let N = M.len
  for i in 0 ..< N:
    ctx.mov scratch[i], a[i]
    if i == 0:
      ctx.sub scratch[i], M[i]
    else:
      ctx.sbb scratch[i], M[i]

  # If it overflows here, it means that it was
  # smaller than the modulus and we don't need `scratch`
  ctx.sbb scratchReg, 0

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc a[i], scratch[i]
    ctx.mov r[i], a[i]

macro finalSub_gen*[N: static int](
       r_PIR: var array[N, SecretWord],
       a_EIR, M_PIR: array[N, SecretWord],
       scratch_EIR: var array[N, SecretWord],
       mayCarry: static bool): untyped =
  ## Returns:
  ##   a-M if a > M
  ##   a otherwise
  ## 
  ## - r_PIR is a pointer to the result array, mutated,
  ## - a_EIR is an array of registers, mutated,
  ## - M_PIR is a pointer to an array, read-only,
  ## - scratch_EIR is an array of registers, mutated
  ## - mayCarry is set to true when the carry flag also needs to be read
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = init(OperandArray, nimSymbol = r_PIR, N, PointerInReg, InputOutput)
    # We reuse the reg used for b for overflow detection
    a = init(OperandArray, nimSymbol = a_EIR, N, ElemsInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_PIR, N, PointerInReg, Input)
    t = init(OperandArray, nimSymbol = scratch_EIR, N, ElemsInReg, Output_EarlyClobber)

  if mayCarry:
    ctx.finalSubMayCarryImpl(
      r, a, M, t, rax
    )
  else:
    ctx.finalSubNoCarryImpl(
      r, a, M, t
    )

  result.add ctx.generate()

# Field addition
# ------------------------------------------------------------

macro addmod_gen[N: static int](R: var Limbs[N], A, B, m: Limbs[N], spareBits: static int): untyped =
  ## Generate an optimized modular addition kernel
  # Register pressure note:
  #   We could generate a kernel per modulus m by hardcoding it as immediate
  #   however this requires
  #     - duplicating the kernel and also
  #     - 64-bit immediate encoding is quite large

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = init(OperandArray, nimSymbol = R, N, PointerInReg, InputOutput)
    # We reuse the reg used for b for overflow detection
    b = init(OperandArray, nimSymbol = B, N, PointerInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = m, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    u = init(OperandArray, nimSymbol = ident"u", N, ElemsInReg, InputOutput)
    v = init(OperandArray, nimSymbol = ident"v", N, ElemsInReg, Output_EarlyClobber)

  let usym = u.nimSymbol
  let vsym = v.nimSymbol
  result.add quote do:
    var `usym`{.noinit.}, `vsym` {.noInit, used.}: typeof(`A`)
    staticFor i, 0, `N`:
      `usym`[i] = `A`[i]

  # Addition
  for i in 0 ..< N:
    if i == 0:
      ctx.add u[0], b[0]
    else:
      ctx.adc u[i], b[i]
    # Interleaved copy in a second buffer as well
    ctx.mov v[i], u[i]

  if spareBits >= 1:
    ctx.finalSubNoCarryImpl(r, u, M, v)
  else:
    ctx.finalSubMayCarryImpl(
      r, u, M, v, b.reuseRegister()
    )

  result.add ctx.generate()

func addmod_asm*(r: var Limbs, a, b, m: Limbs, spareBits: static int) =
  ## Constant-time modular addition
  addmod_gen(r, a, b, m, spareBits)

# Field substraction
# ------------------------------------------------------------

macro submod_gen[N: static int](R: var Limbs[N], A, B, m: Limbs[N]): untyped =
  ## Generate an optimized modular addition kernel
  # Register pressure note:
  #   We could generate a kernel per modulus m by hardocing it as immediate
  #   however this requires
  #     - duplicating the kernel and also
  #     - 64-bit immediate encoding is quite large

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = init(OperandArray, nimSymbol = R, N, PointerInReg, InputOutput)
    # We reuse the reg used for b for overflow detection
    b = init(OperandArray, nimSymbol = B, N, PointerInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = m, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    u = init(OperandArray, nimSymbol = ident"U", N, ElemsInReg, InputOutput)
    v = init(OperandArray, nimSymbol = ident"V", N, ElemsInReg, Output_EarlyClobber)

  let usym = u.nimSymbol
  let vsym = v.nimSymbol
  result.add quote do:
    var `usym`{.noinit.}, `vsym` {.noInit, used.}: typeof(`A`)
    staticFor i, 0, `N`:
      `usym`[i] = `A`[i]

  # Substraction
  for i in 0 ..< N:
    if i == 0:
      ctx.sub u[0], b[0]
    else:
      ctx.sbb u[i], b[i]
    # Interleaved copy the modulus to hide SBB latencies
    ctx.mov v[i], M[i]

  # Mask: underflowed contains 0xFFFF or 0x0000
  let underflowed = b.reuseRegister()
  ctx.sbb underflowed, underflowed

  # Now mask the adder, with 0 or the modulus limbs
  for i in 0 ..< N:
    ctx.`and` v[i], underflowed

  # Add the masked modulus
  for i in 0 ..< N:
    if i == 0:
      ctx.add u[0], v[0]
    else:
      ctx.adc u[i], v[i]
    ctx.mov r[i], u[i]

  result.add ctx.generate

func submod_asm*(r: var Limbs, a, b, M: Limbs) =
  ## Constant-time modular substraction
  ## Warning, does not handle aliasing of a and b
  submod_gen(r, a, b, M)

# Field negation
# ------------------------------------------------------------

macro negmod_gen[N: static int](R: var Limbs[N], A, m: Limbs[N]): untyped =
  ## Generate an optimized modular negation kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    a = init(OperandArray, nimSymbol = A, N, PointerInReg, Input)
    r = init(OperandArray, nimSymbol = R, N, PointerInReg, InputOutput)
    u = init(OperandArray, nimSymbol = ident"U", N, ElemsInReg, Output_EarlyClobber)
    # We could force m as immediate by specializing per moduli
    # We reuse the reg used for m for overflow detection
    M = init(OperandArray, nimSymbol = m, N, PointerInReg, InputOutput)

  # Substraction m - a
  for i in 0 ..< N:
    ctx.mov u[i], M[i]
    if i == 0:
      ctx.sub u[0], a[0]
    else:
      ctx.sbb u[i], a[i]

  # Deal with a == 0
  let isZero = M.reuseRegister()
  ctx.mov isZero, a[0]
  for i in 1 ..< N:
    ctx.`or` isZero, a[i]

  # Zero result if a == 0
  for i in 0 ..< N:
    ctx.cmovz u[i], isZero
    ctx.mov r[i], u[i]

  let usym = u.nimSymbol
  result.add quote do:
    var `usym`{.noinit, used.}: typeof(`A`)
  result.add ctx.generate

func negmod_asm*(r: var Limbs, a, m: Limbs) =
  ## Constant-time modular negation
  negmod_gen(r, a, m)

# Sanity checks
# ----------------------------------------------------------

when isMainModule:
  import ../../config/type_bigint, algorithm, strutils

  proc mainAdd() =
    var a = [SecretWord 0xE3DF60E8F6D0AF9A'u64, SecretWord 0x7B2665C2258A7625'u64, SecretWord 0x68FC9A1D0977C8E0'u64, SecretWord 0xF3DC61ED7DE76883'u64]
    var b = [SecretWord 0x78E9C2EF58BB6B78'u64, SecretWord 0x547F65BD19014254'u64, SecretWord 0x556A115819EAD4B5'u64, SecretWord 0x8CA844A546935DC3'u64]
    var m = [SecretWord 0xFFFFFFFF00000001'u64, SecretWord 0x0000000000000000'u64, SecretWord 0x00000000FFFFFFFF'u64, SecretWord 0xFFFFFFFFFFFFFFFF'u64]
    var s = "0x5cc923d94f8c1b11cfa5cb7f3e8bb879be66ab7423629d968084a692c47ac647"

    a.reverse()
    b.reverse()
    m.reverse()

    debugecho "--------------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", m.toHex()
    addmod_asm(a, a, b, m, spareBits = 0)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

    a = [SecretWord 0x00935a991ca215a6'u64, SecretWord 0x5fbdac6294679337'u64, SecretWord 0x1e41793877b80f12'u64, SecretWord 0x5724cd93cb32932d'u64]
    b = [SecretWord 0x19dd4ecfda64ef80'u64, SecretWord 0x92deeb1532169c3d'u64, SecretWord 0x69ce4ee28421cd30'u64, SecretWord 0x4d90ab5a40295321'u64]
    m = [SecretWord 0x2523648240000001'u64, SecretWord 0xba344d8000000008'u64, SecretWord 0x6121000000000013'u64, SecretWord 0xa700000000000013'u64]
    s = "0x1a70a968f7070526f29c9777c67e2f74880fc81afbd9dc42a4b578ee0b5be64e"

    a.reverse()
    b.reverse()
    m.reverse()

    debugecho "--------------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", m.toHex()
    addmod_asm(a, a, b, m, spareBits = 0)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

    a = [SecretWord 0x1c7d810f37fc6e0b'u64, SecretWord 0xb91aba4ce339cea3'u64, SecretWord 0xd9f5571ccc4dfd1a'u64, SecretWord 0xf5906ee9df91f554'u64]
    b = [SecretWord 0x18394ffe94874c9f'u64, SecretWord 0x6e8a8ad032fc5f15'u64, SecretWord 0x7533a2b46b7e9530'u64, SecretWord 0x2849996b4bb61b48'u64]
    m = [SecretWord 0x2523648240000001'u64, SecretWord 0xba344d8000000008'u64, SecretWord 0x6121000000000013'u64, SecretWord 0xa700000000000013'u64]
    s = "0x0f936c8b8c83baa96d70f79d16362db0ee07f9d137cc923776da08552b481089"

    a.reverse()
    b.reverse()
    m.reverse()

    debugecho "--------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", m.toHex()
    addmod_asm(a, a, b, m, spareBits = 0)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

    a = [SecretWord 0xe9d55643'u64, SecretWord 0x580ec4cc3f91cef3'u64, SecretWord 0x11ecbb7d35b36449'u64, SecretWord 0x35535ca31c5dc2ba'u64]
    b = [SecretWord 0x97f7ed94'u64, SecretWord 0xbad96eb98204a622'u64, SecretWord 0xbba94400f9a061d6'u64, SecretWord 0x60d3521a0d3dd9eb'u64]
    m = [SecretWord 0xffffffff'u64, SecretWord 0xffffffffffffffff'u64, SecretWord 0xffffffff00000000'u64, SecretWord 0x0000000000000001'u64]
    s = "0x0000000081cd43d812e83385c1967515cd95ff7f2f53c61f9626aebd299b9ca4"

    a.reverse()
    b.reverse()
    m.reverse()

    debugecho "--------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", m.toHex()
    addmod_asm(a, a, b, m, spareBits = 0)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

  mainAdd()

  proc mainSub() =
    var a = [SecretWord 0xf9c32e89b80b17bd'u64, SecretWord 0xdbd3069d4ca0e1c3'u64, SecretWord 0x980d4c70d39d5e17'u64, SecretWord 0xd9f0252845f18c3a'u64]
    var b = [SecretWord 0x215075604bfd64de'u64, SecretWord 0x36dc488149fc5d3e'u64, SecretWord 0x91fff665385d20fd'u64, SecretWord 0xe980a5a203b43179'u64]
    var m = [SecretWord 0xFFFFFFFFFFFFFFFF'u64, SecretWord 0xFFFFFFFFFFFFFFFF'u64, SecretWord 0xFFFFFFFFFFFFFFFF'u64, SecretWord 0xFFFFFFFEFFFFFC2F'u64]
    var s = "0xd872b9296c0db2dfa4f6be1c02a48485060d560b9b403d19f06f7f86423d5ac1"

    a.reverse()
    b.reverse()
    m.reverse()

    debugecho "--------------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", m.toHex()
    submod_asm(a, a, b, m, spareBits = 0)
    debugecho "after:"
    debugecho "  a: ", a.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", a.toHex().tolower == s

  mainSub()

  proc mainSubOutplace() =
    var a = [SecretWord 0xf9c32e89b80b17bd'u64, SecretWord 0xdbd3069d4ca0e1c3'u64, SecretWord 0x980d4c70d39d5e17'u64, SecretWord 0xd9f0252845f18c3a'u64]
    var b = [SecretWord 0x215075604bfd64de'u64, SecretWord 0x36dc488149fc5d3e'u64, SecretWord 0x91fff665385d20fd'u64, SecretWord 0xe980a5a203b43179'u64]
    var m = [SecretWord 0xFFFFFFFFFFFFFFFF'u64, SecretWord 0xFFFFFFFFFFFFFFFF'u64, SecretWord 0xFFFFFFFFFFFFFFFF'u64, SecretWord 0xFFFFFFFEFFFFFC2F'u64]
    var s = "0xd872b9296c0db2dfa4f6be1c02a48485060d560b9b403d19f06f7f86423d5ac1"

    a.reverse()
    b.reverse()
    m.reverse()

    var r: typeof(a)

    debugecho "--------------------------------"
    debugecho "before:"
    debugecho "  a: ", a.toHex()
    debugecho "  b: ", b.toHex()
    debugecho "  m: ", m.toHex()
    submod_asm(r, a, b, m, spareBits = 0)
    debugecho "after:"
    debugecho "  r: ", r.toHex().tolower
    debugecho "  s: ", s
    debugecho " ok: ", r.toHex().tolower == s

  mainSubOutplace()
