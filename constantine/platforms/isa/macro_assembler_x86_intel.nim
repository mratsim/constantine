# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[macros, strutils, sets, hashes, algorithm],
  ../config

# A compile-time inline assembler

# No exceptions allowed
{.push raises: [].}

type
  RM* = enum
    ## Register or Memory operand
    # https://gcc.gnu.org/onlinedocs/gcc/Simple-Constraints.html
    # We don't use the "Any" constraint like rm, g, oi or ri. It's unsure how to mix the differing semantics
    Reg            = "r"
    Mem            = "m"
    Imm            = "i"
    MemOffsettable = "o" # 'o' constraint might not work fully https://groups.google.com/g/llvm-dev/c/dfsPzWP_H1E

    PointerInReg   = "r" # Store an array pointer. ⚠️ for const arrays, this may generate incorrect code with LTO and constant folding.
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

when CTT_32:
  type
    Register* = enum
      rbx  = "ebx"
      rdx  = "edx"
      r8   = "r8d"
      rax  = "eax"
      xmm0
else:
  type
    Register* = enum
      rbx
      rdx
      r8
      rax
      xmm0

type
  Constraint* = enum
    ## GCC extended assembly modifier
    asmInput               = ""
    asmInputCommutative   = "%"
    asmOutputOverwrite    = "="
    asmOutputEarlyClobber = "=&"
    asmInputOutput         = "+"
    asmInputOutputEarlyClobber = "+&" # For register asmInputOutput, clang needs "+&" bug?
    asmClobberedRegister

  MemIndirectAccess* = enum
    memNoAccess
    memRead
    memWrite
    memReadWrite

  OpKind = enum
    kRegister
    kFromArray
    kArrayAddr
    k2dArrayAddr

  Operand* = object
    desc: OperandDesc
    case kind: OpKind
    of kRegister:
      discard
    of kFromArray:
      offset: int
    of kArrayAddr:
      buf: seq[Operand]
    of k2dArrayAddr:
      dims: array[2, int]
      buf2d: seq[Operand]

  OperandDesc = ref object
    asmId: string          # [a] - ASM id
    nimSymbol: NimNode     # a   - Nim nimSymbol
    rm: RM
    constraint: Constraint
    constraintString: string          # C emit for example a->limbs
    memClobbered: seq[(MemIndirectAccess, string)]

  OperandArray* = object
    nimSymbol: NimNode
    buf: seq[Operand]

  OperandReuse* = object
    # Allow reusing a register
    asmId: string

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
const OutputReg = {asmOutputEarlyClobber, asmInputOutput, asmInputOutputEarlyClobber, asmOutputOverwrite, asmClobberedRegister}

func toString*(nimSymbol: NimNode): string =
  # We need to dereference the hidden pointer of var param
  let isPtr = nimSymbol.kind in {nnkHiddenDeref, nnkPtrTy}
  let isAddr = nimSymbol.kind in {nnkInfix, nnkCall} and (nimSymbol[0].eqIdent"addr" or nimSymbol[0].eqIdent"unsafeAddr")

  let nimSymbol = if isPtr: nimSymbol[0]
                  elif isAddr: nimSymbol[1]
                  else: nimSymbol
  return $nimSymbol

func hash(od: OperandDesc): Hash =
  {.noSideEffect.}:
    hash(od.nimSymbol.toString())

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

func `[]`*(arrAddr: Operand, index: int): Operand =
  arrAddr.buf[index]

func `[]`*(arrAddr: var Operand, index: int): var Operand =
  arrAddr.buf[index]

func `[]`*(arr2dAddr: Operand, i, j: int): Operand =
  arr2dAddr.buf2d[i*arr2dAddr.dims[1] + j]

func `[]`*(arr2dAddr: var Operand, i, j: int): var Operand =
  arr2dAddr.buf2d[i*arr2dAddr.dims[1] + j]

func init*(T: type Assembler_x86, Word: typedesc[SomeUnsignedInt]): Assembler_x86 =
  result.wordSize = sizeof(Word)
  result.wordBitWidth = result.wordSize * 8

func setConstraintString(desc: OperandDesc, symbolString: string) =
  # [a] "rbx" (`a`) for specific registers
  # [a] "+r" (`*a_ptr`) for pointer to memory
  # [a] "+r" (`a[0]`) for array cells
  desc.constraintString = desc.asmId & "\"" & $desc.constraint & $desc.rm & "\"" &
          " (`" & symbolString & "`)"

func genMemClobber(nimSymbol: NimNode, len: int, memIndirect: MemIndirectAccess): string =
  let baseType = nimSymbol.getTypeImpl()[2].getTypeImpl()[0]
  let cBaseType = if baseType.sameType(getType(uint64)): "NU64"
                  else: "NU32"

  let symStr = nimSymbol.toString()

  case memIndirect
  of memRead:
    return "\"m\" (`*(const " & cBaseType & " (*)[" & $len & "]) " & symStr & "`)"
  of memWrite:
    return "\"=m\" (`*(" & cBaseType & " (*)[" & $len & "]) " & symStr & "`)"
  of memReadWrite:
    return "\"+m\" (`*(" & cBaseType & " (*)[" & $len & "]) " & symStr & "`)"
  else:
    doAssert false, "Indirect access kind not specified"

func asmValue*(nimSymbol: NimNode, rm: RM, constraint: Constraint): Operand =
  let symStr = $nimSymbol

  let desc = OperandDesc(
        asmId: "[" & symStr & "]",
        nimSymbol: nimSymbol,
        rm: rm,
        constraint: constraint)
  if rm in {Mem, MemOffsettable}:
    desc.setConstraintString("*&" & symStr)
  else:
    desc.setConstraintString(symStr)
  return Operand(desc: desc)

func asmArray*(nimSymbol: NimNode, len: int, rm: RM, constraint: Constraint, memIndirect = memNoAccess): OperandArray =
  doAssert rm in {MemOffsettable, PointerInReg, ElemsInReg}
  doAssert (rm == PointerInReg) xor (memIndirect == memNoAccess)

  let symStr = nimSymbol.toString()

  result.nimSymbol = nimSymbol
  result.buf.setLen(len)

  if rm == PointerInReg:
    let desc = OperandDesc(
                  asmId: "[" & symStr & "]",
                  nimSymbol: nimSymbol,
                  rm: rm,
                  constraint: constraint,
                  memClobbered: @[(memIndirect, genMemClobber(nimSymbol, len, memIndirect))])
    desc.setConstraintString(symStr)

    for i in 0 ..< len:
      result.buf[i] = Operand(
        desc: desc,
        kind: kFromArray,
        offset: i)
  elif rm == MemOffsettable:
    # For MemOffsettable
    #   Creating a base address like PointerInReg works with GCC but LLVM miscompiles
    #   so we create individual memory locations.

    # With MemOffsettable it's actually direct access, translate
    let memIndirect = if constraint == asmInput: memRead
                      elif constraint == asmOutputOverwrite: memWrite
                      elif constraint == asmInputOutput: memReadWrite
                      else: raise newException(Defect, "Invalid constraint for MemOffsettable: " & $constraint)

    # https://stackoverflow.com/questions/67993984/clang-errors-expected-register-with-inline-x86-assembly-works-with-gcc#comment120189933_67995035
    # We dereference+cast to "+m" (*(NU64 (*)[6]) myArray)
    # to ensure same treatment of "NU64* myArray" and "NU64 myArray[6]" as in C
    let desc = OperandDesc(
                  asmId: "[" & symStr & "]",
                  nimSymbol: nimSymbol,
                  rm: rm,
                  constraint: constraint,
                  constraintString: "[" & symStr & "] " & genMemClobber(nimSymbol, len, memIndirect))

    for i in 0 ..< len:
      # let desc = OperandDesc(
      #             asmId: "[" & symStr & $i & "]",
      #             nimSymbol: ident(symStr & $i),
      #             rm: rm,
      #             constraint: constraint)
      # desc.setConstraintString(symStr & "[" & $i & "]")

      result.buf[i] = Operand(
        desc: desc,
        kind: kFromArray,
        offset: i)
  else:
    # For ElemsInReg
    #   We can't store an array in register so we create assign individual register
    #   per array elements instead
    for i in 0 ..< len:
      let desc = OperandDesc(
                  asmId: "[" & symStr & $i & "]",
                  nimSymbol: ident(symStr & $i),
                  rm: rm,
                  constraint: constraint)
      desc.setConstraintString(symStr & "[" & $i & "]")
      result.buf[i] = Operand(
        desc: desc,
        kind: kRegister)

func asArrayAddr*(op: Operand, memPointer: NimNode, len: int, memIndirect: MemIndirectAccess): Operand =
  ## Use the value stored in an operand as an array address
  doAssert op.desc.rm in {Reg, PointerInReg, ElemsInReg}+SpecificRegisters
  result = Operand(
    kind: kArrayAddr,
    desc: nil,
    buf: newSeq[Operand](len))

  op.desc.memClobbered.add (memIndirect, genMemClobber(memPointer, len, memIndirect))

  for i in 0 ..< len:
    result.buf[i] = Operand(
      desc: op.desc,
      kind: kFromArray,
      offset: i)

func asArrayAddr*(op: Register, memPointer: NimNode, len: int, memIndirect: MemIndirectAccess): Operand =
  ## Use the value stored in an operand as an array address
  result = Operand(
    kind: kArrayAddr,
    desc: nil,
    buf: newSeq[Operand](len))

  let desc = OperandDesc(
        asmId: $op,
        rm: ClobberedReg,
        constraint: asmClobberedRegister)

  desc.memClobbered = @[(memIndirect, genMemClobber(memPointer, len, memIndirect))]

  for i in 0 ..< len:
    result.buf[i] = Operand(
      desc: desc,
      kind: kFromArray,
      offset: i)

func as2dArrayAddr*(op: Operand, memPointer: NimNode, rows, cols: int, memIndirect: MemIndirectAccess): Operand =
  ## Use the value stored in an operand as an array address
  doAssert op.desc.rm in {Reg, PointerInReg, ElemsInReg}+SpecificRegisters
  result = Operand(
    kind: k2dArrayAddr,
    desc: nil,
    dims: [rows, cols],
    buf2d: newSeq[Operand](rows*cols))

  op.desc.memClobbered.add (memIndirect, genMemClobber(memPointer, rows*cols, memIndirect))

  for i in 0 ..< rows*cols:
    result.buf2d[i] = Operand(
      desc: op.desc,
      kind: kFromArray,
      offset: i)

# Code generation
# ------------------------------------------------------------------------------------------------------------

func setToCarryFlag*(a: var Assembler_x86, carry: NimNode) =

  # We need to dereference the hidden pointer of var param
  let isHiddenDeref = carry.kind == nnkHiddenDeref
  let nimSymbol = if isHiddenDeref: carry[0]
                  else: carry
  let symStr = $nimSymbol

  let desc = OperandDesc(
    asmId: "",
    nimSymbol: ident(symStr),
    rm: CarryFlag,
    constraint: asmOutputOverwrite)
  desc.setConstraintString(symStr)
  a.operands.incl(desc)

func generate*(a: Assembler_x86): NimNode =
  ## Generate the inline assembly code from
  ## the desired instruction

  var
    outOperands: seq[string]
    inOperands: seq[string]
    memClobbered = false

  for odesc in a.operands.items():
    if odesc.constraint in {asmInput, asmInputCommutative}:
      inOperands.add odesc.constraintString
    else:
      outOperands.add odesc.constraintString

    for (memIndirect, memDesc) in odesc.memClobbered:
      # TODO: precise clobbering.
      # GCC and Clang complain about impossible constraints or reaching coloring depth
      # when we do precise constraints for pointer indirect accesses

      # the Poly1305 MAC test fails without mem clobbers
      if memIndirect != memRead:
        memClobbered = true
        break

      # if memIndirect == memRead:
      #   inOperands.add memDesc
      # else:
      #   outOperands.add memDesc

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
    result)

func getStrOffset(a: Assembler_x86, op: Operand): string =
  if op.kind != kFromArray:
    if op.kind in {kArrayAddr, k2dArrayAddr}:
      # We are operating on an array pointer
      # instead of array elements
      if op.buf[0].desc.constraint == asmClobberedRegister:
        return op.buf[0].desc.asmId
      else:
        return "%" & op.buf[0].desc.asmId
    else:
      return "%" & op.desc.asmId

  # Beware GCC / Clang differences with displacements
  # https://lists.llvm.org/pipermail/llvm-dev/2017-August/116202.html
  # - Memory operand:
  #   - 8+%[variable] works with GCC
  #   - 8%[variable] works with Clang
  # - Pointer operand
  #   - 8(%rax) works with both
  #
  # In Clang
  # for 8[M], it might become:
  # - invalid:  8BLS12_381_Order(%rip) with LTO constant propagation
  # - or valid: 8(%rax)
  # for 8+[M], it might become:
  # - valid 8+BLS12_381_Order(%rip) with LTO constant propagation
  # - or invalid: 8+(%rax)
  # also warning about 'o' constraint: https://groups.google.com/g/llvm-dev/c/dfsPzWP_H1E
  # and https://stackoverflow.com/questions/34446928/llvm-reports-unsupported-inline-asm-input-with-type-void-matching-output-w
  #
  # So we use the q/k modifier: https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html#x86Operandmodifiers
  # so that the PointerInReg are passed correctly with register names to linker even with constant folding

  if op.desc.rm in {Mem, MemOffsettable}:
    # Directly accessing memory
    if defined(gcc):
      # https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html#x86-Operand-Modifiers
      # q: Print the DImode name of the register.
      # k: Print the SImode name of the register.
      if a.wordBitWidth == 64:
        if op.offset == 0:
          return "%q" & op.desc.asmId
        return "%q" & op.desc.asmId & " + " & $(op.offset * a.wordSize)
      else:
        if op.offset == 0:
          return "%k" & op.desc.asmId
        return "%k" & op.desc.asmId & " + " & $(op.offset * a.wordSize)
    elif defined(clang):
      if a.wordBitWidth == 64:
        if op.offset == 0:
          return "QWORD ptr %" & op.desc.asmId
        return "QWORD ptr " & $(op.offset * a.wordSize) & "%" & op.desc.asmId
      else:
        if op.offset == 0:
          return "DWORD ptr %" & op.desc.asmId
        return "DWORD ptr " & $(op.offset * a.wordSize) & "%" & op.desc.asmId
    else:
      error "Unsupported compiler"

  elif op.desc.rm == PointerInReg or
       op.desc.rm in SpecificRegisters or
       (op.desc.rm == ElemsInReg and op.kind == kFromArray):
    if a.wordBitWidth == 64:
      if op.offset == 0:
        return "QWORD ptr [%" & op.desc.asmId & ']'
      return "QWORD ptr [%" & op.desc.asmId & " + " & $(op.offset * a.wordSize) & ']'
    else:
      if op.offset == 0:
        return "DWORD ptr [%" & op.desc.asmId & ']'
      return "DWORD ptr [%" & op.desc.asmId & " + " & $(op.offset * a.wordSize) & ']'
  elif op.desc.rm == ClobberedReg: # Array in clobbered register
    if a.wordBitWidth == 64:
      if op.offset == 0:
        return "QWORD ptr [" & op.desc.asmId & ']'
      return "QWORD ptr [" & op.desc.asmId & " + " & $(op.offset * a.wordSize) & ']'
    else:
      if op.offset == 0:
        return "DWORD ptr [" & op.desc.asmId & ']'
      return "DWORD ptr [" & op.desc.asmId & " + " & $(op.offset * a.wordSize) & ']'
  else:
    error "Unsupported: " & $op.desc.rm.ord

func codeFragment(a: var Assembler_x86, instr: string, op: Operand) =
  # Generate a code fragment
  let off = a.getStrOffset(op)

  a.code &= instr & " " & off & '\n'

  if op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc

func codeFragment(a: var Assembler_x86, instr: string, op0, op1: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)

  a.code &= instr & " " & off0 & ", " & off1 & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc

func codeFragment(a: var Assembler_x86, instr: string, reg: Register, op: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  let off = a.getStrOffset(op)

  a.code &= instr & " " & $reg & ", " & off & '\n'

  # op.desc can be nil for renamed registers (using asArrayAddr)
  if not op.desc.isNil and op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, op: Operand, reg: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  let off = a.getStrOffset(op)

  a.code &= instr & " " & off & ", " & $reg & '\n'

  if op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, reg0, reg1: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly

  a.code &= instr & " " & $reg0 & ", " & $reg1 & '\n'

  a.regClobbers.incl reg0
  a.regClobbers.incl reg1

func codeFragment(a: var Assembler_x86, instr: string, op: Operand, imm: int) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  let off = a.getStrOffset(op)

  a.code &= instr & " " & off & ", " & $imm & '\n'

  if op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc

func codeFragment(a: var Assembler_x86, instr: string, op: OperandReuse, reg: Register) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  a.code &= instr & " %" & $op.asmId & ", " & $reg & '\n'
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, reg: Register, op: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  a.code &= instr & " " & $reg & ", %" & $op.asmId & '\n'
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, reg: Register, imm: int) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  a.code &= instr & " " & $reg & ", " & $imm & '\n'
  a.regClobbers.incl reg

func codeFragment(a: var Assembler_x86, instr: string, reg: OperandReuse, imm: int) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits Intel Assembly
  a.code &= instr & " %" & $reg.asmId & ", " & $imm & '\n'

func codeFragment(a: var Assembler_x86, instr: string, reg0, reg1: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  a.code &= instr & " %" & $reg0.asmId & ", %" & $reg1.asmId & '\n'

func codeFragment(a: var Assembler_x86, instr: string, op0: Operand, op1: OperandReuse) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off0 = a.getStrOffset(op0)

  a.code &= instr & " " & off0 & ", %" & $op1.asmId & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc

func codeFragment(a: var Assembler_x86, instr: string, op0: OperandReuse, op1: Operand) =
  # Generate a code fragment
  # ⚠️ Warning:
  # The caller should deal with destination/source operand
  # so that it fits GNU Assembly
  let off1 = a.getStrOffset(op1)

  a.code &= instr & " %" & $op0.asmId & ", " & off1 & '\n'

  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc


func reuseRegister*(reg: OperandArray): OperandReuse =
  doAssert reg.buf[0].desc.constraint in {asmInputOutput, asmInputOutputEarlyClobber}
  result.asmId = reg.buf[0].desc.asmId

func comment*(a: var Assembler_x86, comment: string) =
  # Add a comment
  a.code &= "# " & comment & '\n'

func repackRegisters*(regArr: OperandArray, regs: varargs[Operand]): OperandArray =
  ## Extend an array of registers with extra registers
  result.buf = regArr.buf
  result.buf.add regs
  result.nimSymbol = nil

func subset*(regArr: OperandArray, start, stopEx: int): OperandArray =
  ## Keep a subset of registers
  result.nimSymbol = nil
  for i in start ..< stopEx:
    result.buf.add regArr[i]

func isOutput(op: Operand): bool =
  if op.desc.constraint in OutputReg:
    return true

  if op.desc.rm == PointerInReg:
    doAssert op.desc.memClobbered.len == 1
    if op.desc.memClobbered[0][0] in {memWrite, memReadWrite}:
      return true

  # Currently there is no facility to track writes through an ElemsInReg + asArrayAddr

  return false


# Instructions
# ------------------------------------------------------------------------------------------------------------

func add*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst + src
  doAssert dst.isOutput()
  a.codeFragment("add", dst, src)
  a.areFlagsClobbered = true

func add*(a: var Assembler_x86, dst, src: Register) =
  ## Does: dst <- dst + src
  a.codeFragment("add", dst, src)
  a.areFlagsClobbered = true

func add*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- dst + src
  doAssert dst.isOutput()
  a.codeFragment("add", dst, src)
  a.areFlagsClobbered = true

func add*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Does: dst <- dst + src
  a.codeFragment("add", dst, src)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst + src + carry
  doAssert dst.isOutput()
  doAssert dst.desc.rm notin {Mem, MemOffsettable},
    "Using addcarry with a memory destination, this incurs significant performance penalties."

  a.codeFragment("adc", dst, src)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst, src: Register) =
  ## Does: dst <- dst + src + carry
  a.codeFragment("adc", dst, src)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does: dst <- dst + imm + borrow
  doAssert dst.isOutput()
  doAssert dst.desc.rm notin {Mem, MemOffsettable},
    "Using addcarry with a memory destination, this incurs significant performance penalties."

  a.codeFragment("adc", dst, imm)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- dst + src
  doAssert dst.isOutput()
  a.codeFragment("adc", dst, src)
  a.areFlagsClobbered = true

func adc*(a: var Assembler_x86, dst: Register, imm: int) =
  ## Does: dst <- dst + src
  a.codeFragment("adc", dst, imm)
  a.areFlagsClobbered = true

func sub*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst - src
  doAssert dst.isOutput()
  a.codeFragment("sub", dst, src)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- dst - src - borrow
  doAssert dst.isOutput()
  doAssert dst.desc.rm notin {Mem, MemOffsettable},
    "Using subborrow with a memory destination, this incurs significant performance penalties."

  a.codeFragment("sbb", dst, src)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does: dst <- dst - imm - borrow
  doAssert dst.isOutput()
  doAssert dst.desc.rm notin {Mem, MemOffsettable},
    "Using subborrow with a memory destination, this incurs significant performance penalties."

  a.codeFragment("sbb", dst, imm)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst: Register, imm: int) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", dst, imm)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: Register) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", dst, src)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst: OperandReuse, imm: int) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", dst, imm)
  a.areFlagsClobbered = true

func sbb*(a: var Assembler_x86, dst, src: OperandReuse) =
  ## Does: dst <- dst - imm - borrow
  a.codeFragment("sbb", dst, src)
  a.areFlagsClobbered = true

func sar*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does Arithmetic Right Shift (i.e. with sign extension)
  doAssert dst.isOutput()
  a.codeFragment("sar", dst, imm)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", dst, src)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst: OperandReuse, imm: int) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", dst, imm)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst, src: Operand) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", dst, src)
  a.areFlagsClobbered = true

func `and`*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Compute the bitwise AND of x and y and
  ## set the Sign, Zero and Parity flags
  a.codeFragment("and", dst, src)
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

func `or`*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Compute the bitwise or of x and y and
  ## reset all flags
  a.codeFragment("or", dst, src)
  a.areFlagsClobbered = true

func `or`*(a: var Assembler_x86, dst, src: Operand) =
  ## Compute the bitwise or of x and y and
  ## reset all flags
  a.codeFragment("or", dst, src)
  a.areFlagsClobbered = true

func `or`*(a: var Assembler_x86, dst: OperandReuse, src: Operand) =
  ## Compute the bitwise or of x and y and
  ## reset all flags
  a.codeFragment("or", dst, src)
  a.areFlagsClobbered = true

func `xor`*(a: var Assembler_x86, dst, src: Operand) =
  ## Compute the bitwise xor of x and y and
  ## reset all flags
  a.codeFragment("xor", dst, src)
  a.areFlagsClobbered = true

func `xor`*(a: var Assembler_x86, dst, src: Register) =
  ## Compute the bitwise xor of x and y and
  ## reset all flags
  a.codeFragment("xor", dst, src)
  a.areFlagsClobbered = true

func mov*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("mov", dst, src)
  # No clobber

func mov*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Does: dst <- src
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("mov", dst, src)
  # No clobber

func mov*(a: var Assembler_x86, dst: OperandReuse, src: Operand) =
  ## Does: dst <- src
  # doAssert dst.isOutput(), $dst.repr

  a.codeFragment("mov", dst, src)
  # No clobber

func mov*(a: var Assembler_x86, dst: Operand, imm: int) =
  ## Does: dst <- imm
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("mov", dst, imm)
  # No clobber

func mov*(a: var Assembler_x86, dst: Register, imm: int) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", dst, imm)

func mov*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", dst, src)

func mov*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", dst, src)

func mov*(a: var Assembler_x86, dst: Register, src: OperandReuse) =
  ## Does: dst <- src with dst a fixed register
  a.codeFragment("mov", dst, src)

func mov*(a: var Assembler_x86, dst: OperandReuse, src: Register) =
  ## Does: dst <- imm
  # doAssert dst.isOutput(), $dst.repr
  a.codeFragment("mov", dst, src)

func cmovc*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the carry flag is set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovc", dst, src)
  # No clobber

func cmovnc*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the carry flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovnc", dst, src)
  # No clobber

func cmovz*(a: var Assembler_x86, dst: Operand, src: Register) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovz", dst, src)
  # No clobber

func cmovz*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovz", dst, src)
  # No clobber

func cmovz*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovz", dst, src)
  # No clobber

func cmovnz*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovnz", dst, src)
  # No clobber

func cmovnz*(a: var Assembler_x86, dst: Operand, src: OperandReuse) =
  ## Does: dst <- src if the zero flag is not set
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovnz", dst, src)
  # No clobber

func cmovs*(a: var Assembler_x86, dst, src: Operand) =
  ## Does: dst <- src if the sign flag
  doAssert dst.desc.rm in {Reg, ElemsInReg}, "The destination operand must be a register: " & $dst.repr
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("cmovs", dst, src)
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
  doAssert dst.isOutput(), $dst.repr

  a.codeFragment("imul", dst, src)

func imul*(a: var Assembler_x86, dst: Register, src: Operand) =
  ## Does dst <- dst * src, keeping only the low half
  a.codeFragment("imul", dst, src)

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

  a.code &= "mulx %" & $dHi.desc.asmId & ", %" & $dLo.desc.asmId & ", " & off0 & '\n'

  a.operands.incl src0.desc

func mulx*(a: var Assembler_x86, dHi: Operand, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  doAssert dHi.desc.rm in {Reg, ElemsInReg}+SpecificRegisters,
    "The destination operand must be a register " & $dHi.repr
  doAssert dHi.desc.constraint in OutputReg

  let off0 = a.getStrOffset(src0)

  a.code &= "mulx %" & $dHi.desc.asmId & ", " & $dLo & ", " & off0 & '\n'

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

  a.code &= "mulx %" & $dHi.asmId & ", %" & $dLo.desc.asmId & ", " & off0 & '\n'

  a.operands.incl src0.desc

func mulx*(a: var Assembler_x86, dHi: OperandReuse, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  let off0 = a.getStrOffset(src0)

  a.code &= "mulx %" & $dHi.asmId & ", " & $dLo & ", " & off0 & '\n'

  a.operands.incl src0.desc
  a.regClobbers.incl dLo

func mulx*(a: var Assembler_x86, dHi, dLo: Register, src0: Operand, src1: Register) =
  ## Does (dHi, dLo) <- src0 * src1
  doAssert src1 == rdx, "MULX requires the RDX register"
  a.regClobbers.incl rdx

  let off0 = a.getStrOffset(src0)

  a.code &= "mulx " & $dHi & ", " & $dLo & ", " & off0 & '\n'

  a.operands.incl src0.desc
  a.regClobbers.incl dHi
  a.regClobbers.incl dLo

func adcx*(a: var Assembler_x86, dst: Operand|OperandReuse|Register, src: Operand|OperandReuse|Register) =
  ## Does: dst <- dst + src + carry
  ## and only sets the carry flag
  when dst is Operand:
    doAssert dst.isOutput(), $dst.repr
    doAssert dst.desc.rm in {Reg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $dst.repr
  a.codeFragment("adcx", dst, src)
  a.areFlagsClobbered = true

func adox*(a: var Assembler_x86, dst: Operand|OperandReuse|Register, src: Operand|OperandReuse|Register) =
  ## Does: dst <- dst + src + overflow
  ## and only sets the overflow flag
  when dst is Operand:
    doAssert dst.isOutput(), $dst.repr
    doAssert dst.desc.rm in {Reg, ElemsInReg}+SpecificRegisters, "The destination operand must be a register: " & $dst.repr
  a.codeFragment("adox", dst, src)
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
