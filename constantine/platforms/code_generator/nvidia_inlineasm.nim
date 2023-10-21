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
#                   Nvidia Inline ASM
#
# ############################################################

# We want to generate procedures related to the following
# instructions -> inline assembly -> argument mapping

# Inline assembly looks like this:
#
# C:    asm volatile ("add.cc.u64 %0, %1, %2;" : "=l"(c) : "l"(a), "l"(b) : "memory" );
# LLVM: call i64 asm "add.cc.u64 $0, $1, $2;", "=l,l,l,~{memory}"(i64 %1, i64 %2)
#
# So we need to do the following steps
#
# 1. Collect inline ASM opcodes definition for Nvidia PTX inline assembly
# 2. Generate u32 and u64 `getInlineAsm()` definition (that is associated with an LLVM IR ContextRef)
# 3. Create an initialization proc to be called after initializing the LLVM ContextRef
#    For each instruction, return a routine with signature that mirrors LLVM builtin instructions:
#
#    proc myInstr(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef =
#      let numBits = lhs.getTypeOf().getIntTypeWidth()
#      if numBits == 32:
#        builder.call2(inlineAsmFnType, inlineAsmFn32, [arg0, arg1, ...], name)
#      elif numBits == 64:
#        builder.call2(inlineAsmFnType, inlineAsmFn64, [arg0, arg1, ...], name)
#      else:
#        doAssert false, "Unsupported int" & $numBits
#
# To create `inlineAsmFn32` and `inlineAsmFn64` we may use `getInlineAsm` just before the corresponding
# builder.call2. This allows us to define freestanding functions.
# The potential issue is the overhead of repeated definition of add/sub/mul/muladd
# and their carry-in, carry-out variations.
# LLVM internally ensures that only a single instance will be defined via a HashTable
# Though this will involve thousands of repeated hashing: https://llvm.org/doxygen/InlineAsm_8cpp_source.html#l00043
#
# Alternatively, we can cache the functions created and the design challenge is how to expose
# the routines with the same API as LLVM builder. We could use a global, a wrapper builder type,
# or a template to call at the beginning of each function that setups some boilerplate indirection.
#
# However caching only works if inlineAsmFn32 and inlineAsmFn64 are stable
# but it's very clunky in our case as a fused multiply-addfunction like
# mad.lo.u32 "%0, %1, %2, %3;" "=l,l,l,l" [lmul, rmul, addend]
# can also have immediate operand (a modulus for example) as constraint.
# So we don't cache and rely on LLVM own deduplication.

template selConstraint(operand: auto, append = ""): string =
  when operand is ValueRef:
    # PTX Assembly:
    # r for 32-bit operand
    # l for 64-bit operand
    # n for immediates
    if operand.getTypeOf().getIntTypeWidth() == 32:
      "r" & append
    else:
      "l" & append
  else: # ConstValueRef or uint32 or uint64
    "n" & append

macro genInstr(body: untyped): untyped =
  result = newStmtList()

  body.expectKind(nnkStmtList)
  for op in body:
    op.expectKind(nnkCommand)
    doAssert op[0].eqIdent"op"

    let instrName = op[1]
    # For each op, generate a builder proc
    op[2][0].expectKind(nnkTupleConstr)
    op[2][0][0].expectKind({nnkStrLit, nnkCurly})
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
    let hasTwoTypes = instr.kind == nnkCurly

    if hasTwoTypes:
      # For now only slct has 2 types so we special case to it
      instrBody.add quote do:
        let `fnTy` = function_t(`regTy`, [`regTy`, `regTy`, `ctx`.int32_t()])

    elif arity == 2:
      if constraintString.strVal.startsWith('='):
        instrBody.add quote do:
          let `fnTy` = function_t(`regTy`, [`regTy`, `regTy`])
      else:
        # We only support out of place "=" function.
        # In-place with "+" requires alloca + load/stores in codegen
        error "Unsupported constraint: " & constraintString.strVal
    elif arity == 3:
      if constraintString.strVal.startsWith('='):
        instrBody.add quote do:
          let `fnTy` = function_t(`regTy`, [`regTy`, `regTy`, `regTy`])
        # We only support out of place "=" function.
        # In-place with "+" requires alloca + load/stores in codegen
      else:
        error "Unsupported constraint: " & constraintString.strVal
    else:
      error "Unsupported arity: " & $arity

    # 3. Create the constraints string

    # We could have generic constraint string generation, but we only have 2 arities to support
    # and codegen without quote do would be even more verbose and hard to read.

    # TODO: commutative inputs
    if arity == 2:
      let op0 = operands[0]
      let op1 = operands[1]
      instrBody.add quote do:
        let `constraints` = block:
          var c: string
          let constraintRegisterSymbol =
            if `numBits` == 32: "r"
            else: "l"
          when `constraintString`.startsWith('='):
            c.add "=" & constraintRegisterSymbol & ','
            c.add selConstraint(`op0`,",")
            c.add selConstraint(`op1`)
          else:
            static: doAssert false, " Constraint misconfigured"
          when `constraintString`.endsWith(",~{memory}"):
            c.add ",~{memory}"
          c

    elif arity == 3:
      let op0 = operands[0]
      let op1 = operands[1]
      let op2 = operands[2]
      instrBody.add quote do:
        let `constraints` = block:
          var c: string
          let constraintRegisterSymbol =
            if `numBits` == 32: "r"
            else: "l"
          when `constraintString`.startsWith('='):
            c.add "=" & constraintRegisterSymbol & ','
            c.add selConstraint(`op0`,",")
            c.add selConstraint(`op1`, ",")
            c.add selConstraint(`op2`)
          else:
            static: doAssert false, " Constraint misconfigured"
          when `constraintString`.endsWith(",~{memory}"):
            c.add ",~{memory}"
          c

    else:
      error "Unsupported arity: " & $arity


    # 4. Register the inline ASM with LLVM
    let inlineASM = ident"inlineASM"
    let instrParam = op[2][0][1]
    let asmString = ident"asmString"

    if hasTwoTypes:
      # Only slct has 2 types, and it has to be s32, so there is no need to dynamically the type of the parameter at the moment
      let mnemo = instr[0]
      let type2 = instr[1]
      instrBody.add quote do:
        let `asmString` = static(`mnemo` & ".u") & $`numBits` & static(`type2` & " " & `instrParam`)
    else:
      instrBody.add quote do:
        let `asmString` = static(`instr` & ".u") & $`numBits` & static(" " & `instrParam`)

    instrBody.add quote do:
      # Chapter 6 of https://docs.nvidia.com/cuda/pdf/NVVM_IR_Specification.pdf
      # inteldialect is not supported (but the NVPTX dialect is akin to intel dialect)

      let `inlineASM` = getInlineAsm(
        ty = `fnTy`,
        asmString = `asmString`,
        constraints = `constraints`,
        # All carry instructions have sideffect on carry flag and can't be reordered
        # However, function calls can't be reordered and
        # by default on NVPTX load/stores, comparisons and arithmetic operations don't affect carry
        # flags so it's fine for the compiler to intersperse them.
        hasSideEffects = LlvmBool(0),
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
          nnkElifBranch.newTree(nnkInfix.newTree(ident"is", op, bindSym"ConstValueRef"), newCall(ident"ValueRef", op)),
          nnkElse.newTree(newCall(ident"ValueRef", newCall(ident"constInt", regTy, newCall(ident"uint64", op))))
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
        elif constraint == "rl":
          opDefs.add newIdentDefs(operands[i], ident"ValueRef")
        elif constraint == "rln":
          opDefs.add newIdentDefs(
            operands[i],
            nnkInfix.newTree(ident"or",
              nnkInfix.newTree(ident"or", ident"AnyValueRef", ident"uint32"),
              ident"uint64")
          )
        elif constraint == "rn":
          opDefs.add newIdentDefs(
            operands[i],
            nnkInfix.newTree(ident"or",
              ident"AnyValueRef",
              ident"uint32")
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

# Inline PTX assembly
# ------------------------------------------------------------
# See docs/implementation_nvidia_gpus.md for detailed implementation considerations
#
# Need Cuda 11.5.1 at least for madc.hi.u64:
# https://forums.developer.nvidia.com/t/wrong-result-returned-by-madc-hi-u64-ptx-instruction-for-specific-operands/196094
#
# The PTX compilation part is done by NVVM
# but NVVM version is not listed here: https://docs.nvidia.com/cuda/archive/11.5.1/cuda-toolkit-release-notes/index.html
# and nvvmVersion returns the IR version instead of the version of the compiler library.
# Alternatively we use LLVM NVPTX backend instead of Nvidia's NVVM.
#
# Nvidia manual
# ~~~~~~~~~~~~~
#
# https://docs.nvidia.com/cuda/inline-ptx-assembly/index.html#constraints
# There is a separate constraint letter for each PTX register type:
#
# "h" = .u16 reg
# "r" = .u32 reg
# "l" = .u64 reg
# "f" = .f32 reg
# "d" = .f64 reg
#
# The constraint "n" may be used for immediate integer operands with a known value.
#
#
# 1.2.3. Incorrect Optimization
#
# The compiler assumes that an asm() statement has no side effects except to change the output operands. To ensure that the asm is not deleted or moved during generation of PTX, you should use the volatile keyword, e.g.:
#
# asm volatile ("mov.u32 %0, %%clock;" : "=r"(x));
#
# Normally any memory that is written to will be specified as an out operand, but if there is a hidden side effect on user memory (for example, indirect access of a memory location via an operand), or if you want to stop any memory optimizations around the asm() statement performed during generation of PTX, you can add a “memory” clobbers specification after a 3rd colon, e.g.:
#
# asm volatile ("mov.u32 %0, %%clock;" : "=r"(x) :: "memory");
# asm ("st.u32 [%0], %1;" : "r"(p), "r"(x) :: "memory");
#
# Constantine implementation
# ~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# To encode the allowed constraints we use rl to allow the r and l constraints
# and we use rln to allow r and l constraints and n immediate.
#
# The asm volatile constraint is passed via `hasSideEffects` in getInlineAsm.
#
# For the memory constraint, it is specified the following way:
#
# C:    asm volatile ("add.cc.u64 %0, %1, %2;" : "=l"(c) : "l"(a), "l"(b) : "memory" );
# LLVM: call i64 asm "add.u64 $0, $1, $2;", "=l,l,l,~{memory}"(i64 %1, i64 %2)
#
# Instructions that use carries should not be reordered hence need volatile/hasSideEffect

genInstr():
  # The PTX is without size indicator i.e. add.cc instead of add.cc.u32
  # Both version will be generated.
  #
  # op name:       ("ptx",        "args;",            "constraints", [params])

  # r <- a+b
  op add_co:       ("add.cc",     "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  op add_ci:       ("addc",       "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  op add_cio:      ("addc.cc",    "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  # r <- a-b
  op sub_bo:       ("sub.cc",     "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  op sub_bi:       ("subc",       "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  op sub_bio:      ("subc.cc",    "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  # r <- a * b >> 32
  op mulhi:        ("mul.hi",     "$0, $1, $2;",     "=rl,rln,rln",   [lhs, rhs])
  # r <- a * b + c
  op mulloadd:     ("mad.lo",     "$0, $1, $2, $3;", "=rl,rln,rln,rln", [lmul, rmul, addend])
  op mulloadd_co:  ("mad.lo.cc",  "$0, $1, $2, $3;", "=rl,rln,rln,rln", [lmul, rmul, addend])
  op mulloadd_cio: ("madc.lo.cc", "$0, $1, $2, $3;", "=rl,rln,rln,rln", [lmul, rmul, addend])
  # r <- (a * b) >> 32 + c
  # r <- (a * b) >> 64 + c
  op mulhiadd:     ("mad.hi",     "$0, $1, $2, $3;", "=rl,rln,rln,rln", [lmul, rmul, addend])
  op mulhiadd_co:  ("mad.hi.cc",  "$0, $1, $2, $3;", "=rl,rln,rln,rln", [lmul, rmul, addend])
  op mulhiadd_cio: ("madc.hi.cc", "$0, $1, $2, $3;", "=rl,rln,rln,rln", [lmul, rmul, addend])

  # Conditional mov / select

  # slct r, a, b, c;
  # r <- (c >= 0) ? a : b;
  op slct:         ({"slct",".s32"},     "$0, $1, $2, $3;", "=rl,rln,rln,rn", [ifPos, ifNeg, condition])

  # selp is the classic select operation, however the selector `c` is of type "predicate"
  # and quoting the PTX ISA doc
  # https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#manipulating-predicates
  # > There is no direct conversion between predicates and integer values, and no direct way to load or store predicate register values. However, setp can be used to generate a predicate from an integer, and the predicate-based select (selp) instruction can be used to generate an integer value based on the value of a predicate; for example:
  # >     selp.u32 %r1,1,0,%p; 	// convert predicate to 32-bit value
  #
  # If selp is more practical than slct in some cases, then it's likely easier to use LLVM builtin IR trunc/icmp + select

  # selp r, a, b, c;
  # r <- (c == 1) ? a : b;
  # op selp:         ("selp",     "$0, $1, $2, $3;", "=rl,rln,rln,rln", [ifTrue, ifFalse, condition])

  # Alternatively, for conditional moves use-cases, we might want to use
  # 'setp' to set a predicate and then '@p mov' for predicated moves
