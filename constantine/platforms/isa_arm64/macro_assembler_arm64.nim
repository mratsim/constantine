# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[macros, strutils, sets, hashes, algorithm, sequtils, enumutils]

# A compile-time inline assembler

# No exceptions allowed
{.push raises: [].}

type
  RM* = enum
    ## Register or Memory operand
    # https://gcc.gnu.org/onlinedocs/gcc/Simple-Constraints.html
    # We don't use the "Any" constraint like rm, g, oi or ri. It's unsure how to mix the differing semantics
    Reg            = "r"
    Mem            = "m" # It doesn't seem possible to specify Aarch64 memory offsets.
    Imm            = "i"
    MemOffsettable = "o" # 'o' constraint might not work fully https://groups.google.com/g/llvm-dev/c/dfsPzWP_H1E

    PointerInReg   = "r" # Store an array pointer. ⚠️ for const arrays, this may generate incorrect code with LTO and constant folding.
    ElemsInReg     = "r" # Store each individual array element in reg

    # Specific registers
    XZR            = "zr"

    # Flags
    CarryFlag      = "@cccs" # https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html#Flag-Output-Operands
    BorrowFlag     = "@cccc" # ARM uses inverted carry for subtraction, i.e. it sets the carry flag if no borrow occured
                             # - https://devblogs.microsoft.com/oldnewthing/20220729-00/?p=106915
                             # - https://stackoverflow.com/questions/77672643/aarch64-sub-etc-instructions-defined-as-add-with-carry-operation
                             # - https://retrocomputing.stackexchange.com/questions/21861/what-cpu-architecture-was-first-to-implement-inverted-borrow-carry-flag-during

    # Clobbered register
    ClobberedReg

    # Aarch memory offset are in the form `ldr x8, [x0, #8]`
    # However, when using a memory operand %[a] will be replaced by [x0], leading to `ldr x8, [[x0], #8]`, which is incorrect
    # on Aarch32 it was possible to specify %m[a] modifier to remove the brackets
    # but this is not available on Aarch64:
    # https://developer.arm.com/documentation/101754/0616/armclang-Reference/armclang-Inline-Assembler/Inline-assembly-constraint-strings/Constraint-codes-common-to-AArch32-state-and-AArch64-state?lang=en

type
  ConditionCode* = enum
    # https://community.arm.com/arm-community-blogs/b/architectures-and-processors-blog/posts/condition-codes-1-condition-flags-and-codes
    # https://devblogs.microsoft.com/oldnewthing/20220815-00/?p=106975
    eq
    ne
    cs
    hs
    cc
    lo
    mi
    pl
    vs
    vc
    hi
    ls
    ge
    lt
    gt
    le
    al

type
  Register* = enum
    xzr

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
    constraintDesc: seq[NimNode] # C emit for example `[a] "r" (a->limbs)`
    memClobbered: seq[(MemIndirectAccess, seq[NimNode])]

  OperandArray* = object
    nimSymbol: NimNode
    buf: seq[Operand]

  OperandReuse* = object
    # Allow reusing a register
    asmId: string

  Assembler_arm64* = object
    code: string
    operands: HashSet[OperandDesc]
    wordBitWidth*: int
    wordSize: int
    areFlagsClobbered: bool
    isStackClobbered: bool
    regClobbers: set[Register] # Unused. We don't use named registers on ARM64 as instructions are not register specific.

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

func init*(T: type Assembler_arm64, Word: typedesc[SomeUnsignedInt]): Assembler_arm64 =
  result.wordSize = sizeof(Word)
  result.wordBitWidth = result.wordSize * 8

func escapeConstraint(asmDesc: string, symbol: NimNode): seq[NimNode] =
  # Input:
  # The assembly symbol + constraint + opening '(' + modifiers like reference/dereference/array-ranges
  # The Nim symbol
  #
  # The closing ')' is automatically appended.
  @[
    newLit(asmDesc),
    symbol,
    newLit ")",
  ]

func setConstraintDesc(desc: OperandDesc, symbol: NimNode) =
  # [a] "rbx" (`a`) for specific registers
  # [a] "+r" (`*a_ptr`) for pointer to memory
  # [a] "+r" (`a[0]`) for array cells
  desc.constraintDesc = escapeConstraint(
    desc.asmId & "\"" & $desc.constraint & $desc.rm & "\"" & " (",
    symbol
  )

func setConstraintDesc(desc: OperandDesc, modifier: string, symbol: NimNode) =
  # [a] "rbx" (`a`) for specific registers
  # [a] "+r" (`*a_ptr`) for pointer to memory
  # [a] "+r" (`a[0]`) for array cells
  desc.constraintDesc = escapeConstraint(
    desc.asmId & "\"" & $desc.constraint & $desc.rm & "\"" & " (" & modifier,
    symbol
  )

func genRawMemClobber(nimSymbol: NimNode, len: int, memIndirect: MemIndirectAccess): seq[NimNode] =
  ## Create a raw memory clobber, for use in clobber list
  let baseType = nimSymbol.getTypeImpl()[2].getTypeImpl()[0]
  let cBaseType = if baseType.sameType(getType(uint64)): "NU64"
                  else: "NU32"

  case memIndirect
  of memRead:
    return escapeConstraint("\"o\" (*(const " & cBaseType & " (*)[" & $len & "]) ", nimSymbol)
  of memWrite:
    return escapeConstraint("\"=o\" (*(" & cBaseType & " (*)[" & $len & "]) ", nimSymbol)
  of memReadWrite:
    return escapeConstraint("\"+o\" (*(" & cBaseType & " (*)[" & $len & "]) ", nimSymbol)
  else:
    doAssert false, "Indirect access kind not specified"

func genConstraintMemClobber(asmSymbol: string, nimSymbol: NimNode, len: int, memIndirect: MemIndirectAccess): seq[NimNode] =
  ## Create a constraint memory clobber, for use in constraint list
  let baseType = nimSymbol.getTypeImpl()[2].getTypeImpl()[0]
  let cBaseType = if baseType.sameType(getType(uint64)): "NU64"
                  else: "NU32"

  case memIndirect
  of memRead:
    return escapeConstraint("[" & asmSymbol & "] \"o\" (*(const " & cBaseType & " (*)[" & $len & "]) ", nimSymbol)
  of memWrite:
    return escapeConstraint("[" & asmSymbol & "] \"=o\" (*(" & cBaseType & " (*)[" & $len & "]) ", nimSymbol)
  of memReadWrite:
    return escapeConstraint("[" & asmSymbol & "] \"+o\" (*(" & cBaseType & " (*)[" & $len & "]) ", nimSymbol)
  else:
    doAssert false, "Indirect access kind not specified"

func asmValue*(nimSymbol: NimNode, rm: RM, constraint: Constraint): Operand =
  let desc = OperandDesc(
        asmId: "[" & $nimSymbol & "]",
        nimSymbol: nimSymbol,
        rm: rm,
        constraint: constraint)
  if rm in {Mem, MemOffsettable}:
    desc.setConstraintDesc("*&", nimSymbol)
  else:
    desc.setConstraintDesc(nimSymbol)
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
                  memClobbered: @[(memIndirect, genRawMemClobber(nimSymbol, len, memIndirect))])
    desc.setConstraintDesc(nimSymbol)

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
                  constraintDesc: genConstraintMemClobber(symStr, nimSymbol, len, memIndirect))

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
  elif rm == ElemsInReg:
    #   We can't store an array in register so we create assign individual register
    #   per array elements instead
    for i in 0 ..< len:
      let desc = OperandDesc(
                  asmId: "[" & symStr & $i & "]",
                  nimSymbol: ident(symStr & $i),
                  rm: rm,
                  constraint: constraint)
      desc.setConstraintDesc(nnkBracketExpr.newTree(nimSymbol, newLit i))
      result.buf[i] = Operand(
        desc: desc,
        kind: kRegister)
  else:
    error "Not implemented"

func asArrayAddr*(op: Operand, memPointer: NimNode, len: int, memIndirect: MemIndirectAccess): Operand =
  ## Use the value stored in an operand as an array address
  doAssert op.desc.rm in {Reg, PointerInReg, ElemsInReg}
  result = Operand(
    kind: kArrayAddr,
    desc: nil,
    buf: newSeq[Operand](len))

  op.desc.memClobbered.add (memIndirect, genRawMemClobber(memPointer, len, memIndirect))

  for i in 0 ..< len:
    result.buf[i] = Operand(
      desc: op.desc,
      kind: kFromArray,
      offset: i)

func as2dArrayAddr*(op: Operand, memPointer: NimNode, rows, cols: int, memIndirect: MemIndirectAccess): Operand =
  ## Use the value stored in an operand as an array address
  doAssert op.desc.rm in {Reg, PointerInReg, ElemsInReg}
  result = Operand(
    kind: k2dArrayAddr,
    desc: nil,
    dims: [rows, cols],
    buf2d: newSeq[Operand](rows*cols))

  op.desc.memClobbered.add (memIndirect, genRawMemClobber(memPointer, rows*cols, memIndirect))

  for i in 0 ..< rows*cols:
    result.buf2d[i] = Operand(
      desc: op.desc,
      kind: kFromArray,
      offset: i)

# Code generation
# ------------------------------------------------------------------------------------------------------------

func setOutputToFlag*(a: var Assembler_arm64, outputFlag: NimNode, carryOrBorrow: RM) =
  doAssert carryOrBorrow in {CarryFlag, BorrowFlag}
  # We need to dereference the hidden pointer of var param
  let isHiddenDeref = outputFlag.kind == nnkHiddenDeref
  let nimSymbol = if isHiddenDeref: outputFlag[0]
                  else: outputFlag
  let symStr = $nimSymbol

  let desc = OperandDesc(
    asmId: "",
    nimSymbol: ident(symStr),
    rm: carryOrBorrow,
    constraint: asmOutputOverwrite)
  desc.setConstraintDesc(nimSymbol)
  a.operands.incl(desc)

func generate*(a: Assembler_arm64): NimNode =
  ## Generate the inline assembly code from
  ## the desired instruction

  var
    outOperands: seq[seq[NimNode]]
    inOperands: seq[seq[NimNode]]
    memClobbered = false

  for odesc in a.operands.items():
    if odesc.constraint in {asmInput, asmInputCommutative}:
      inOperands.add odesc.constraintDesc
    else:
      outOperands.add odesc.constraintDesc

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

  var params: seq[NimNode]
  if outOperands.len != 0:
    params.add newLit(": ") & outOperands.foldl(a & newLit(", ") & b) & newLit("\n")
  else:
    params.add newLit(":\n")
  if inOperands.len != 0:
    params.add newLit(": ") &  inOperands.foldl(a & newLit(", ") & b) & newLit("\n")
  else:
    params.add newLit(":\n")

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

  params.add newLit(clobberList)

  # GCC will optimize ASM away if there are no
  # memory operand or volatile + memory clobber
  # https://stackoverflow.com/questions/34244185/looping-over-arrays-with-inline-assembly

  # result = nnkAsmStmt.newTree(
  #   newEmptyNode(),
  #   newLit(asmStmt & params)
  # )

  var asmStmt = "\"" & a.code.replace("\n", "\\n\"\n\"")
  asmStmt.setLen(asmStmt.len - 1) # drop the last quote

  var emitStmt = nnkBracket.newTree(
        newLit("\nasm volatile(\n"),
        newLit(asmStmt),
  )

  for node in params:
    emitStmt.add node

  emitStmt.add newLit(");")

  result = nnkPragma.newTree(
    nnkExprColonExpr.newTree(
      ident"emit",
      emitStmt
    )
  )
  result = nnkBlockStmt.newTree(
    newEmptyNode(),
    result)

func getStrOffset(a: Assembler_arm64, op: Operand, force32IfReg = false): string =
  # force32IfReg forces uses of 32-bit registers (memory operand are not changed)

  if op.kind != kFromArray:
    if op.kind in {kArrayAddr, k2dArrayAddr}:
      # We are operating on an array pointer
      # instead of array elements
      if op.buf[0].desc.constraint == asmClobberedRegister:
        return op.buf[0].desc.asmId
      else:
        return "%" & op.buf[0].desc.asmId
    elif op.kind == kRegister:
      if force32IfReg:
        return "%w" & op.desc.asmId
      else:
        return "%" & op.desc.asmId
    else:
      error "Unsupported: " & $op.kind

  if op.desc.rm in {Mem, MemOffsettable}:
    # Directly accessing memory
    # We cannot generate displacements in inline assembly memory operands
    error "Memory operand aren't supported for ARM64"

  elif op.desc.rm == PointerInReg or
       (op.desc.rm == ElemsInReg and op.kind == kFromArray):
    if op.offset == 0:
      return "[%" & op.desc.asmId & ']'
    return "[%" & op.desc.asmId & ", #" & $(op.offset * a.wordSize) & ']'
  elif op.desc.rm == ClobberedReg: # Array in clobbered register
    if op.offset == 0:
      return "[" & op.desc.asmId & ']'
    return "[" & op.desc.asmId & ", #" & $(op.offset * a.wordSize) & ']'
  else:
    error "Unsupported: " & $op.desc.rm.symbolName() & "\n" &
      op.repr

func codeFragment(a: var Assembler_arm64, instr: string, op: Operand, reg: Register) =
  # Generate a code fragment
  let off = a.getStrOffset(op)

  a.code &= instr & " " & off & ", " & $reg & '\n'

  if op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc
  if reg != xzr:
    a.regClobbers.incl reg

func codeFragment(a: var Assembler_arm64, instr: string, op0, op1: Operand) =
  # Generate a code fragment
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)

  a.code &= instr & " " & off0 & ", " & off1 & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc

func codeFragment(a: var Assembler_arm64, instr: string, op0, op1, op2: Operand) =
  # Generate a code fragment
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)
  let off2 = a.getStrOffset(op2)

  a.code &= instr & " " & off0 & ", " & off1 & ", " & off2 & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc
  if op2.desc.constraint != asmClobberedRegister:
    a.operands.incl op2.desc

func codeFragment(a: var Assembler_arm64, instr: string, op0, op1: Operand, op2: OperandReuse) =
  # Generate a code fragment
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)

  a.code &= instr & " " & off0 & ", " & off1 & ", %" & $op2.asmId & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc

func codeFragment(a: var Assembler_arm64, instr: string, op0, op1, op2: Operand, cc: ConditionCode) =
  # Generate a code fragment
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)
  let off2 = a.getStrOffset(op2)

  a.code &= instr & " " & off0 & ", " & off1 & ", " & off2 & ", " & $cc & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc
  if op2.desc.constraint != asmClobberedRegister:
    a.operands.incl op2.desc

func codeFragment(a: var Assembler_arm64, instr: string, op0, op1: Operand, reg: Register) =
  # Generate a code fragment
  let off0 = a.getStrOffset(op0)
  let off1 = a.getStrOffset(op1)

  a.code &= instr & " " & off0 & ", " & off1 & ", " & $reg & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc
  if reg != xzr:
    a.regClobbers.incl reg

func codeFragment(a: var Assembler_arm64, instr: string, op: Operand, reg0, reg1: Register) =
  # Generate a code fragment
  let off = a.getStrOffset(op)

  a.code &= instr & " " & off & ", " & $reg0 & ", " & $reg1 & '\n'

  if op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc
  if reg0 != xzr:
    a.regClobbers.incl reg0
  if reg1 != xzr:
    a.regClobbers.incl reg1

func codeFragment(a: var Assembler_arm64, instr: string, op: OperandReuse, reg0, reg1: Register) =
  # Generate a code fragment

  a.code &= instr & " %" & $op.asmId & ", " & $reg0 & ", " & $reg1 & '\n'

  if reg0 != xzr:
    a.regClobbers.incl reg0
  if reg1 != xzr:
    a.regClobbers.incl reg1

func codeFragment(a: var Assembler_arm64, instr: string, dst: Register, lhs: OperandReuse, rhs: Register) =
  # Generate a code fragment

  a.code &= instr & " " & $dst & ", %" & $lhs.asmId & ", " & $rhs & '\n'

  if dst != xzr:
    a.regClobbers.incl dst
  if rhs != xzr:
    a.regClobbers.incl rhs

func reuseRegister*(reg: OperandArray): OperandReuse =
  doAssert reg.buf[0].desc.constraint in {asmInputOutput, asmInputOutputEarlyClobber}
  result.asmId = reg.buf[0].desc.asmId

func comment*(a: var Assembler_arm64, comment: string) =
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

func ldr*(a: var Assembler_arm64, dst, src: Operand) =
  ## Load register: dst <- src
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("ldr", dst, src)

func ldp*(a: var Assembler_arm64, dst0, dst1, src: Operand) =
  ## Load pair: (dst0, dst1) <- src
  doAssert dst0.isOutput(), $dst0.repr
  doAssert dst1.isOutput(), $dst1.repr
  a.codeFragment("ldp", dst0, dst1, src)

func str*(a: var Assembler_arm64, src, dst: Operand) =
  ## Store register: src -> dst
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("str", src, dst)

func stp*(a: var Assembler_arm64, src0, src1, dst: Operand) =
  ## Store pair: (src0, src1) -> dst
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("stp", src0, src1, dst)

func add*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Addition (no flags):
  ##   dst <- lhs + rhs
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("add", dst, lhs, rhs)

func adds*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Addition (set carry flag):
  ##   (carry, dst) <- lhs + rhs
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("adds", dst, lhs, rhs)

func adc*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Addition-with-carry (no carry flag):
  ##   dst <- lhs + rhs + carry
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("adc", dst, lhs, rhs)

func adc*(a: var Assembler_arm64, dst: OperandReuse, lhs, rhs: Register) =
  ## Addition-with-carry (no carry flag):
  ##   dst <- lhs + rhs + carry
  a.codeFragment("adc", dst, lhs, rhs)

func adc*(a: var Assembler_arm64, dst: Operand, lhs: Operand, rhs: Register) =
  ## Addition-with-carry (no carry flag):
  ##   dst <- lhs + rhs + carry
  a.codeFragment("adc", dst, lhs, rhs)

func adc*(a: var Assembler_arm64, dst: Operand, lhs, rhs: Register) =
  ## Addition-with-carry (no carry flag):
  ##   dst <- lhs + rhs + carry
  a.codeFragment("adc", dst, lhs, rhs)

func adcs*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Addition-with-carry (set carry flag):
  ##   (carry, dst) <- lhs + rhs + carry
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("adcs", dst, lhs, rhs)

func sub*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Subtraction (no flags):
  ##   dst <- lhs - rhs
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("sub", dst, lhs, rhs)

func subs*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Subtraction (set carry flag):
  ##   (borrow, dst) <- lhs - rhs
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("subs", dst, lhs, rhs)

func sbc*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Subtraction with borrow (no carry flag):
  ##   dst <- lhs - rhs - borrow
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("sbc", dst, lhs, rhs)

func sbc*(a: var Assembler_arm64, dst: OperandReuse, lhs, rhs: Register) =
  ## Subtraction-with-borrow (no carry flag):
  ##   dst <- lhs - rhs - borrow
  a.codeFragment("sbc", dst, lhs, rhs)

func sbcs*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Subtraction with borrow (set carry flag):
  ##   (borrow, dst) <- lhs - rhs - borrow
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("sbcs", dst, lhs, rhs)

func sbcs*(a: var Assembler_arm64, dst: Register, lhs: OperandReuse, rhs: Register) =
  ## Subtraction with borrow (set carry flag):
  ##   (borrow, dst) <- lhs - rhs - borrow
  a.codeFragment("sbcs", dst, lhs, rhs)

func mul*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Multiplication (no flags):
  ##   dst <- (lhs * rhs) mod 64
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("mul", dst, lhs, rhs)

func umulh*(a: var Assembler_arm64, dst, lhs, rhs: Operand) =
  ## Multiplication high-word (no flags):
  ##   dst <- (lhs * rhs) >> 64
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("umulh", dst, lhs, rhs)

func csel*(a: var Assembler_arm64, dst, lhs, rhs: Operand, cc: ConditionCode) =
  ## Conditional select into dst depending on condition code
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("csel", dst, lhs, rhs, cc)

func cmp*(a: var Assembler_arm64, lhs: Operand, rhs: Register) =
  ## Compare and set flags / condition code
  ## This uses SUBS and discards the result
  a.codeFragment("cmp", lhs, rhs)

func cmn*(a: var Assembler_arm64, lhs: Operand, rhs: Operand) =
  ## Compare-negative and set flags / condition code
  ## This uses ADDS and discards the result
  a.codeFragment("cmn", lhs, rhs)

func `and`*(a: var Assembler_arm64, dst: Operand, lhs: Operand, rhs: OperandReuse) =
  a.codeFragment("and", dst, lhs, rhs)

func mov*(a: var Assembler_arm64, dst: Operand, src: Register) =
  a.codeFragment("mov", dst, src)