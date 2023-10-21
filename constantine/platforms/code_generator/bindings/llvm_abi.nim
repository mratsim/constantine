# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./c_abi

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

{.push noconv, dynlib: libLLVM.}

# ############################################################
#
#                         LLVM
#
# ############################################################

type
  LlvmBool = distinct int32
  ErrorRef = distinct pointer
  MemoryBufferRef = distinct pointer
  ContextRef* = distinct pointer
  ModuleRef* = distinct pointer
  TargetRef* = distinct pointer
  ExecutionEngineRef* = distinct pointer
  TargetMachineRef* = distinct pointer
  PassManagerRef* = distinct pointer
  PassManagerBuilderRef* = distinct pointer
  PassBuilderOptionsRef* = distinct pointer
  PassRegistryRef* = distinct pointer
  TypeRef* = distinct pointer
  ValueRef* = distinct pointer
  MetadataRef = distinct pointer
  LLVMstring = distinct cstring
  ErrorMessageString = distinct cstring
    ## A string with a buffer owned by LLVM

# <llvm-c/Core.h>

proc createContext*(): ContextRef {.importc: "LLVMContextCreate".}
proc dispose*(ctx: ContextRef) {.importc: "LLVMContextDispose".}

proc dispose(msg: LLVMstring) {.used, importc: "LLVMDisposeMessage".}
  ## cstring in LLVM are owned by LLVM and must be destroyed with a specific function
proc dispose(buf: MemoryBufferRef){.used, importc: "LLVMDisposeMemoryBuffer".}
proc getBufferStart(buf: MemoryBufferRef): ptr byte {.used, importc: "LLVMGetBufferStart".}
proc getBufferSize(buf: MemoryBufferRef): csize_t {.used, importc: "LLVMGetBufferSize".}

proc dispose(msg: ErrorMessageString) {.used, importc: "LLVMDisposeErrorMessage".}
proc getErrorMessage(err: ErrorRef): ErrorMessageString {.used, importc: "LLVMGetErrorMessage".}

# ############################################################
#
#                         Module
#
# ############################################################

# {.push header: "<llvm-c/Core.h>".}

proc createModule(name: cstring, ctx: ContextRef): ModuleRef {.used, importc: "LLVMModuleCreateWithNameInContext".}
proc dispose*(m: ModuleRef) {.importc: "LLVMDisposeModule".}
  ## Destroys a module
  ## Note: destroying an Execution Engine will also destroy modules attached to it
proc toIR_LLVMstring(m: ModuleRef): LLVMstring {.used, importc: "LLVMPrintModuleToString".}
  ## Print a module IR to textual IR string. The string must be disposed with LLVM "dispose" or memory will leak.
proc getContext*(m: ModuleRef): ContextRef {.importc: "LLVMGetModuleContext".}
proc getIdentifier*(m: ModuleRef, rLen: var csize_t): cstring {.used, importc: "LLVMGetModuleIdentifier".}

proc addNamedMetadataOperand*(m: ModuleRef, name: cstring, val: ValueRef) {.importc: "LLVMAddNamedMetadataOperand".}
proc metadataNode*(ctx: ContextRef, metadataNodes: openArray[MetadataRef]): MetadataRef {.wrapOpenArrayLenType: csize_t, importc: "LLVMMDNodeInContext2".}
proc metadataNode*(ctx: ContextRef, str: openArray[char]): MetadataRef {.wrapOpenArrayLenType: csize_t, importc: "LLVMMDStringInContext2".}
proc asMetadataRef*(val: ValueRef): MetadataRef {.importc: "LLVMValueAsMetadata".}
proc asValueRef*(ctx: ContextRef, md: MetadataRef): ValueRef {.importc: "LLVMMetadataAsValue".}

# <llvm-c/BitWriter.h>
proc writeBitcodeToFile*(m: ModuleRef, path: cstring) {.importc: "LLVMWriteBitcodeToFile".}
proc writeBitcodeToMemoryBuffer(m: ModuleRef): MemoryBufferRef {.used, importc: "LLVMWriteBitcodeToMemoryBuffer".}
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

{.push used.}
proc initializeX86AsmPrinter() {.importc: "LLVMInitializeX86AsmPrinter".}
proc initializeX86Target() {.importc: "LLVMInitializeX86Target".}
proc initializeX86TargetInfo() {.importc: "LLVMInitializeX86TargetInfo".}
proc initializeX86TargetMC() {.importc: "LLVMInitializeX86TargetMC".}

proc initializeNVPTXAsmPrinter() {.importc: "LLVMInitializeNVPTXAsmPrinter".}
proc initializeNVPTXTarget() {.importc: "LLVMInitializeNVPTXTarget".}
proc initializeNVPTXTargetInfo() {.importc: "LLVMInitializeNVPTXTargetInfo".}
proc initializeNVPTXTargetMC() {.importc: "LLVMInitializeNVPTXTargetMC".}
{.pop.}

proc getTargetFromName*(name: cstring): TargetRef {.importc: "LLVMGetTargetFromName".}
proc getTargetFromTriple*(triple: cstring, target: var TargetRef, errorMessage: var LLVMstring
       ): LLVMBool {.importc: "LLVMGetTargetFromTriple".}

proc getTargetDescription*(t: TargetRef): cstring {.importc: "LLVMGetTargetDescription".}

proc hasJIT*(t: TargetRef): LLVMBool {.importc: "LLVMTargetHasJIT".}
proc hasTargetMachine*(t: TargetRef): LLVMBool {.importc: "LLVMTargetHasTargetMachine".}
proc hasAsmBackend*(t: TargetRef): LLVMBool {.importc: "LLVMTargetHasAsmBackend".}

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
#                    Target Machine
#
# ############################################################

type
  CodeGenOptLevel* {.size: sizeof(cint).} = enum
    CodeGenLevelNone, CodeGenLevelLess, CodeGenLevelDefault, CodeGenLevelAggressive
  RelocMode* {.size: sizeof(cint).} = enum
    RelocDefault, RelocStatic, RelocPIC, RelocDynamicNoPic, RelocROPI, RelocRWPI,
    RelocROPI_RWPI
  CodeModel* {.size: sizeof(cint).} = enum
    CodeModelDefault, CodeModelJITDefault, CodeModelTiny, CodeModelSmall,
    CodeModelKernel, CodeModelMedium, CodeModelLarge
  CodeGenFileType* {.size: sizeof(cint).} = enum
    AssemblyFile, ObjectFile

  TargetDataRef* = distinct pointer
  TargetLibraryInfoRef* = distinct pointer

# "<llvm-c/TargetMachine.h>"
proc createTargetMachine*(
       target: TargetRef, triple, cpu, features: cstring,
       level: CodeGenOptLevel, reloc: RelocMode, codeModel: CodeModel): TargetMachineRef {.importc: "LLVMCreateTargetMachine".}
proc dispose*(m: TargetMachineRef) {.importc: "LLVMDisposeTargetMachine".}

proc createTargetDataLayout*(t: TargetMachineRef): TargetDataRef {.importc: "LLVMCreateTargetDataLayout".}
proc dispose*(m: TargetDataRef) {.importc: "LLVMDisposeTargetData".}
proc setDataLayout*(module: ModuleRef, dataLayout: TargetDataRef) {.importc: "LLVMSetModuleDataLayout".}

proc targetMachineEmitToFile*(t: TargetMachineRef, m: ModuleRef, fileName: cstring,
                             codegen: CodeGenFileType, errorMessage: var LLVMstring): LLVMBool {.importc: "LLVMTargetMachineEmitToFile".}
proc targetMachineEmitToMemoryBuffer*(t: TargetMachineRef, m: ModuleRef,
                                     codegen: CodeGenFileType,
                                     errorMessage: var LLVMstring,
                                     outMemBuf: var MemoryBufferRef): LLVMBool {.importc: "LLVMTargetMachineEmitToMemoryBuffer".}

# ############################################################
#
#                    Passes and transforms
#
# ############################################################

# - https://blog.llvm.org/posts/2021-03-26-the-new-pass-manager/
# - https://llvm.org/docs/NewPassManager.html

# https://llvm.org/doxygen/group__LLVMCCorePassManagers.html
# # header: "<llvm-c/Core.h>"

proc createPassManager*(): PassManagerRef {.importc: "LLVMCreatePassManager".}
proc dispose*(pm: PassManagerRef) {.importc: "LLVMDisposePassManager".}
proc run*(pm: PassManagerRef, module: ModuleRef) {. importc: "LLVMRunPassManager".}

# https://llvm.org/doxygen/group__LLVMCTransformsPassManagerBuilder.html
# header: "<llvm-c/Transforms/PassManagerBuilder.h>"

proc createPassManagerBuilder*(): PassManagerBuilderRef {.importc: "LLVMPassManagerBuilderCreate".}
proc dispose*(pmb: PassManagerBuilderRef) {.importc: "LLVMPassManagerBuilderDispose".}
proc setOptLevel*(pmb: PassManagerBuilderRef, level: uint32) {.importc: "LLVMPassManagerBuilderSetOptLevel".}
proc setSizeLevel*(pmb: PassManagerBuilderRef, level: uint32) {.importc: "LLVMPassManagerBuilderSetSizeLevel".}
proc populateModulePassManager*(pmb: PassManagerBuilderRef, legacyPM: PassManagerRef) {. importc: "LLVMPassManagerBuilderPopulateModulePassManager".}

# https://llvm.org/doxygen/group__LLVMCCoreNewPM.html
# header: "<llvm-c/Transforms/PassBuilder.h>"

proc createPassBuilderOptions*(): PassBuilderOptionsRef {.importc: "LLVMCreatePassBuilderOptions".}
proc dispose*(pbo: PassBuilderOptionsRef) {.importc: "LLVMDisposePassBuilderOptions".}
proc runPasses(module: ModuleRef, passes: cstring, machine: TargetMachineRef, pbo: PassBuilderOptionsRef): ErrorRef {.used, importc: "LLVMRunPasses".}

# https://llvm.org/docs/doxygen/group__LLVMCInitialization.html
# header: "<llvm-c/Initialization.h>"

{.push used.}
proc getGlobalPassRegistry(): PassRegistryRef {.importc: "LLVMGetGlobalPassRegistry".}

proc initializeCore(registry: PassRegistryRef) {.importc: "LLVMInitializeCore".}
proc initializeTransformUtils(registry: PassRegistryRef) {.importc: "LLVMInitializeTransformUtils".}
proc initializeScalarOpts(registry: PassRegistryRef) {.importc: "LLVMInitializeScalarOpts".}
proc initializeVectorization(registry: PassRegistryRef) {.importc: "LLVMInitializeVectorization".}
proc initializeInstCombine(registry: PassRegistryRef) {.importc: "LLVMInitializeInstCombine".}
proc initializeIPO(registry: PassRegistryRef) {.importc: "LLVMInitializeIPO".}
proc initializeAnalysis(registry: PassRegistryRef) {.importc: "LLVMInitializeAnalysis".}
proc initializeIPA(registry: PassRegistryRef) {.importc: "LLVMInitializeIPA".}
proc initializeCodeGen(registry: PassRegistryRef) {.importc: "LLVMInitializeCodeGen".}
proc initializeTarget(registry: PassRegistryRef) {.importc: "LLVMInitializeTarget".}

# Removed in LLVM 16
# ------------------
# proc initializeObjCARCOpts(registry: PassRegistryRef) {.importc: "LLVMInitializeObjCARCOpts".}
# proc initializeAggressiveInstCombiner(registry: PassRegistryRef) {.importc: "LLVMInitializeAggressiveInstCombiner".}
# proc initializeInstrumentation(registry: PassRegistryRef) {.importc: "LLVMInitializeInstrumentation".}

{.pop.}

# https://llvm.org/doxygen/group__LLVMCTarget.html
proc addTargetLibraryInfo*(tli: TargetLibraryInfoRef, pm: PassManagerRef) {.importc: "LLVMAddTargetLibraryInfo".}
  # There doesn't seem to be a way to instantiate TargetLibraryInfoRef :/
proc addAnalysisPasses*(machine: TargetMachineRef, pm: PassManagerRef) {.importc: "LLVMAddAnalysisPasses".}

# https://www.llvm.org/docs/Passes.html
# -------------------------------------

# https://llvm.org/doxygen/group__LLVMCTransformsInstCombine.html
proc addInstructionCombiningPass*(pm: PassManagerRef) {.importc: "LLVMAddInstructionCombiningPass".}

# https://llvm.org/doxygen/group__LLVMCTransformsUtils.html
proc addPromoteMemoryToRegisterPass*(pm: PassManagerRef) {.importc: "LLVMAddPromoteMemoryToRegisterPass".}

# https://llvm.org/doxygen/group__LLVMCTransformsScalar.html
proc addAggressiveDeadCodeEliminationPass*(pm: PassManagerRef) {.importc: "LLVMAddAggressiveDCEPass".}
proc addDeadStoreEliminationPass*(pm: PassManagerRef) {.importc: "LLVMAddDeadStoreEliminationPass".}
proc addGlobalValueNumberingPass*(pm: PassManagerRef) {.importc: "LLVMAddNewGVNPass".}
proc addMemCpyOptPass*(pm: PassManagerRef) {.importc: "LLVMAddMemCpyOptPass".}
proc addScalarReplacementOfAggregatesPass*(pm: PassManagerRef) {.importc: "LLVMAddScalarReplAggregatesPass".}

# https://llvm.org/doxygen/group__LLVMCTransformsIPO.html
proc addDeduceFunctionAttributesPass*(pm: PassManagerRef) {.importc: "LLVMAddFunctionAttrsPass".}
proc addFunctionInliningPass*(pm: PassManagerRef) {.importc: "LLVMAddFunctionInliningPass".}

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

proc getContext*(ty: TypeRef): ContextRef {.importc: "LLVMGetTypeContext".}
proc getTypeKind*(ty: TypeRef): TypeKind {.importc: "LLVMGetTypeKind".}
proc dumpType*(ty: TypeRef) {.sideeffect, importc: "LLVMDumpType".}
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

proc getIntTypeWidth*(ty: TypeRef): uint32 {.importc: "LLVMGetIntTypeWidth".}

# Composite
# ------------------------------------------------------------
proc struct_t*(
       ctx: ContextRef,
       elemTypes: openArray[TypeRef],
       packed: LlvmBool): TypeRef {.wrapOpenArrayLenType: cuint, importc: "LLVMStructTypeInContext".}
proc array_t*(elemType: TypeRef, elemCount: uint32): TypeRef {.importc: "LLVMArrayType".}

proc pointerType(elementType: TypeRef; addressSpace: cuint): TypeRef {.used, importc: "LLVMPointerType".}

proc getElementType*(arrayOrVectorTy: TypeRef): TypeRef {.importc: "LLVMGetElementType".}

# Functions
# ------------------------------------------------------------
proc function_t*(
       returnType: TypeRef,
       paramTypes: openArray[TypeRef],
       isVarArg: LlvmBool): TypeRef {.wrapOpenArrayLenType: cuint, importc: "LLVMFunctionType".}

proc addFunction*(m: ModuleRef, name: cstring, ty: TypeRef): ValueRef {.importc: "LLVMAddFunction".}
  ## Declare a function `name` in a module.
  ## Returns a handle to specify its instructions

proc getReturnType*(functionTy: TypeRef): TypeRef {.importc: "LLVMGetReturnType".}
proc countParamTypes*(functionTy: TypeRef): uint32 {.importc: "LLVMCountParamTypes".}

# ############################################################
#
#                         Values
#
# ############################################################

# {.push header: "<llvm-c/Core.h>".}

proc getTypeOf*(v: ValueRef): TypeRef {.importc: "LLVMTypeOf".}
proc getValueName2(v: ValueRef, rLen: var csize_t): cstring {.used, importc: "LLVMGetValueName2".}
  ## Returns the name of a valeu if it exists.
  ## `rLen` stores the returned string length
  ##
  ## This is not free, it requires internal hash table access
  ## The return value does not have to be freed and is a pointer an internal LLVM data structure

proc dumpValue*(v: ValueRef) {.sideeffect, importc: "LLVMDumpValue".}
  ## Print the value to stderr

proc toLLVMstring(v: ValueRef): LLVMstring {.used, importc: "LLVMPrintValueToString".}

# Constants
# ------------------------------------------------------------
# https://llvm.org/doxygen/group__LLVMCCoreValueConstant.html

proc constInt(ty: TypeRef, n: culonglong, signExtend: LlvmBool): ValueRef {.used, importc: "LLVMConstInt".}
proc constReal*(ty: TypeRef, n: cdouble): ValueRef {.importc: "LLVMConstReal".}

proc constNull*(ty: TypeRef): ValueRef {.importc: "LLVMConstNull".}
proc constAllOnes*(ty: TypeRef): ValueRef {.importc: "LLVMConstAllOnes".}
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
    IntEQ = 32               ## equal
    IntNE                    ## not equal
    IntUGT                   ## unsigned greater than
    IntUGE                   ## unsigned greater or equal
    IntULT                   ## unsigned less than
    IntULE                   ## unsigned less or equal
    IntSGT                   ## signed greater than
    IntSGE                   ## signed greater or equal
    IntSLT                   ## signed less than
    IntSLE                   ## signed less or equal

  InlineAsmDialect* {.size: sizeof(cint).} = enum
    InlineAsmDialectATT
    InlineAsmDialectIntel

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
proc retVoid*(builder: BuilderRef): ValueRef {.discardable, importc: "LLVMBuildRetVoid".}
proc ret*(builder: BuilderRef, returnVal: ValueRef): ValueRef {.discardable, importc: "LLVMBuildRet".}

# Positioning
# ------------------------------------------------------------

proc position*(builder: BuilderRef, blck: BasicBlockRef, instr: ValueRef) {.importc: "LLVMPositionBuilder".}
proc positionBefore*(builder: BuilderRef, instr: ValueRef) {.importc: "LLVMPositionBuilderBefore".}
proc positionAtEnd*(builder: BuilderRef, blck: BasicBlockRef) {.importc: "LLVMPositionBuilderAtEnd".}

proc getInsertBlock(builder: BuilderRef): BasicBlockRef {.used, importc: "LLVMGetInsertBlock".}
  ## This function is not documented and probably for special use
  ## However due to https://github.com/llvm/llvm-project/issues/59875
  ## it's our workaround to get the context of a Builder

proc getBasicBlockParent*(blck: BasicBlockRef): ValueRef {.importc: "LLVMGetBasicBlockParent".}
  ## Obtains the function to which a basic block belongs

# Inline Assembly
# ------------------------------------------------------------
proc getInlineAsm*(
       ty: TypeRef,
       asmString: openArray[char],
       constraints: openArray[char],
       hasSideEffects, isAlignStack: LlvmBool,
       dialect: InlineAsmDialect, canThrow: LlvmBool
     ): ValueRef {.importc: "LLVMGetInlineAsm"}

# Intermediate Representation
# ------------------------------------------------------------
#
# - NSW: no signed wrap, signed value cannot over- or underflow.
# - NUW: no unsigned wrap, unsigned value cannot over- or underflow.

proc call2*(
       builder: BuilderRef,
       ty: TypeRef,
       fn: ValueRef,
       args: openArray[ValueRef],
       name: cstring = ""): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMBuildCall2".}

proc add*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildAdd".}
proc addNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWAdd".}
proc addNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWAdd".}

proc sub*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildSub".}
proc subNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWSub".}
proc subNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWSub".}

proc neg*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNeg".}
proc negNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWNeg".}
proc negNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWNeg".}

proc mul*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildMul".}
proc mulNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWMul".}
proc mulNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWMul".}

proc divU*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildUDiv".}
proc divU_exact*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildExactUDiv".}
proc divS*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildSDiv".}
proc divS_exact*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildExactSDiv".}
proc remU*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildURem".}
proc remS*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildSRem".}

proc lshl*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildShl".}
proc lshr*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildLShr".}
proc ashr*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildAShr".}

proc `and`*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildAnd".}
proc `or`*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildOr".}
proc `xor`*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildXor".}
proc `not`*(builder: BuilderRef, val: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNot".}
proc select*(builder: BuilderRef, condition, then, otherwise: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildSelect".}

proc icmp*(builder: BuilderRef, op: IntPredicate, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildICmp".}

proc bitcast*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildBitcast".}
proc trunc*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildTrunc".}
proc zext*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildZExt".}
  ## Zero-extend
proc sext*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildSExt".}
  ## Sign-extend

proc malloc*(builder: BuilderRef, ty: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildMalloc".}
proc mallocArray*(builder: BuilderRef, ty: TypeRef, length: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildArrayMalloc".}
proc free*(builder: BuilderRef, ty: TypeRef, `ptr`: ValueRef): ValueRef {.importc: "LLVMBuildFree".}
proc alloca*(builder: BuilderRef, ty: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildAlloca".}
proc allocaArray*(builder: BuilderRef, ty: TypeRef, length: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildArrayAlloca".}

proc extractValue*(builder: BuilderRef, aggVal: ValueRef, index: uint32, name: cstring = ""): ValueRef {.importc: "LLVMBuildExtractValue".}
proc insertValue*(builder: BuilderRef, aggVal: ValueRef, eltVal: ValueRef, index: uint32, name: cstring = ""): ValueRef {.discardable, importc: "LLVMBuildInsertValue".}

proc getElementPtr2*(
       builder: BuilderRef,
       ty: TypeRef,
       `ptr`: ValueRef,
       indices: openArray[ValueRef],
       name: cstring = ""
     ): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMBuildGEP2".}
  ## https://www.llvm.org/docs/GetElementPtr.html
proc getElementPtr2_InBounds*(
       builder: BuilderRef,
       ty: TypeRef,
       `ptr`: ValueRef,
       indices: openArray[ValueRef],
       name: cstring = ""
     ): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMBuildInBoundsGEP2".}
  ## https://www.llvm.org/docs/GetElementPtr.html
  ## If the GEP lacks the inbounds keyword, the value is the result from evaluating the implied two’s complement integer computation.
  ## However, since there’s no guarantee of where an object will be allocated in the address space, such values have limited meaning.
proc getElementPtr2_Struct*(
       builder: BuilderRef,
       ty: TypeRef,
       `ptr`: ValueRef,
       idx: uint32,
       name: cstring = ""
     ): ValueRef {.importc: "LLVMBuildStructGEP2".}
  ## https://www.llvm.org/docs/GetElementPtr.html
  ## If the GEP lacks the inbounds keyword, the value is the result from evaluating the implied two’s complement integer computation.
  ## However, since there’s no guarantee of where an object will be allocated in the address space, such values have limited meaning.

proc load2*(builder: BuilderRef, ty: TypeRef, `ptr`: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildLoad2".}
proc store*(builder: BuilderRef, val, `ptr`: ValueRef): ValueRef {.discardable, importc: "LLVMBuildStore".}

proc memset*(builder: BuilderRef, `ptr`, val, len: ValueRef, align: uint32) {.importc: "LLVMBuildMemset".}
proc memcpy*(builder: BuilderRef, dst: ValueRef, dstAlign: uint32, src: ValueRef, srcAlign: uint32, size: ValueRef) {.importc: "LLVMBuildMemcpy".}
proc memmove*(builder: BuilderRef, dst: ValueRef, dstAlign: uint32, src: ValueRef, srcAlign: uint32, size: ValueRef) {.importc: "LLVMBuildMemmove".}

{.pop.} # {.used, hint[Name]: off, noconv, dynlib: libLLVM.}
