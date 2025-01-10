# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[macros, strutils],
  ./llvm

# ############################################################
#
#                   ARM64 Inline ASM
#
# ############################################################

macro genInstr(body: untyped): untyped =
  result = newStmtList()

  body.expectKind(nnkStmtList)
  for op in body:
    op.expectKind(nnkCommand)
    doAssert op[0].eqIdent"op"

    let instrName = op[1]
    # For each op, generate a builder proc
    op[2][0].expectKind(nnkTupleConstr)
    op[2][0][0].expectKind(nnkStrLit)
    op[2][0][1].expectKind(nnkStrLit)
    op[2][0][2].expectKind(nnkStrLit)
    op[2][0][3].expectKind(nnkBracket)

    let instrBody = newStmtList()

    # 1. Detect the size of registers
    let numBits = ident"numBits"
    let regTy = ident"regTy"
    let fnTy = ident"fnTy"
    let ctx = ident"ctx"
    let lhs = op[2][0][3][0]

    instrBody.add quote do:
      let `ctx` {.used.} = builder.getContext()
      # lhs: ValueRef or uint32 or uint64
      let `numBits` = when `lhs` is ValueRef: `lhs`.getTypeOf().getIntTypeWidth()
                      else: 8*sizeof(`lhs`)
      let `regTy` = when `lhs` is ValueRef: `lhs`.getTypeOf()
                    elif `lhs` is uint32: `ctx`.int32_t()
                    elif `lhs` is uint64: `ctx`.int64_t()
                    else: {.error "Unsupported input type " & $typeof(`lhs`).}

    # 2. Create the LLVM asm signature
    let operands = op[2][0][3]
    let arity = operands.len

    let constraintString = op[2][0][2]
    let instr = op[2][0][0]

    if arity == 2:
      if constraintString.strVal.startsWith('='):
        if constraintString.strVal.endsWith('r'):
          instrBody.add quote do:
            let `fnTy` = function_t(`regTy`, [`regTy`, `regTy`])
        else:
          instrBody.add quote do:
            let `fnTy` = function_t(`regTy`, [`regTy`, pointer_t(`regTy`)])
      else:
        # We only support out of place "=" instructions.
        # In-place with "+" requires alloca + load/stores in codegen
        # in-place functions can be rewritten to be out-place with "matching constraints"
        error "Unsupported constraint: " & constraintString.strVal
    else:
      error "Unsupported arity: " & $arity

    # 3. Nothing, we can use the constraint string as is on ARM64

    # 4. Register the inline ASM with LLVM
    let inlineASM = ident"inlineASM"
    let instrParam = op[2][0][1]
    let asmString = ident"asmString"

    instrBody.add quote do:
      let `asmString` = `instr` & static(" " & `instrParam`)

    instrBody.add quote do:
      # Chapter 6 of https://docs.nvidia.com/cuda/pdf/NVVM_IR_Specification.pdf
      # inteldialect is not supported (but the NVPTX dialect is akin to intel dialect)

      let `inlineASM` = getInlineAsm(
        ty = `fnTy`,
        asmString = `asmString`,
        constraints = `constraintString`,
        # All carry instructions have sideffect on carry flag and can't be reordered
        hasSideEffects = LlvmBool(1),
        isAlignStack = LlvmBool(0),
        dialect = InlineAsmDialectATT,
        canThrow = LlvmBool(0))

    # 5. Call it
    let opArray = nnkBracket.newTree()
    for op in operands:
      # when op is ValueRef: op
      # else: constInt(uint64(op))
      opArray.add nnkWhenStmt.newTree(
          nnkElifBranch.newTree(nnkInfix.newTree(ident"is", op, bindSym"ValueRef"), op),
          nnkElse.newTree(newCall(ident"constInt", regTy, newCall(ident"uint64", op)))
        )
    # builder.call2(ty, inlineASM, [lhs, rhs], name)
    instrBody.add newCall(
      ident"call2", ident"builder", fnTy,
      inlineASM, opArray, ident"name")

    # 6. Create the function signature
    var opDefs: seq[NimNode]
    opDefs.add ident"ValueRef" # Return type
    opDefs.add newIdentDefs(ident"builder", bindSym"BuilderRef")
    block:
      var i = 0
      for constraint in constraintString.strVal.split(','):
        if constraint.startsWith('=') or constraint.startsWith("~{memory}"):
          # Don't increment i
          continue
        elif constraint == "m":
          opDefs.add newIdentDefs(operands[i], ident"ValueRef")
        elif constraint.endsWith('r') or constraint.endsWith('0'):
          opDefs.add newIdentDefs(
            operands[i],
            nnkInfix.newTree(ident"or",
              nnkInfix.newTree(ident"or", ident"ValueRef", ident"uint32"),
              ident"uint64")
          )
        else:
          error "Unsupported constraint: " & constraint
        i += 1
    opDefs.add newIdentDefs(ident"name", bindSym"cstring", newLit"")

    result.add newProc(
      name = nnkPostfix.newTree(ident"*", instrName),
      params = opDefs,
      procType = nnkProcDef,
      body = instrBody)

# Inline ARM64 assembly
# ------------------------------------------------------------
genInstr():
  # r <- a+b
  op arm64_add_co:       ("adds",       "$0, $1, $2;",     "=r,r,r",   [lhs, rhs])
  op arm64_add_ci:       ("adc",        "$0, $1, $2;",     "=r,r,r",   [lhs, rhs])
  op arm64_add_cio:      ("adcs",       "$0, $1, $2;",     "=r,r,r",   [lhs, rhs])
  # r <- a-b
  # Note that subs/sbcs that don't borrow will set the carry flag,
  # it is inverted compared to LLVM, Nvidia or X86 semantics (6502 works similarly)
  op arm64_sub_bo:       ("subs",       "$0, $1, $2;",     "=r,r,r",   [lhs, rhs])
  op arm64_sub_bi:       ("sbc",        "$0, $1, $2;",     "=r,r,r",   [lhs, rhs])
  op arm64_sub_bio:      ("sbcs",       "$0, $1, $2;",     "=r,r,r",   [lhs, rhs])

  # Conditional mov / select
  # csel, carry clear
  op arm64_csel_cc:      ("csel",       "$0, $1, $2, cc;", "=r,r,r", [ifPos, ifNeg])

  