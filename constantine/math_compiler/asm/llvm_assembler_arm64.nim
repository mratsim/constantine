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
# This reuses most the Nim assembler logic
# but changes the codegen to fit LLVM IR inline assembler
# See LLVM IR reference manual https://llvm.org/docs/LangRef.html#inline-assembler-expressions

# No exceptions allowed
{.push raises: [].}

type
  RM* = enum
    ## Register or Memory operand
    # https://llvm.org/docs/LangRef.html#supported-constraint-code-list
    # We don't use the "Any" constraint like rm, g, oi or ri. It's unsure how to mix the differing semantics
    Reg            = "r"
    # Mem            = "m" # It doesn't seem possible to specify Aarch64 memory offsets. Indirect write need =*m
    Imm            = "i"
    # MemLoad        = "p"

    PointerInReg   = "r" # Store an array pointer. ⚠️ for const arrays, this may generate incorrect code with LTO and constant folding.
    ElemsInReg     = "r" # Store each individual array element in reg

    # Specific registers
    XZR            = "zr"

    # Clobbered register
    ClobberedReg

    # Aarch memory offset are in the form `ldr x8, [x0, #8]`
    # However, when using a memory operand %[a] will be replaced by [x0], leading to `ldr x8, [[x0], #8]`, which is incorrect
    # on Aarch32 it was possible to specify %m[a] modifier to remove the brackets
    # but this is not available on Aarch64:
    # https://developer.arm.com/documentation/101754/0616/armclang-Reference/armclang-Inline-Assembler/Inline-assembly-constraint-strings/Constraint-codes-common-to-AArch32-state-and-AArch64-state?lang=en
    #
    # It may be possible to pass multiple memory operand instead
    # but we might as well pass the pointer and do the load ourselves

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
    asmOutputOverwrite     = "="  # This assumes it's written after all inputs are read, i.e. it can reuse an input register
    asmOutputEarlyClobber  = "=&"
    asmInputOutput         =      # This will need 2 entries in output and as tied input in LLVM IR, and output should be =&
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
    # IDs are assigned outputs first, then inputs
    # then inputs tied to the id of the output
    # We require outputs to be declared before inputs
    asmId: int
    debugId: string
    rm: RM
    constraint: Constraint
    memClobbered: seq[tuple[kind: MemIndirectAccess, len: int]]

  OperandArray* = object
    asmId: int
    debugId: string
    buf: seq[Operand]

  OperandReuse* = object
    # Allow reusing a register
    asmId: int
    debugId: string

  Assembler_arm64* = object
    code: string
    operandsOut: seq[OperandDesc]
    operandsIn: seq[OperandDesc]
    operandsInOut: seq[int] # ID in the operandsOut array
    wordBitWidth*: int
    wordSize: int
    areFlagsClobbered: bool
    isStackClobbered: bool
    regClobbers: set[Register] # Unused. We don't use named registers on ARM64 as instructions are not register specific.

func c(code: string): CodeWord =
  CodeWord(kind: kCode, code: code)

func c(id: int): CodeWord =
  CodeWord(kind: kID, tempId: id)

const OutputReg = {asmOutputEarlyClobber, asmInputOutput, asmInputOutputEarlyClobber, asmOutputOverwrite, asmClobberedRegister}

func hash(od: OperandDesc): Hash =
  {.noSideEffect.}:
    hash(od.tempId)

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

func getID(a: Assembler_arm64): int =
  return a.outOperands.len + a.inOperands.len

func track(a: var Assembler_arm64, op: Operand) =
  doAssert op.id == a.getID()

  if op.constraint in {asmInputOutput, asmOutputEarlyClobber, asmOutputOverwrite} and
      a.inOperands.len != 0:
    error "Outputs MUST be declared before inputs."

  if op.constraint in {asmInputOutput, asmOutputEarlyClobber, asmOutputOverwrite}:
    a.outOperands.add op
    if op.constraint == asmInputOutput
      a.inOutOperands.add a.outOperands.len-1
  else:
    a.inOperands.add op

func asmValue*(a: var Assembler_arm64, debugId: string, rm: RM, constraint: Constraint): Operand =
  let desc = OperandDesc(
        asmId: a.getID(),
        debugId: debugId,
        rm: rm,
        constraint: constraint)
  result = Operand(desc: desc)
  a.track(result)

func asmArray*(a: var Assembler_arm64, debugId: string, len: int, rm: RM, constraint: Constraint, memIndirect = memNoAccess): OperandArray =
  doAssert rm in {PointerInReg, ElemsInReg} # We don't support Memory "m" and MemLoad "p" constraint at the moment
  doAssert (rm == PointerInReg) xor (memIndirect == memNoAccess)

  result.debugId = debugId
  result.buf.setLen(len)

  if rm == PointerInReg:
    let desc = OperandDesc(
                  asmId: a.getID(),
                  debugId: debugId,
                  rm: rm,
                  constraint: constraint,
                  memClobbered: @[(memIndirect, len)])

    for i in 0 ..< len:
      result.buf[i] = Operand(
        desc: desc,
        kind: kFromArray,
        offset: i)

    result.tempId = a.getID()
    a.track(result)
  elif rm == ElemsInReg:
    #   We can't store an array in register so we create assign individual register
    #   per array elements instead
    for i in 0 ..< len:
      let desc = OperandDesc(
                  asmId: a.getID(),
                  debugId: debugId & $i,
                  rm: rm,
                  constraint: constraint)
      result.buf[i] = Operand(
        desc: desc,
        kind: kRegister)
      a.track(result.buf[i])
  else:
    error "asmArray not implemented for constraint: " & $rm

func asArrayAddr*(op: Operand, memPointer: NimNode, len: int, memIndirect: MemIndirectAccess): Operand =
  ## Use the value stored in an operand as an array address
  doAssert op.desc.rm in {Reg, PointerInReg, ElemsInReg}
  result = Operand(
    kind: kArrayAddr,
    desc: nil,
    buf: newSeq[Operand](len))

  op.desc.memClobbered.add (memIndirect, len)

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

  op.desc.memClobbered.add (memIndirect, rows*cols)

  for i in 0 ..< rows*cols:
    result.buf2d[i] = Operand(
      desc: op.desc,
      kind: kFromArray,
      offset: i)

# Code generation
# ------------------------------------------------------------------------------------------------------------

func generate*(a: Assembler_arm64): NimNode =
  ## Generate the inline assembly code from
  ## the desired instruction

  var
    constraints: string
    memClobbered = false

  for odesc in a.operands.items():
    if odesc.constraint == asmInput:
      inOperands.add ($odesc.constraint & $odesc.rm) # should always be r or i
    elif odesc.constraint in {asmOutputOverwrite, asmOutputEarlyClobber}:
      outOperands.add ($odesc.constraint & $odesc.rm)
    elif odesc.constraint == asmInputOutput:
      outOperands.add ($odesc.constraint & $odesc.rm)
      inOutOperands.add odesc.tempId
    else:
      error " Unsupported Constraint: " & $odesc.constraint # Clobbered register

    for (memIndirect, len) in odesc.memClobbered:
      # TODO: precise clobbering.
      # Clang complain about impossible constraints or reaching coloring depth
      # when we do precise constraints for pointer indirect accesses

      # the Poly1305 MAC test fails without mem clobbers
      if memIndirect != memRead:
        memClobbered = true
        break

  for opDesc in a.outOperands:
    if constraint.len != 0:
      constraints &= ','
    if opDesc.constraint == asmInputOutput:
      constraints &= "=&"
      constraints &= $opDesc.rm
    else:
      constraints &= $opDesc.constraint
      constraints &= $opDesc.rm

    if not memClobbered:
      for (memIndirect, len) in odesc.memClobbered:
        # TODO: precise clobbering.
        # Clang complain about impossible constraints or reaching coloring depth
        # when we do precise constraints for pointer indirect accesses

        # the Poly1305 MAC test fails without mem clobbers
        if memIndirect != memRead:
          memClobbered = true
          break

  for opDesc in a.inOperands:
    constraints &= $opDesc.rm

  for opDesc in a.inOutOperands:
    constraints &= $.desc.asmId

  var params: string
  params.add outOperands.foldl(a & "," & b)
  params.add inOperands.foldl(a & "," & b)
  params.add inOutOperands.foldl(a & "," & b)

  let clobbers = [(memClobbered, "~{memory}")]
  for (clobbered, str) in clobbers:
    if clobbered:
      params.add "," & str

  for reg in a.regClobbers:
    params.add ",~{" & str & '}'

  var asmStmt = "\"" & a.code.replace("\n", "\0A")
  asmStmt.setLen(asmStmt.len - 1) # drop the last quote

func getStrOffset(a: Assembler_arm64, op: Operand, force32IfReg = false): string =
  # force32IfReg forces uses of 32-bit registers (memory operand are not changed)

  if op.kind != kFromArray:
    if op.kind in {kArrayAddr, k2dArrayAddr}:
      # We are operating on an array pointer
      # instead of array elements
      if op.buf[0].desc.constraint == asmClobberedRegister:
        return op.buf[0].desc.asmId
      else:
        return "%" & op.buf[0].desc.tempId
    elif op.kind == kRegister:
      if force32IfReg:
        return "%w" & op.desc.tempId
      else:
        return "%" & op.desc.tempId
    else:
      error "Unsupported: " & $op.kind

  if op.desc.rm in {Mem, MemOffsettable}:
    # Directly accessing memory
    # We cannot generate displacements in inline assembly memory operands
    error "Memory operand aren't supported for ARM64"

  elif op.desc.rm == PointerInReg or
       (op.desc.rm == ElemsInReg and op.kind == kFromArray):
    if op.offset == 0:
      return "[%" & op.desc.tempId & ']'
    return "[%" & op.desc.tempId & ", #" & $(op.offset * a.wordSize) & ']'
  elif op.desc.rm == ClobberedReg: # Array in clobbered register
    if op.offset == 0:
      return "[" & op.desc.tempId & ']'
    return "[" & op.desc.tempId & ", #" & $(op.offset * a.wordSize) & ']'
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

func codeFragment(a: var Assembler_arm64, instr: string, reg: Register, op: Operand) =
  # Generate a code fragment
  let off = a.getStrOffset(op)

  a.code &= instr & " " & $reg & ", " & off & '\n'

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

  a.code &= instr & " " & off0 & ", " & off1 & ", %" & $op2.tempId & '\n'

  if op0.desc.constraint != asmClobberedRegister:
    a.operands.incl op0.desc
  if op1.desc.constraint != asmClobberedRegister:
    a.operands.incl op1.desc

func codeFragment(a: var Assembler_arm64, instr: string, op: Operand, cc: ConditionCode) =
  # Generate a code fragment
  let off = a.getStrOffset(op)

  a.code &= instr & " " & off & ", " & $cc & '\n'

  if op.desc.constraint != asmClobberedRegister:
    a.operands.incl op.desc

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

  a.code &= instr & " %" & $op.tempId & ", " & $reg0 & ", " & $reg1 & '\n'

  if reg0 != xzr:
    a.regClobbers.incl reg0
  if reg1 != xzr:
    a.regClobbers.incl reg1

func codeFragment(a: var Assembler_arm64, instr: string, dst: Register, lhs: Operand, rhs: Register) =
  # Generate a code fragment
  let lhs_off = a.getStrOffset(lhs)

  a.code &= instr & " " & $dst & ", " & lhs_off & ", " & $rhs & '\n'

  if dst != xzr:
    a.regClobbers.incl dst
  if lhs.desc.constraint != asmClobberedRegister:
    a.operands.incl lhs.desc
  if rhs != xzr:
    a.regClobbers.incl rhs

func codeFragment(a: var Assembler_arm64, instr: string, dst: Register, lhs: OperandReuse, rhs: Register) =
  # Generate a code fragment

  a.code &= instr & " " & $dst & ", %" & $lhs.tempId & ", " & $rhs & '\n'

  if dst != xzr:
    a.regClobbers.incl dst
  if rhs != xzr:
    a.regClobbers.incl rhs

func reuseRegister*(reg: OperandArray): OperandReuse =
  doAssert reg.buf[0].desc.constraint in {asmInputOutput, asmInputOutputEarlyClobber}
  result.tempId = reg.buf[0].desc.tempId

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

func str*(a: var Assembler_arm64, src: Register, dst: Operand) =
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

func sbcs*(a: var Assembler_arm64, dst: Register, lhs: Operand, rhs: Register) =
  ## Subtraction with borrow (set carry flag):
  ##   (borrow, dst) <- lhs - rhs - borrow
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

func cset*(a: var Assembler_arm64, dst: Operand, cc: ConditionCode) =
  ## Store a condition code in a register
  doAssert dst.isOutput(), $dst.repr
  a.codeFragment("cset", dst, cc)

func `and`*(a: var Assembler_arm64, dst: Operand, lhs: Operand, rhs: OperandReuse) =
  a.codeFragment("and", dst, lhs, rhs)

func mov*(a: var Assembler_arm64, dst: Operand, src: Register) =
  a.codeFragment("mov", dst, src)