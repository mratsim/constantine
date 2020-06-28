# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import macros, strutils, sets, hashes

# A compile-time inline assembler

type
  RM* = enum
    ## Register or Memory operand
    # https://gcc.gnu.org/onlinedocs/gcc/Simple-Constraints.html
    Reg            = "r"
    Mem            = "m"
    AnyRegOrMem    = "rm" # use "r, m" instead?
    Imm            = "i"
    MemOffsettable = "o"
    AnyRegMemImm   = "g"
    AnyMemOffImm   = "oi"

    PointerInReg   = "r" # Store an array pointer
    ElemsInReg     = "r" # Store each individual array element in reg

    # Specific registers
    RCX            = "rcx"
    RDX            = "rdx"
    R8             = "r8"

  Register* = enum
    rbx, rdx, r8

  Constraint* = enum
    ## GCC extended assembly modifier
    Input               = ""
    Input_Commutative   = "%"
    Input_EarlyClobber  = "&"
    Output_Overwrite    = "="
    Output_EarlyClobber = "=&"
    InputOutput         = "+"

  Operand* = object
    desc*: OperandDesc
    case fromArray: bool
    of true:
      offset: int
    of false:
      discard

  OperandDesc* = ref object
    asmId*: string          # [a] - ASM id
    nimSymbol*: NimNode     # a   - Nim nimSymbol
    rm*: RM
    constraint*: Constraint
    cEmit*: string          # C emit for example a->limbs

  OperandArray* = object
    nimSymbol*: NimNode
    buf: seq[Operand]

  OperandReuse* = object
    # Allow reusing a register
    asmId*: string

  Assembler_x86* = object
    code: string
    operands: HashSet[OperandDesc]
    wordBitWidth*: int
    wordSize: int
    areFlagsClobbered: bool

const SpecificRegisters = {RCX, RDX, R8}

func hash(od: OperandDesc): Hash =
  {.noSideEffect.}:
    hash($od.nimSymbol)

func `[]`*(opArray: OperandArray, index: int): Operand =
  opArray.buf[index]

func `[]`*(opArray: var OperandArray, index: int): var Operand =
  opArray.buf[index]

func init*(T: type Assembler_x86, Word: typedesc[SomeUnsignedInt]): Assembler_x86 =
  result.wordSize = sizeof(Word)
  result.wordBitWidth = result.wordSize * 8

func init*(T: type OperandArray, nimSymbol: NimNode, len: int, rm: RM, constraint: Constraint): OperandArray =
  doAssert rm in {
    MemOffsettable,
    AnyMemOffImm,
    PointerInReg,
    ElemsInReg
  } or rm in SpecificRegisters

  result.buf.setLen(len)

  # We need to dereference the hidden pointer of var param
  let isHiddenDeref = nimSymbol.kind == nnkHiddenDeref
  let nimSymbol = if isHiddenDeref: nimSymbol[0]
                  else: nimSymbol
  {.noSideEffect.}:
    let symStr = $nimSymbol

  result.nimSymbol = nimSymbol

  if rm in {PointerInReg, MemOffsettable, AnyMemOffImm} or
     rm in SpecificRegisters:
    let desc = OperandDesc(
                  asmId: "[" & symStr & "]",
                  nimSymbol: nimSymbol,
                  rm: rm,
                  constraint: constraint,
                  cEmit: symStr
                )
    for i in 0 ..< len:
      result.buf[i] = Operand(
        desc: desc,
        fromArray: true,
        offset: i
      )
  else:
    # We can't store an array in register so we create assign individual register
    # per array elements instead
    for i in 0 ..< len:
      result.buf[i] = Operand(
        desc: OperandDesc(
                  asmId: "[" & symStr & $i & "]",
                  nimSymbol: ident(symStr & $i),
                  rm: rm,
                  constraint: constraint,
                  cEmit: symStr & "[" & $i & "]"
              ),
        fromArray: false
      )


# Code generation
# ------------------------------------------------------------------------------------------------------------

func generate*(a: Assembler_x86): NimNode =
  ## Generate the inline assembly code from
  ## the desired instruction

  var
    outOperands: seq[string]
    inOperands: seq[string]
    memClobbered = false

  for odesc in a.operands.items():
    var decl: string
    if odesc.rm in SpecificRegisters:
      # "rbx" (`a`)
      decl = "\"" & $odesc.constraint & $odesc.rm & "\"" &
             " (`" & odesc.cEmit & "`)"
    elif odesc.rm in {Mem, AnyRegOrMem, MemOffsettable, AnyRegMemImm, AnyMemOffImm}:
      # [a] "+r" (`*a`)
      # We need to deref the pointer to memory
      decl = odesc.asmId & " \"" & $odesc.constraint & $odesc.rm & "\"" &
             " (`*" & odesc.cEmit & "`)"
    else:
      # [a] "+r" (`a[0]`)
      decl = odesc.asmId & " \"" & $odesc.constraint & $odesc.rm & "\"" &
             " (`" & odesc.cEmit & "`)"

    if odesc.constraint in {Input, Input_Commutative}:
      inOperands.add decl
    else:
      outOperands.add decl

    if odesc.rm == PointerInReg and odesc.constraint in {Output_Overwrite, Output_EarlyClobber, InputOutput}:
      memClobbered = true

  var params: string
  params.add ": " & outOperands.join(", ") & '\n'
  params.add ": " & inOperands.join(", ") & '\n'

  if a.areFlagsClobbered and memClobbered:
    params.add ": \"cc\", \"memory\""
  elif a.areFlagsClobbered:
    params.add ": \"cc\""
  elif memClobbered:
    params.add ": \"memory\""
  else:
    params.add ": "

  # GCC will optimize ASM away if there are no
  # memory operand or volatile + memory clobber
  # https://stackoverflow.com/questions/34244185/looping-over-arrays-with-inline-assembly

  # result = nnkAsmStmt.newTree(
  #   newEmptyNode(),
  #   newLit(asmStmt & params)
  # )

  var asmStmt = "\"" & a.code.replace("\n", "\\n\"\n\"")
  asmStmt.setLen(asmStmt.len - 1) # drop the last quote

  result = nnkPragma.newTree(
    nnkExprColonExpr.newTree(
      ident"emit",
      newLit(
        "asm volatile(" & asmStmt & params & ");"
      )
    )
  )

func getStrOffset(a: Assembler_x86, op: Operand): string =
  if not op.fromArray:
    return "%" & op.desc.asmId

  # Beware GCC / Clang differences with array offsets
  # https://lists.llvm.org/pipermail/llvm-dev/2017-August/116202.html

  if op.desc.rm in {Mem, AnyRegOrMem, MemOffsettable, AnyMemOffImm, AnyRegMemImm}:
    # Directly accessing memory
    if op.offset == 0:
      return "%" & op.desc.asmId
    if defined(gcc):
      return $(op.offset * a.wordSize) & "+%" & op.desc.asmId
    elif defined(clang):
      return $(op.offset * a.wordSize) & "%" & op.desc.asmId
    else:
      error "Unconfigured compiler"
  elif op.desc.rm == PointerInReg:
    if op.offset == 0:
      return "(%" & $op.desc.asmId & ')'

    if defined(gcc):
      return $(op.offset * a.wordSize) & "+(%" & $op.desc.asmId & ')'
    elif defined(clang):
      return $(op.offset * a.wordSize) & "(%" & $op.desc.asmId & ')'
    else:
      error "Unconfigured compiler"
  elif op.desc.rm in SpecificRegisters:
    if op.offset == 0:
      return "(%%" & $op.desc.rm & ')'

    if defined(gcc):
      return $(op.offset * a.wordSize) & "+(%%" & $op.desc.rm & ')'
    elif defined(clang):
      return $(op.offset * a.wordSize) & "(%%" & $op.desc.rm & ')'
    else:
      error "Unconfigured compiler"
  else:
    error "Unsupported: " & $op.desc.rm.ord

func codeFragment(a: var Assembler_x86, instr: string, op0, op1: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)

  if a.wordBitWidth == 64:
    a.code &= instr & "q " & off0 & ", " & off1 & '\n'
  elif a.wordBitWidth == 32:
    a.code &= instr & "l " & off0 & ", " & off1 & '\n'
  else:
    error "Unsupported bitwidth: " & $a.wordBitWidth

  a.operands.incl op0.desc
  a.operands.incl op1.desc

func codeFragment(a: var Assembler_x86, instr: string, imm: int, op: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q $" & $imm & ", %" & op.desc.asmId & '\n'
  else:
    a.code &= instr & "l $" & $imm & ", %" & op.desc.asmId & '\n'

  a.operands.incl op.desc

func codeFragment(a: var Assembler_x86, instr: string, imm: int, reg: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q $" & $imm & ", %%" & $reg & '\n'
  else:
    a.code &= instr & "l $" & $imm & ", %%" & $reg & '\n'

func codeFragment(a: var Assembler_x86, instr: string, reg0, reg1: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q %%" & $reg0 & ", %%" & $reg1 & '\n'
  else:
    a.code &= instr & "l %%" & $reg0 & ", %%" & $reg1 & '\n'

func codeFragment(a: var Assembler_x86, instr: string, imm: int, reg: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q $" & $imm & ", %" & $reg.asmId & '\n'
  else:
    a.code &= instr & "l $" & $imm & ", %" & $reg.asmId & '\n'

func codeFragment(a: var Assembler_x86, instr: string, reg0, reg1: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q %" & $reg0.asmId & ", %" & $reg1.asmId & '\n'
  else:
    a.code &= instr & "l %" & $reg0.asmId & ", %" & $reg1.asmId & '\n'

func reuseRegister*(reg: OperandArray): OperandReuse =
  # TODO: disable the reg input
  doAssert reg.buf[0].desc.constraint == InputOutput
  result.asmId = reg.buf[0].desc.asmId

# Instructions
# ------------------------------------------------------------------------------------------------------------

func add*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- dst + src
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("add", src, dst)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- dst + src + carry
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("adc", src, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm != Reg:
    {.warning: "Using addcarry with a memory destination, this incurs significant performance penalties.".}

func adc*(a: var Assembler_x86, dst: Operand, imm: int) =
  # Does: dst <- dst + imm + borrow
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("adc", imm, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm != Reg:
    {.warning: "Using addcarry with a memory destination, this incurs significant performance penalties.".}

func sub*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- dst - src
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("sub", src, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- dst - src - borrow
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("sbb", src, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm != Reg:
    {.warning: "Using subborrow with a memory destination, this incurs significant performance penalties.".}

func sbb*(a: var Assembler_x86, dst: Operand, imm: int) =
  # Does: dst <- dst - imm - borrow
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("sbb", imm, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm != Reg:
    {.warning: "Using subborrow with a memory destination, this incurs significant performance penalties.".}

func sbb*(a: var Assembler_x86, dst: Register, imm: int) =
  # Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", imm, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: Register) =
  # Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", src, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst: OperandReuse, imm: int) =
  # Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", imm, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: OperandReuse) =
  # Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", src, dst)
  a.areFlagsClobbered = true

func sar*(a: var Assembler_x86, loc: Operand, imm: int) =
  # Does Arithmetic Right Shift (i.e. with sign extension)
  doAssert loc.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}
  a.codeFragment("sar", imm, loc)
  a.areFlagsClobbered = true

func test*(a: var Assembler_x86, x, y: Operand) =
  # COmpute the bitwise AND of x and y and
  # set the Sign, Zero and Parity flags
  a.codeFragment("test", x, y)
  a.areFlagsClobbered = true

func mov*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- src
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}

  a.codeFragment("mov", src, dst)
  # No clobber

func cmovc*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- src if the carry flag is set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register"
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}

  a.codeFragment("cmovc", src, dst)
  # No clobber

func cmovnc*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- src if the carry flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register"
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}

  a.codeFragment("cmovnc", src, dst)
  # No clobber

func cmovz*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register"
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}

  a.codeFragment("cmovz", src, dst)
  # No clobber

func cmovnz*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register"
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}

  a.codeFragment("cmovnz", src, dst)
  # No clobber

func cmovs*(a: var Assembler_x86, dst, src: Operand) =
  # Does: dst <- src if the sign flag
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register"
  doAssert dst.desc.constraint in {Output_EarlyClobber, InputOutput, Output_Overwrite}

  a.codeFragment("cmovs", src, dst)
  # No clobber
