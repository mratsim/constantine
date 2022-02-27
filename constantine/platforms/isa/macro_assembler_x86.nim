# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/[macros, strutils, sets, hashes, algorithm]

# A compile-time inline assembler

# No exceptions allowed
{.push raises: [].}

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
    AnyRegImm      = "ri"

    PointerInReg   = "r" # Store an array pointer
    ElemsInReg     = "r" # Store each individual array element in reg

    # Specific registers
    RCX            = "c"
    RDX            = "d"
    R8             = "r8"

    RAX            = "a"

    # Flags
    CarryFlag      = "@ccc"

    # Clobbered register
    ClobberedReg

when sizeof(int) == 8 and not defined(Constantine32):
  type
    Register* = enum
      rbx
      rdx
      r8
      rax
      xmm0
else:
  type
    Register* = enum
      rbx  = "ebx"
      rdx  = "edx"
      r8   = "r8d"
      rax  = "eax"
      xmm0

type
  Constraint* = enum
    ## GCC extended assembly modifier
    Input               = ""
    Input_Commutative   = "%"
    Output_Overwrite    = "="
    Output_EarlyClobber = "=&"
    InputOutput         = "+"
    InputOutput_EnsureClobber = "+&" # For register InputOutput, clang needs "+&" bug?
    ClobberedRegister

  OpKind = enum
    kRegister
    kFromArray
    kArrayAddr

  Operand* = object
    desc*: OperandDesc
    case kind: OpKind
    of kRegister:
      discard
    of kFromArray:
      offset: int
    of kArrayAddr:
      buf: seq[Operand]

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
    isStackClobbered: bool
    regClobbers: set[Register]

  Stack* = object

const SpecificRegisters = {RCX, RDX, R8, RAX}
const OutputReg = {Output_EarlyClobber, InputOutput, InputOutput_EnsureClobber, Output_Overwrite, ClobberedRegister}

func hash(od: OperandDesc): Hash =
  {.noSideEffect.}:
    try: # Why does this raise a generic exception?
      hash($od.nimSymbol)
    except:
      raise newException(Defect, "Broke Nim")

# TODO: remove the need of OperandArray

func len*(opArray: OperandArray): int =
  opArray.buf.len

func len*(opArray: Operand): int =
  opArray.buf.len

func rotateLeft*(opArray: var OperandArray) =
  opArray.buf.rotateLeft(1)

func rotateRight*(opArray: var OperandArray) =
  opArray.buf.rotateLeft(-1)

proc `[]`*(opArray: OperandArray, index: int): Operand =
  opArray.buf[index]

func `[]`*(opArray: var OperandArray, index: int): var Operand =
  opArray.buf[index]

func `[]`*(arrayAddr: Operand, index: int): Operand =
  arrayAddr.buf[index]

func `[]`*(arrayAddr: var Operand, index: int): var Operand =
  arrayAddr.buf[index]

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
    let symStr = try: # Why does this raise a generic exception?
      $nimSymbol
    except:
      raise newException(Defect, "Broke Nim!")

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
        kind: kFromArray,
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
        kind: kRegister
      )

func asArrayAddr*(op: Operand, len: int): Operand =
  ## Use the value stored in an operand as an array address
  doAssert op.desc.rm in {Reg, PointerInReg, ElemsInReg}+SpecificRegisters
  result = Operand(
    kind: kArrayAddr,
    desc: nil,
    buf: newSeq[Operand](len)
  )
  for i in 0 ..< len:
    result.buf[i] = Operand(
      desc: op.desc,
      kind: kFromArray,
      offset: i
    )

func asArrayAddr*(op: Register, len: int): Operand =
  ## Use the value stored in an operand as an array address
  result = Operand(
    kind: kArrayAddr,
    desc: nil,
    buf: newSeq[Operand](len)
  )
  for i in 0 ..< len:
    result.buf[i] = Operand(
      desc: OperandDesc(
        asmId: $op,
        rm: ClobberedReg,
        constraint: ClobberedRegister
      ),
      kind: kFromArray,
      offset: i
    )

# Code generation
# ------------------------------------------------------------------------------------------------------------

func setToCarryFlag*(a: var Assembler_x86, carry: NimNode) =

  # We need to dereference the hidden pointer of var param
  let isHiddenDeref = carry.kind == nnkHiddenDeref
  let nimSymbol = if isHiddenDeref: carry[0]
                  else: carry
  {.noSideEffect.}:
    let symStr = try: # Why does this raise a generic exception?
      $nimSymbol
    except:
      raise newException(Defect, "Broke Nim!")

  let desc = OperandDesc(
    asmId: "",
    nimSymbol: ident(symStr),
    rm: CarryFlag,
    constraint: Output_Overwrite,
    cEmit: symStr
  )

  a.operands.incl(desc)

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
      # [a] "rbx" (`a`)
      decl = odesc.asmId & "\"" & $odesc.constraint & $odesc.rm & "\"" &
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

    if odesc.rm == PointerInReg and odesc.constraint in {Output_Overwrite, Output_EarlyClobber, InputOutput, InputOutput_EnsureClobber}:
      memClobbered = true

  var params: string
  params.add ": " & outOperands.join(", ") & '\n'
  params.add ": " & inOperands.join(", ") & '\n'

  let clobbers = [(a.isStackClobbered, "sp"),
                  (a.areFlagsClobbered, "cc"),
                  (memClobbered, "memory")]
  var clobberList = ": "
  for (clobbered, str) in clobbers:
    if clobbered:
      if clobberList.len == 2:
        clobberList.add "\"" & str & '\"'
      else:
        clobberList.add ", \"" & str & '\"'

  for reg in a.regClobbers:
    if clobberList.len == 2:
      clobberList.add "\"" & $reg & '\"'
    else:
      clobberList.add ", \"" & $reg & '\"'

  params.add clobberList

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
        "asm volatile(\n" & asmStmt & params & ");"
      )
    )
  )
  result = nnkBlockStmt.newTree(
    newEmptyNode(),
    result
  )

func getStrOffset(a: Assembler_x86, op: Operand): string =
  if op.kind != kFromArray:
    if op.kind == kArrayAddr:
      # We are operating on an array pointer
      # instead of array elements
      if op.buf[0].desc.constraint == ClobberedRegister:
        return "%%" & op.buf[0].desc.asmId
      else:
        return "%" & op.buf[0].desc.asmId
    else:
      return "%" & op.desc.asmId

  # Beware GCC / Clang differences with array offsets
  # https://lists.llvm.org/pipermail/llvm-dev/2017-August/116202.html
  # - 8+%rax works with GCC
  # - 8%rax works with Clang
  # - 8(%rax) works with both

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
  elif op.desc.rm == PointerInReg or
       op.desc.rm in SpecificRegisters or
       (op.desc.rm == ElemsInReg and op.kind == kFromArray):
    if op.offset == 0:
      return "(%" & op.desc.asmId & ')'
    # GCC & Clang seemed to disagree on pointer indexing
    # in the past and required different codegen
    # if defined(gcc):
    #   return $(op.offset * a.wordSize) & "+(%" & op.desc.asmId & ')'
    return $(op.offset * a.wordSize) & "(%" & op.desc.asmId & ')'
  elif op.desc.rm == ClobberedReg: # Array in clobbered register
    if op.offset == 0:
      return "(%%" & op.desc.asmId & ')'
    return $(op.offset * a.wordSize) & "(%%" & op.desc.asmId & ')'
  else:
    error "Unsupported: " & $op.desc.rm.ord

func codeFragment(a: var Assembler_x86, instr: string, op: Operand) =
  # Generate a code fragment
  let off = a.getStrOffset(op)

  if a.wordBitWidth == 64:
    a.code &= instr & "q " & off & '\n'
  elif a.wordBitWidth == 32:
    a.code &= instr & "l " & off & '\n'
  else:
    error "Unsupported bitwidth: " & $a.wordBitWidth

  if op.desc.constraint != ClobberedRegister:
    a.operands.incl op.desc

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

  if op0.desc.constraint != ClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != ClobberedRegister:
    a.operands.incl op1.desc

func codeFragment(a: var Assembler_x86, instr: string, op: Operand, reg: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off = a.getStrOffset(op)

  if a.wordBitWidth == 64:
    a.code &= instr & "q " & off & ", %%" & $reg & '\n'
  else:
    a.code &= instr & "l " & off & ", %%" & $reg & '\n'

  # op.desc can be nil for renamed registers (using asArrayAddr)
  if not op.desc.isNil and op.desc.constraint != ClobberedRegister:
    a.operands.incl op.desc
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, reg: Register, op: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off = a.getStrOffset(op)

  if a.wordBitWidth == 64:
    a.code &= instr & "q %%" & $reg & ", " & off & '\n'
  else:
    a.code &= instr & "l %%" & $reg & ", " & off & '\n'

  if op.desc.constraint != ClobberedRegister:
    a.operands.incl op.desc
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, reg0, reg1: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q %%" & $reg0 & ", %%" & $reg1 & '\n'
  else:
    a.code &= instr & "l %%" & $reg0 & ", %%" & $reg1 & '\n'

  a.regClobbers.incl reg0
  a.regClobbers.incl reg1

func codeFragment(a: var Assembler_x86, instr: string, imm: int, op: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off = a.getStrOffset(op)

  if a.wordBitWidth == 64:
    a.code &= instr & "q $" & $imm & ", " & off & '\n'
  else:
    a.code &= instr & "l $" & $imm & ", " & off & '\n'

  if op.desc.constraint != ClobberedRegister:
    a.operands.incl op.desc

func codeFragment(a: var Assembler_x86, instr: string, reg: Register, op: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q %%" & $reg & ", %" & $op.asmId & '\n'
  else:
    a.code &= instr & "l %%" & $reg & ", %" & $op.asmId & '\n'
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, op: OperandReuse, reg: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q %" & $op.asmId & ", %%" & $reg & '\n'
  else:
    a.code &= instr & "l %" & $op.asmId & ", %%" & $reg & '\n'
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, imm: int, reg: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  if a.wordBitWidth == 64:
    a.code &= instr & "q $" & $imm & ", %%" & $reg & '\n'
  else:
    a.code &= instr & "l $" & $imm & ", %%" & $reg & '\n'
  a.regClobbers.incl reg

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

func codeFragment(a: var Assembler_x86, instr: string, op0: OperandReuse, op1: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off1 = a.getStrOffset(op1)

  if a.wordBitWidth == 64:
    a.code &= instr & "q %" & $op0.asmId & ", " & off1 & '\n'
  else:
    a.code &= instr & "l %" & $op0.asmId & ", " & off1 & '\n'

  if op1.desc.constraint != ClobberedRegister:
    a.operands.incl op1.desc

func codeFragment(a: var Assembler_x86, instr: string, op0: Operand, op1: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off0 = a.getStrOffset(op0)

  if a.wordBitWidth == 64:
    a.code &= instr & "q " & off0 & ", %" & $op1.asmId & '\n'
  else:
    a.code &= instr & "l " & off0 & ", %" & $op1.asmId & '\n'

  if op0.desc.constraint != ClobberedRegister:
    a.operands.incl op0.desc

func reuseRegister*(reg: OperandArray): OperandReuse =
  # TODO: disable the reg input
  doAssert reg.buf[0].desc.constraint == InputOutput
  result.asmId = reg.buf[0].desc.asmId

func comment*(a: var Assembler_x86, comment: string) =
  # Add a comment
  a.code &= "# " & comment & '\n'

func repackRegisters*(regArr: OperandArray, regs: varargs[Operand]): OperandArray =
  ## Extend an array of registers with extra registers
  result.buf = regArr.buf
  result.buf.add regs
  result.nimSymbol = nil

# Instructions
# ------------------------------------------------------------------------------------------------------------

func add*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst + src
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("add", src, dst)
  a.areFlagsClobbered = true

func add*(a: var Assembler_x86, dst, src: Register) =
  ## Does: dst <- dst + src
  a.codeFragment("add", src, dst)
  a.areFlagsClobbered = true

func add*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- dst + src
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("add", src, dst)
  a.areFlagsClobbered = true

func add*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Does: dst <- dst + src
  a.codeFragment("add", src, dst)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst + src + carry
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("adc", src, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm in {Mem, MemOffsettable, AnyRegOrMem}:
    {.warning: "Using addcarry with a memory destination, this incurs significant performance penalties.".}

func adc*(a: var Assembler_x86, dst, src: Register) =
  ## Does: dst <- dst + src + carry
  a.codeFragment("adc", src, dst)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does: dst <- dst + imm + borrow
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("adc", imm, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm in {Mem, MemOffsettable, AnyRegOrMem}:
    {.warning: "Using addcarry with a memory destination, this incurs significant performance penalties.".}

func adc*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- dst + src
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("adc", src, dst)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst: Register, imm: int) =
  ## Does: dst <- dst + src
  a.codeFragment("adc", imm, dst)
  a.areFlagsClobbered = true

func sub*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst - src
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("sub", src, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst - src - borrow
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("sbb", src, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm != Reg:
    {.warning: "Using subborrow with a memory destination, this incurs significant performance penalties.".}

func sbb*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does: dst <- dst - imm - borrow
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("sbb", imm, dst)
  a.areFlagsClobbered = true

  if dst.desc.rm != Reg:
    {.warning: "Using subborrow with a memory destination, this incurs significant performance penalties.".}

func sbb*(a: var Assembler_x86, dst: Register, imm: int) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", imm, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: Register) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", src, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst: OperandReuse, imm: int) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", imm, dst)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: OperandReuse) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", src, dst)
  a.areFlagsClobbered = true

func sar*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does Arithmetic Right Shift (i.e. with sign extension)
  doAssert dst.desc.constraint in OutputReg
  a.codeFragment("sar", imm, dst)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst: OperandReuse, imm: int) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", imm, dst)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst, src: Operand) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", src, dst)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", src, dst)
  a.areFlagsClobbered = true

func test*(a: var Assembler_x86, x, y: Operand) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("test", x, y)
  a.areFlagsClobbered = true

func test*(a: var Assembler_x86, x, y: OperandReuse) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("test", x, y)
  a.areFlagsClobbered = true

func `or`*(a: var Assembler_x86, dst, src: Operand) =
  ## Compute the bitwise or of x and y and
  ## reset all flags
  a.codeFragment("or", src, dst)
  a.areFlagsClobbered = true

func `or`*(a: var Assembler_x86, dst: OperandReuse, src: Operand) =
  ## Compute the bitwise or of x and y and
  ## reset all flags
  a.codeFragment("or", src, dst)
  a.areFlagsClobbered = true

func `xor`*(a: var Assembler_x86, dst, src: Operand) =
  ## Compute the bitwise xor of x and y and
  ## reset all flags
  a.codeFragment("xor", src, dst)
  a.areFlagsClobbered = true

func `xor`*(a: var Assembler_x86, dst, src: Register) =
  ## Compute the bitwise xor of x and y and
  ## reset all flags
  a.codeFragment("xor", src, dst)
  a.areFlagsClobbered = true

func mov*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("mov", src, dst)
  # No clobber

func mov*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Does: dst <- src
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("mov", src, dst)
  # No clobber

func mov*(a: var Assembler_x86, dst: OperandReuse, src: Operand) =
  ## Does: dst <- src
  # doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("mov", src, dst)
  # No clobber

func mov*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does: dst <- imm
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("mov", imm, dst)
  # No clobber

func mov*(a: var Assembler_x86, dst: Register, imm: int) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", imm, dst)

func mov*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", src, dst)

func mov*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", src, dst)

func mov*(a: var Assembler_x86, dst: Register, src: OperandReuse) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", src, dst)

func mov*(a: var Assembler_x86, dst: OperandReuse, src: Register) =
  ## Does: dst <- imm
  # doAssert dst.desc.constraint in OutputReg, $dst.repr
  a.codeFragment("mov", src, dst)

func cmovc*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the carry flag is set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovc", src, dst)
  # No clobber

func cmovnc*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the carry flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovnc", src, dst)
  # No clobber

func cmovz*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovz", src, dst)
  # No clobber

func cmovz*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovz", src, dst)
  # No clobber

func cmovnz*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovnz", src, dst)
  # No clobber

func cmovnz*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovnz", src, dst)
  # No clobber

func cmovs*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the sign flag
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("cmovs", src, dst)
  # No clobber

func mul*(a: var Assembler_x86, dHi, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rax, "MUL requires the RAX register"
  doAssert dHi == rdx,  "MUL requires the RDX register"
  doAssert dLo == rax,   "MUL requires the RAX register"
  a.regClobbers.incl rax
  a.regClobbers.incl rdx

  a.codeFragment("mul", src0)

func imul*(a: var Assembler_x86, dst, src: Operand) =
  ## Does dst <- dst * src, keeping only the low half
  doAssert dst.desc.rm in {Reg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $dst.repr
  doAssert dst.desc.constraint in OutputReg, $dst.repr

  a.codeFragment("imul", src, dst)

func imul*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Does dst <- dst * src, keeping only the low half
  a.codeFragment("imul", src, dst)

func mulx*(a: var Assembler_x86, dHi, dLo, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  doAssert dHi.desc.rm in {Reg, ElemsInReg}+SpecificRegisters,
    "The destination operand must be a register " & $dHi.repr
  doAssert dLo.desc.rm in {Reg, ElemsInReg}+SpecificRegisters,
    "The destination operand must be a register " & $dLo.repr
  doAssert dHi.desc.constraint in OutputReg
  doAssert dLo.desc.constraint in OutputReg

  let off0 = a.getStrOffset(src0)

  # Annoying AT&T syntax
  if a.wordBitWidth == 64:
    a.code &= "mulxq " & off0 & ", %" & $dLo.desc.asmId & ", %" & $dHi.desc.asmId & '\n'
  else:
    a.code &= "mulxl " & off0 & ", %" & $dLo.desc.asmId & ", %" & $dHi.desc.asmId & '\n'

  a.operands.incl src0.desc

func mulx*(a: var Assembler_x86, dHi: Operand, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  doAssert dHi.desc.rm in {Reg, ElemsInReg}+SpecificRegisters,
    "The destination operand must be a register " & $dHi.repr
  doAssert dHi.desc.constraint in OutputReg

  let off0 = a.getStrOffset(src0)

  # Annoying AT&T syntax
  if a.wordBitWidth == 64:
    a.code &= "mulxq " & off0 & ", %%" & $dLo & ", %" & $dHi.desc.asmId & '\n'
  else:
    a.code &= "mulxl " & off0 & ", %%" & $dLo & ", %" & $dHi.desc.asmId & '\n'

  a.operands.incl src0.desc
  a.regClobbers.incl dLo

func mulx*(a: var Assembler_x86, dHi: OperandReuse, dLo, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  doAssert dLo.desc.rm in {Reg, ElemsInReg}+SpecificRegisters,
    "The destination operand must be a register " & $dLo.repr
  doAssert dLo.desc.constraint in OutputReg

  let off0 = a.getStrOffset(src0)

  # Annoying AT&T syntax
  if a.wordBitWidth == 64:
    a.code &= "mulxq " & off0 & ", %" & $dLo.desc.asmId & ", %" & $dHi.asmId & '\n'
  else:
    a.code &= "mulxl " & off0 & ", %" & $dLo.desc.asmId & ", %" & $dHi.asmId & '\n'

  a.operands.incl src0.desc

func mulx*(a: var Assembler_x86, dHi: OperandReuse, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  let off0 = a.getStrOffset(src0)

  # Annoying AT&T syntax
  if a.wordBitWidth == 64:
    a.code &= "mulxq " & off0 & ", %%" & $dLo & ", %" & $dHi.asmId & '\n'
  else:
    a.code &= "mulxl " & off0 & ", %%" & $dLo & ", %" & $dHi.asmId & '\n'

  a.operands.incl src0.desc
  a.regClobbers.incl dLo

func mulx*(a: var Assembler_x86, dHi, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  let off0 = a.getStrOffset(src0)

  # Annoying AT&T syntax
  if a.wordBitWidth == 64:
    a.code &= "mulxq " & off0 & ", %%" & $dLo & ", %%" & $dHi & '\n'
  else:
    a.code &= "mulxl " & off0 & ", %%" & $dLo & ", %%" & $dHi & '\n'

  a.operands.incl src0.desc
  a.regClobbers.incl dHi
  a.regClobbers.incl dLo

func adcx*(a: var Assembler_x86, dst: Operand|OperandReuse|Register, src: Operand|OperandReuse|Register) =
  ## Does: dst <- dst + src + carry
  ## and only sets the carry flag
  when dst is Operand:
    doAssert dst.desc.constraint in OutputReg, $dst.repr
    doAssert dst.desc.rm in {Reg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $dst.repr
  a.codeFragment("adcx", src, dst)
  a.areFlagsClobbered = true

func adox*(a: var Assembler_x86, dst: Operand|OperandReuse|Register, src: Operand|OperandReuse|Register) =
  ## Does: dst <- dst + src + overflow
  ## and only sets the overflow flag
  when dst is Operand:
    doAssert dst.desc.constraint in OutputReg, $dst.repr
    doAssert dst.desc.rm in {Reg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $dst.repr
  a.codeFragment("adox", src, dst)
  a.areFlagsClobbered = true

func push*(a: var Assembler_x86, _: type Stack, reg: Operand) =
  ## Push the content of register on the stack
  doAssert reg.desc.rm in {Reg, PointerInReg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $reg.repr
  a.codeFragment("push", reg)
  a.isStackClobbered = true

func pop*(a: var Assembler_x86, _: type Stack, reg: Operand) =
  ## Pop the content of register on the stack
  doAssert reg.desc.rm in {Reg, PointerInReg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $reg.repr
  a.codeFragment("pop", reg)
  a.isStackClobbered = true
