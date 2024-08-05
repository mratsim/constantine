# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[macros, strutils],
  constantine/platforms/llvm/llvm

# ############################################################
#
#                   x86 Inline ASM
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
      let `ctx` = builder.getContext()
      # lhs: ValueRef or uint32 or uint64
      let `numBits` = when `lhs` is ValueRef|ConstValueRef: `lhs`.getTypeOf().getIntTypeWidth()
                      else: 8*sizeof(`lhs`)
      let `regTy` = when `lhs` is ValueRef|ConstValueRef: `lhs`.getTypeOf()
                    elif `lhs` is uint32: `ctx`.int32_t()
                    elif `lhs` is uint64: `ctx`.int64_t()
                    else: {.error "Unsupported input type " & $typeof(`lhs`).}

    # 2. Create the LLVM asm signature
    let operands = op[2][0][3]
    let arity = operands.len

    let constraintString = op[2][0][2]
    let constraints = ident"constraints"

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
        # We only support out of place "=" function.
        # In-place with "+" requires alloca + load/stores in codegen
        # in-place functions can be rewritten to be out-place with "matching constraints"
        error "Unsupported constraint: " & constraintString.strVal
    else:
      error "Unsupported arity: " & $arity

    # 3. Nothing, we can use the constraint string as is on x86

    # 4. Register the inline ASM with LLVM
    let inlineASM = ident"inlineASM"
    let instrParam = op[2][0][1]
    let asmString = ident"asmString"


    instrBody.add quote do:
      let `asmString` = if `numBits` == 64: static(`instr` & "q") & static(" " & `instrParam`)
                        else: static(`instr` & "l") & static(" " & `instrParam`)

    instrBody.add quote do:
      let `inlineASM` = getInlineAsm(
        ty = `fnTy`,
        asmString = `asmString`,
        constraints = `constraintString`,
        # All carry/overflow instructions have sideffect on carry flag and can't be reordered
        # However, function calls can't be reordered.
        # Relevant operations that affects flags are:
        # - MUL, if the compiler decides not to use MULX
        # - XOR, for zeroing a register
        hasSideEffects = LlvmBool(0),
        isAlignStack = LlvmBool(0),
        dialect = InlineAsmDialectATT,
        canThrow = LlvmBool(0))

    # 5. Call it
    let opArray = nnkBracket.newTree()
    for op in operands:
      # when op is ValueRef: op
      # else: constInt(uint64(op))
      opArray.add newCall(
        bindSym"ValueRef",
        nnkWhenStmt.newTree(
          nnkElifBranch.newTree(nnkInfix.newTree(ident"is", op, bindSym"AnyValueRef"), op),
          nnkElse.newTree(newCall(ident"constInt", regTy, newCall(ident"uint64", op)))
        )
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
              nnkInfix.newTree(ident"or", ident"AnyValueRef", ident"uint32"),
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

# Inline x86 assembly
# ------------------------------------------------------------
#
# We can generate add with carry via
#   call { i8, i64 } @llvm.x86.addcarry.64(i8 %carryIn, i64 %a, i64 %b)
#
# We can generate multi-precision mul and mulx via
#
#    define {i64, i64} @mul(i64 %x, i64 %y) #0 {
#
#      %1 = zext i64 %x to i128
#      %2 = zext i64 %y to i128
#      %r = mul i128 %1, %2
#      %3 = zext i32 64 to i128
#      %4 = lshr i128 %r, %3
#      %hi = trunc i128 %4 to i64
#      %lo = trunc i128 %r to i64
#
#      %res_tmp = insertvalue {i64, i64} undef, i64 %hi, 0
#      %res = insertvalue {i64, i64} %res_tmp, i64 %lo, 1
#
#      ret {i64, i64} %res
#    }
#
#    attributes #0 = {"target-features"="+bmi2"}
#
#    mul:
#            mov     rax, rdi
#            mul     rsi
#            mov     rcx, rax
#            mov     rax, rdx
#            mov     rdx, rcx
#            ret
#
#    mul_bmi2:
#        mov     rdx, rdi
#        mulx    rax, rdx, rsi
#        ret
#
# Note that mul(hi: var rdx, lo: var rax, a: reg/mem64, b: rax)
#   - clobbers carry (and many other) flags
#   - has fixed output to rdx:rax registers
# while mulx(hi: var reg64, lo: var reg64, a: reg/mem64, b: rdx)
#   - does not clobber flags
#   - has flexible register outputs


genInstr():
  # We are only concerned about the ADCX/ADOX instructions
  # which do not have intrinsics or cannot be generated through instruction combining
  # unlike llvm.x86.addcarry.u64 that can generate adc

  # (cf/of, r) <- a+b+(cf/of)
  op adcx_rr: ("adcx", "%2, %0;", "=r,%0,r", [lhs, rhs])
  op adcx_rm: ("adcx", "%2, %0;", "=r,0,m", [lhs, rhs])
  op adox_rr: ("adox", "%2, %0;", "=r,%0,r", [lhs, rhs])
  op adox_rm: ("adox", "%2, %0;", "=r,0,m", [lhs, rhs])
