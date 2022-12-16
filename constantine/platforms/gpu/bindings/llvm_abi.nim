# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./utils

{.passc: gorge("llvm-config --cflags").}
{.passl: gorge("llvm-config --libs").}

const libLLVM = gorge("llvm-config --libnames")
static: echo "[Constantine] Using library " & libLLVM

# ############################################################
#
#                 Bindings to LLVM JIT
#
# ############################################################

# https://llvm.org/doxygen/group__LLVMC.html

# Constantine is a library. It is possible that applications relying on Constantine
# also link to libLLVM, for example if they implement a virtual machine (for the EVM, for Snarks/zero-knowledge, ...).
# Hence Constantine should always use LLVM context to "namespace" its own codegen and avoid collisions in the global context.

{.push used, hint[Name]: off, cdecl, dynlib: libLLVM.}

# ############################################################
#
#                         LLVM
#
# ############################################################

type
  LlvmBool = distinct int32
  MemoryBufferRef = distinct pointer
  ContextRef* = distinct pointer
  ModuleRef* = distinct pointer
  TargetRef* = distinct pointer
  ExecutionEngineRef* = distinct pointer
  TypeRef* = distinct pointer
  ValueRef* = distinct pointer
  MetadataRef = distinct pointer
  LLVMstring = distinct cstring
    ## A string with a buffer owned by LLVM

# <llvm-c/Core.h>

proc createContext*(): ContextRef {.importc: "LLVMContextCreate".}
proc dispose*(ctx: ContextRef) {.importc: "LLVMContextDispose".}

proc dispose(msg: LLVMstring) {.importc: "LLVMDisposeMessage".}
  ## cstring in LLVM are owned by LLVM and must be destroyed with a specific function
proc dispose(buf: MemoryBufferRef){.importc: "LLVMDisposeMemoryBuffer".}
proc getBufferStart(buf: MemoryBufferRef): ptr byte {.importc: "LLVMGetBufferStart".}
proc getBufferSize(buf: MemoryBufferRef): csize_t {.importc: "LLVMGetBufferSize".}

# ############################################################
#
#                         Module
#
# ############################################################

# {.push header: "<llvm-c/Core.h>".}

proc createModule(name: cstring, ctx: ContextRef): ModuleRef {.importc: "LLVMModuleCreateWithNameInContext".}
proc dispose*(m: ModuleRef) {.importc: "LLVMDisposeModule".}
  ## Destroys a module
  ## Note: destroying an Execution Engine will also destroy modules attached to it
proc toIR_LLVMstring(m: ModuleRef): LLVMstring {.used, importc: "LLVMPrintModuleToString".}
  ## Print a module IR to textual IR string. The string must be disposed with LLVM "dispose" or memory will leak.
proc getContext*(m: ModuleRef): ContextRef {.importc: "LLVMGetModuleContext".}

proc addNamedMetadataOperand*(m: ModuleRef, name: cstring, val: ValueRef) {.importc: "LLVMAddNamedMetadataOperand".}
proc metadataNode*(ctx: ContextRef, metadataNodes: openArray[MetadataRef]): MetadataRef {.wrapOpenArrayLenType: csize_t, importc: "LLVMMDNodeInContext2".}
proc metadataNode*(ctx: ContextRef, str: openArray[char]): MetadataRef {.wrapOpenArrayLenType: csize_t, importc: "LLVMMDStringInContext2".}
proc asMetadataRef*(val: ValueRef): MetadataRef {.importc: "LLVMValueAsMetadata".}
proc asValueRef*(ctx: ContextRef, md: MetadataRef): ValueRef {.importc: "LLVMMetadataAsValue".}

# <llvm-c/BitWriter.h>
proc writeBitcodeToFile*(m: ModuleRef, path: cstring) {.importc: "LLVMWriteBitcodeToFile".}
proc writeBitcodeToMemoryBuffer*(m: ModuleRef): MemoryBufferRef {.importc: "LLVMWriteBitcodeToMemoryBuffer".}
  ## Write bitcode to a memory buffer
  ## The MemoryBuffer must be disposed appropriately or memory will leak

type VerifierFailureAction* {.size: sizeof(cint).} = enum
  AbortProcessAction # verifier will print to stderr and abort()
  PrintMessageAction # verifier will print to stderr and return 1
  ReturnStatusAction # verifier will just return 1

# {.push header: "<llvm-c/Analysis.h>".}
proc verify(module: ModuleRef, failureAction: VerifierFailureAction, msg: var LLVMstring): LlvmBool {.used, importc: "LLVMVerifyModule".}

# ############################################################
#
#                         Target
#
# ############################################################

# "<llvm-c/Target.h>"

# The following procedures:
# - initializeNativeTarget()
# - initializeNativeAsmPrinter()
# are implemented in the development header macros and aren't in the LLVM library
# We want to only depend on the runtime for installation ease and size. 
#
# We can emulate the calls based on:
# - /usr/include/llvm-c/Target.h
# - /usr/include/llvm/Config/llvm-config-64.h

# proc initializeNativeTarget*(): LlvmBool {.discardable, importc: "LLVMInitializeNativeTarget".}
# proc initializeNativeAsmPrinter*(): LlvmBool {.discardable, importc: "LLVMInitializeNativeAsmPrinter".}

proc initializeX86AsmPrinter() {.importc: "LLVMInitializeX86AsmPrinter".}
proc initializeX86Target() {.importc: "LLVMInitializeX86Target".}
proc initializeX86TargetInfo() {.importc: "LLVMInitializeX86TargetInfo".}
proc initializeX86TargetMC() {.importc: "LLVMInitializeX86TargetMC".}

proc getTargetFromName*(name: cstring): TargetRef {.importc: "LLVMGetTargetFromName".}

# {.push header: "<llvm-c/Core.h>".}
proc setTarget*(module: ModuleRef, triple: cstring) {.importc: "LLVMSetTarget".}
proc setDataLayout*(module: ModuleRef, layout: cstring) {.importc: "LLVMSetDataLayout".}

# ############################################################
#
#                    Execution Engine
#
# ############################################################

# "<llvm-c/ExecutionEngine.h>"
proc createJITCompilerForModule(
       engine: var ExecutionEngineRef,
       module: ModuleRef,
       optLevel: uint32,
       err: var LLVMstring): LlvmBool {.used, importc: "LLVMCreateJITCompilerForModule".}
proc dispose*(engine: ExecutionEngineRef) {.importc: "LLVMDisposeExecutionEngine".}
  ## Destroys an execution engine
  ## Note: destroying an Execution Engine will also destroy modules attached to it
proc getFunctionAddress*(engine: ExecutionEngineRef, name: cstring): distinct pointer {.importc: "LLVMGetFunctionAddress".}

# ############################################################
#
#                         Types
#
# ############################################################

# https://llvm.org/doxygen/group__LLVMCCoreType.html

type
  TypeKind* {.size: sizeof(cint).} = enum
    tkVoid,           ## type with no size
    tkHalf,           ## 16 bit floating point type
    tkFloat,          ## 32 bit floating point type
    tkDouble,         ## 64 bit floating point type
    tkX86_FP80,       ## 80 bit floating point type (X87)
    tkFP128,          ## 128 bit floating point type (112-bit mantissa)
    tkPPC_FP128,      ## 128 bit floating point type (two 64-bits)
    tkLabel,          ## Labels
    tkInteger,        ## Arbitrary bit width integers
    tkFunction,       ## Functions
    tkStruct,         ## Structures
    tkArray,          ## Arrays
    tkPointer,        ## Pointers
    tkVector,         ## Fixed width SIMD vector type
    tkMetadata,       ## Metadata
    tkX86_MMX,        ## X86 MMX
    tkToken,          ## Tokens
    tkScalableVector, ## Scalable SIMD vector type
    tkBFloat,         ## 16 bit brain floating point type
    tkX86_AMX         ## X86 AMX

# header: "<llvm-c/Core.h>"

proc getTypeKind*(ty: TypeRef): TypeKind {.importc: "LLVMGetTypeKind".}
proc toLLVMstring(ty: TypeRef): LLVMstring {.used, importc: "LLVMPrintTypeToString".}

proc void_t*(ctx: ContextRef): TypeRef {.importc: "LLVMVoidTypeInContext".}

# Integers
# ------------------------------------------------------------
proc int1_t*(ctx: ContextRef): TypeRef {.importc: "LLVMInt1TypeInContext".}
proc int8_t*(ctx: ContextRef): TypeRef {.importc: "LLVMInt8TypeInContext".}
proc int16_t*(ctx: ContextRef): TypeRef {.importc: "LLVMInt16TypeInContext".}
proc int32_t*(ctx: ContextRef): TypeRef {.importc: "LLVMInt32TypeInContext".}
proc int64_t*(ctx: ContextRef): TypeRef {.importc: "LLVMInt64TypeInContext".}
proc int128_t*(ctx: ContextRef): TypeRef {.importc: "LLVMInt128TypeInContext".}
proc int_t*(ctx: ContextRef, numBits: uint32): TypeRef {.importc: "LLVMIntTypeInContext".}

# Composite
# ------------------------------------------------------------
proc struct_t*(
       ctx: ContextRef,
       elemTypes: openArray[TypeRef],
       packed: LlvmBool): TypeRef {.wrapOpenArrayLenType: cuint, importc: "LLVMStructTypeInContext".}
proc array_t*(elemType: TypeRef, elemCount: uint32): TypeRef {.importc: "LLVMArrayType".}

proc pointerType(elementType: TypeRef; addressSpace: cuint): TypeRef {.used, importc: "LLVMPointerType".}

# Functions
# ------------------------------------------------------------
proc function_t*(
       returnType: TypeRef,
       paramTypes: openArray[TypeRef],
       isVarArg: LlvmBool): TypeRef {.wrapOpenArrayLenType: cuint, importc: "LLVMFunctionType".}

proc addFunction*(m: ModuleRef, name: cstring, ty: TypeRef): ValueRef {.importc: "LLVMAddFunction".}
  ## Declare a function `name` in a module.
  ## Returns a handle to specify its instructions

# TODO: Function and Parameter attributes:
# - https://www.llvm.org/docs/LangRef.html?highlight=attribute#function-attributes
# - https://www.llvm.org/docs/LangRef.html?highlight=attribute#parameter-attributes
#
# We can use attributes to specify additional guarantees of Constantine code, for instance:
# - "pure" function with: nounwind, readonly
# - pointer particularities: readonly, writeonly, noalias, inalloca, byval

proc getReturnType*(functionTy: TypeRef): TypeRef {.importc: "LLVMGetReturnType".}

# ############################################################
#
#                         Values
#
# ############################################################

# {.push header: "<llvm-c/Core.h>".}

proc getTypeOf*(x: ValueRef): TypeRef {.importc: "LLVMTypeOf".}

# Constants
# ------------------------------------------------------------
# https://llvm.org/doxygen/group__LLVMCCoreValueConstant.html

proc constInt(ty: TypeRef, n: culonglong, signExtend: LlvmBool): ValueRef {.importc: "LLVMConstInt".}
proc constReal*(ty: TypeRef, n: cdouble): ValueRef {.importc: "LLVMConstReal".}

proc constNull*(ty: TypeRef): ValueRef {.importc: "LLVMConstNull".}
proc constAllOnes*(ty: TypeRef): ValueRef {.importc: "LLVMConstAllOnes".}
proc constStruct(
       constantVals: openArray[ValueRef],
       packed: LlvmBool): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMConstStruct".}
proc constArray*(
       ty: TypeRef,
       constantVals: openArray[ValueRef],
    ): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMConstArray".}

# ############################################################
#
#                      IR builder
#
# ############################################################

# https://llvm.org/doxygen/group__LLVMCCoreInstructionBuilder.html

type
  BasicBlockRef* = distinct pointer
  BuilderRef* = distinct pointer
    ##  An instruction builder represents a point within a basic block and is
    ##  the exclusive means of building instructions using the C interface.

  IntPredicate* {.size: sizeof(cint).} = enum
    IntEQ = 32,               ## equal
    IntNE,                    ## not equal
    IntUGT,                   ## unsigned greater than
    IntUGE,                   ## unsigned greater or equal
    IntULT,                   ## unsigned less than
    IntULE,                   ## unsigned less or equal
    IntSGT,                   ## signed greater than
    IntSGE,                   ## signed greater or equal
    IntSLT,                   ## signed less than
    IntSLE                    ## signed less or equal

# "<llvm-c/Core.h>"

# Instantiation
# ------------------------------------------------------------

proc appendBasicBlock*(ctx: ContextRef, fn: ValueRef, name: cstring): BasicBlockRef {.importc: "LLVMAppendBasicBlockInContext".}
  ## Append a basic block to the end of a function

proc createBuilder*(ctx: ContextRef): BuilderRef {.importc: "LLVMCreateBuilderInContext".}
proc dispose*(builder: BuilderRef) {.importc: "LLVMDisposeBuilder".}

# Functions
# ------------------------------------------------------------

proc getParam*(fn: ValueRef, index: uint32): ValueRef {.importc: "LLVMGetParam".}
proc retVoid*(builder: BuilderRef): ValueRef {.importc: "LLVMBuildRetVoid".}
proc ret*(builder: BuilderRef, returnVal: ValueRef) {.importc: "LLVMBuildRet".}

# Positioning
# ------------------------------------------------------------

proc position*(builder: BuilderRef, blck: BasicBlockRef, instr: ValueRef) {.importc: "LLVMPositionBuilder".}
proc positionBefore*(builder: BuilderRef, instr: ValueRef) {.importc: "LLVMPositionBuilderBefore".}
proc positionAtEnd*(builder: BuilderRef, blck: BasicBlockRef) {.importc: "LLVMPositionBuilderAtEnd".}

# Intermediate Representation
# ------------------------------------------------------------
# 
# - NSW: no signed wrap, signed value cannot over- or underflow.
# - NUW: no unsigned wrap, unsigned value cannot over- or underflow.

proc add*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildAdd".}
proc addNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNSWAdd".}
proc addNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNUWAdd".}

proc sub*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildSub".}
proc subNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNSWSub".}
proc subNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNUWSub".}

proc neg*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNeg".}
proc negNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNSWNeg".}
proc negNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNUWNeg".}

proc mul*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildMul".}
proc mulNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNSWMul".}
proc mulNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNUWMul".}

proc divU*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildUDiv".}
proc divU_exact*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildExactUDiv".}
proc divS*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildSDiv".}
proc divS_exact*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildExactSDiv".}
proc remU*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildURem".}
proc remS*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildSRem".}

proc lshl*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildShl".}
proc lshr*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildLShr".}
proc ashr*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildAShr".}

proc `and`*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildAnd".}
proc `or`*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildOr".}
proc `xor`*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildXor".}
proc `not`*(builder: BuilderRef, val: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNot".}
proc select*(builder: BuilderRef, condition, then, otherwise: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildNot".}

proc icmp*(builder: BuilderRef, op: IntPredicate, lhs, rhs: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildICmp".}

proc bitcast*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring) {.importc: "LLVMBuildBitcast".}
proc trunc*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring) {.importc: "LLVMBuildTrunc".}
proc zext*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring) {.importc: "LLVMBuildZExt".}
  ## Zero-extend
proc sext*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring) {.importc: "LLVMBuildSExt".}
  ## Sign-extend

proc malloc*(builder: BuilderRef, ty: TypeRef): ValueRef {.importc: "LLVMBuildMalloc".}
proc mallocArray*(builder: BuilderRef, ty: TypeRef, val: ValueRef): ValueRef {.importc: "LLVMBuildMallocArray".}
proc free*(builder: BuilderRef, ty: TypeRef, `ptr`: ValueRef): ValueRef {.importc: "LLVMBuildFree".}
proc alloca*(builder: BuilderRef, ty: TypeRef): ValueRef {.importc: "LLVMBuildAlloca".}
proc allocaArray*(builder: BuilderRef, ty: TypeRef, val: ValueRef): ValueRef {.importc: "LLVMBuildAllocaArray".}

proc getElementPtr2*(
       builder: BuilderRef,
       ty: TypeRef,
       `ptr`: ValueRef,
       indices: openArray[ValueRef],
       name: cstring
     ): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMBuildGEP2".}
  ## https://www.llvm.org/docs/GetElementPtr.html
proc getElementPtr2_InBounds*(
       builder: BuilderRef,
       ty: TypeRef,
       `ptr`: ValueRef,
       indices: openArray[ValueRef],
       name: cstring
     ): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMBuildInBoundsGEP2".}
  ## https://www.llvm.org/docs/GetElementPtr.html
  ## If the GEP lacks the inbounds keyword, the value is the result from evaluating the implied two’s complement integer computation.
  ## However, since there’s no guarantee of where an object will be allocated in the address space, such values have limited meaning.
proc getElementPtr2_Struct*(
       builder: BuilderRef,
       ty: TypeRef,
       `ptr`: ValueRef,
       idx: uint32,
       name: cstring
     ): ValueRef {.importc: "LLVMBuildStructGEP2".}
  ## https://www.llvm.org/docs/GetElementPtr.html
  ## If the GEP lacks the inbounds keyword, the value is the result from evaluating the implied two’s complement integer computation.
  ## However, since there’s no guarantee of where an object will be allocated in the address space, such values have limited meaning.

proc load2*(builder: BuilderRef, ty: TypeRef, `ptr`: ValueRef, name: cstring): ValueRef {.importc: "LLVMBuildLoad2".}
proc store*(builder: BuilderRef, val, `ptr`: ValueRef): ValueRef {.importc: "LLVMBuildStore".}

proc memset*(builder: BuilderRef, `ptr`, val, len: ValueRef, align: uint32) {.importc: "LLVMBuildMemset".}
proc memcpy*(builder: BuilderRef, dst: ValueRef, dstAlign: uint32, src: ValueRef, srcAlign: uint32, size: ValueRef) {.importc: "LLVMBuildMemcpy".}
proc memmove*(builder: BuilderRef, dst: ValueRef, dstAlign: uint32, src: ValueRef, srcAlign: uint32, size: ValueRef) {.importc: "LLVMBuildMemmove".}

{.pop.} # {.used, hint[Name]: off, cdecl, dynlib: libLLVM.}
