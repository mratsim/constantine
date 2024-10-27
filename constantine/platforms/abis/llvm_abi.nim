# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./c_abi

const libLLVM = "libLLVM-(16|17|18).so"
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
  TargetDataRef* = distinct pointer
  ExecutionEngineRef* = distinct pointer
  TargetMachineRef* = distinct pointer
  PassBuilderOptionsRef* = distinct pointer
  TypeRef* = distinct pointer
  ValueRef* = distinct pointer
  MetadataRef = distinct pointer
  AttributeRef* = distinct pointer
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
proc initializeX86AsmParser() {.importc: "LLVMInitializeX86AsmParser".}
proc initializeX86Target() {.importc: "LLVMInitializeX86Target".}
proc initializeX86TargetInfo() {.importc: "LLVMInitializeX86TargetInfo".}
proc initializeX86TargetMC() {.importc: "LLVMInitializeX86TargetMC".}

proc initializeNVPTXAsmPrinter() {.importc: "LLVMInitializeNVPTXAsmPrinter".}
proc initializeNVPTXAsmParser() {.importc: "LLVMInitializeNVPTXAsmParser".}
proc initializeNVPTXTarget() {.importc: "LLVMInitializeNVPTXTarget".}
proc initializeNVPTXTargetInfo() {.importc: "LLVMInitializeNVPTXTargetInfo".}
proc initializeNVPTXTargetMC() {.importc: "LLVMInitializeNVPTXTargetMC".}

proc initializeAMDGPUAsmPrinter() {.importc: "LLVMInitializeAMDGPUAsmPrinter".}
proc initializeAMDGPUAsmParser() {.importc: "LLVMInitializeAMDGPUAsmParser".}
proc initializeAMDGPUTarget() {.importc: "LLVMInitializeAMDGPUTarget".}
proc initializeAMDGPUTargetInfo() {.importc: "LLVMInitializeAMDGPUTargetInfo".}
proc initializeAMDGPUTargetMC() {.importc: "LLVMInitializeAMDGPUTargetMC".}
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

# "<llvm-c/TargetMachine.h>"
proc createTargetMachine*(
       target: TargetRef, triple, cpu, features: cstring,
       level: CodeGenOptLevel, reloc: RelocMode, codeModel: CodeModel): TargetMachineRef {.importc: "LLVMCreateTargetMachine".}
proc dispose*(m: TargetMachineRef) {.importc: "LLVMDisposeTargetMachine".}

proc getDataLayout*(t: TargetMachineRef): TargetDataRef {.importc: "LLVMCreateTargetDataLayout".}
proc getDataLayout*(module: ModuleRef): TargetDataRef {.importc: "LLVMGetModuleDataLayout".}
proc dispose*(m: TargetDataRef) {.importc: "LLVMDisposeTargetData".}
proc setDataLayout*(module: ModuleRef, dataLayout: TargetDataRef) {.importc: "LLVMSetModuleDataLayout".}

proc getPointerSize*(datalayout: TargetDataRef): cuint {.importc: "LLVMPointerSize".}
proc getSizeInBits*(datalayout: TargetDataRef, ty: TypeRef): culonglong {.importc: "LLVMSizeOfTypeInBits".}
  ## Computes the size of a type in bits for a target.
proc getStoreSize*(datalayout: TargetDataRef, ty: TypeRef): culonglong {.importc: "LLVMStoreSizeOfType".}
  ## Computes the storage size of a type in bytes for a target.
proc getAbiSize*(datalayout: TargetDataRef, ty: TypeRef): culonglong {.importc: "LLVMABISizeOfType".}
  ## Computes the ABI size of a type in bytes for a target.

type
  ByteOrder {.size: sizeof(cint).} = enum
    kBigEndian
    kLittleEndian

proc getEndianness*(datalayout: TargetDataref): ByteOrder {.importc: "LLVMByteOrder".}


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

# https://llvm.org/doxygen/group__LLVMCCoreNewPM.html
# header: "<llvm-c/Transforms/PassBuilder.h>"

proc createPassBuilderOptions*(): PassBuilderOptionsRef {.importc: "LLVMCreatePassBuilderOptions".}
proc dispose*(pbo: PassBuilderOptionsRef) {.importc: "LLVMDisposePassBuilderOptions".}
proc runPasses*(module: ModuleRef, passes: cstring, machine: TargetMachineRef, pbo: PassBuilderOptionsRef): ErrorRef {.used, importc: "LLVMRunPasses".}
proc setMergeFunctions*(pbo: PassBuilderOptionsRef, mergeFunctions = LlvmBool(1)) {.importc: "LLVMPassBuilderOptionsSetMergeFunctions".}

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

# Floats
# ------------------------------------------------------------
proc float16_t*(ctx: ContextRef): TypeRef {.importc: "LLVMBFloatTypeInContext".}
proc float32_t*(ctx: ContextRef): TypeRef {.importc: "LLVMFloatTypeInContext".}
proc float64_t*(ctx: ContextRef): TypeRef {.importc: "LLVMDoubleTypeInContext".}
proc float128_t*(ctx: ContextRef): TypeRef {.importc: "LLVMFP128TypeInContext".}

# Composite
# ------------------------------------------------------------
proc struct_t*(
       ctx: ContextRef,
       elemTypes: openArray[TypeRef],
       packed = LlvmBool(false)): TypeRef {.wrapOpenArrayLenType: cuint, importc: "LLVMStructTypeInContext".}
proc array_t*(elemType: TypeRef, elemCount: uint32): TypeRef {.importc: "LLVMArrayType".}
proc vector_t*(elemType: TypeRef, elemCount: uint32): TypeRef {.importc: "LLVMVectorType".}
  ## Create a SIMD vector type (for SSE, AVX or Neon for example)

proc pointerType(elementType: TypeRef; addressSpace: cuint): TypeRef {.used, importc: "LLVMPointerType".}

proc getElementType*(arrayOrVectorTy: TypeRef): TypeRef {.importc: "LLVMGetElementType".}
proc getArrayLength*(arrayTy: TypeRef): uint64 {.importc: "LLVMGetArrayLength2".}
proc getNumElements*(structTy: TypeRef): cuint {.importc: "LLVMCountStructElementTypes".}
proc getVectorSize*(vecTy: TypeRef): cuint {.importc: "LLVMGetVectorSize".}

# Functions
# ------------------------------------------------------------
type
  CallingConvention {.size: sizeof(cuint).} = enum
    # The default llvm calling convention, compatible with C. This convention
    # is the only one that supports varargs calls. As with typical C calling
    # conventions, the callee/caller have to tolerate certain amounts of
    # prototype mismatch.
    C = 0,

    # Generic LLVM calling conventions. None of these support varargs calls,
    # and all assume that the caller and callee prototype exactly match.

    # Attempts to make calls as fast as possible (e.g. by passing things in
    # registers).
    Fast = 8,

    # Attempts to make code in the caller as efficient as possible under the
    # assumption that the call is not commonly executed. As such, these calls
    # often preserve all registers so that the call does not break any live
    # ranges in the caller side.
    Cold = 9,

    # Used by the Glasgow Haskell Compiler (GHC).
    GHC = 10,

    # Used by the High-Performance Erlang Compiler (HiPE).
    HiPE = 11,

    # OBSOLETED - Used for stack based JavaScript calls
    # WebKit_JS = 12,

    # Used for dynamic register based calls (e.g. stackmap and patchpoint
    # intrinsics).
    AnyReg = 13,

    # Used for runtime calls that preserves most registers.
    PreserveMost = 14,

    # Used for runtime calls that preserves (almost) all registers.
    PreserveAll = 15,

    # Calling convention for Swift.
    Swift = 16,

    # Used for access functions.
    CXX_FAST_TLS = 17,

    # Attemps to make calls as fast as possible while guaranteeing that tail
    # call optimization can always be performed.
    Tail = 18,

    # Special calling convention on Windows for calling the Control Guard
    # Check ICall funtion. The function takes exactly one argument (address of
    # the target function) passed in the first argument register, and has no
    # return value. All register values are preserved.
    CFGuard_Check = 19,

    # This follows the Swift calling convention in how arguments are passed
    # but guarantees tail calls will be made by making the callee clean up
    # their stack.
    SwiftTail = 20,

    # Used for runtime calls that preserves none general registers.
    PreserveNone = 21,

    # This is the start of the target-specific calling conventions, e.g.
    # fastcall and thiscall on X86.
    # FirstTargetCC = 64,

    # stdcall is mostly used by the Win32 API. It is basically the same as the
    # C convention with the difference in that the callee is responsible for
    # popping the arguments from the stack.
    X86_StdCall = 64,

    # 'fast' analog of X86_StdCall. Passes first two arguments in ECX:EDX
    # registers, others - via stack. Callee is responsible for stack cleaning.
    X86_FastCall = 65,

    # ARM Procedure Calling Standard (obsolete, but still used on some
    # targets).
    ARM_APCS = 66,

    # ARM Architecture Procedure Calling Standard calling convention (aka
    # EABI). Soft float variant.
    ARM_AAPCS = 67,

    # Same as ARM_AAPCS, but uses hard floating point ABI.
    ARM_AAPCS_VFP = 68,

    # Used for MSP430 interrupt routines.
    MSP430_INTR = 69,

    # Similar to X86_StdCall. Passes first argument in ECX, others via stack.
    # Callee is responsible for stack cleaning. MSVC uses this by default for
    # methods in its ABI.
    X86_ThisCall = 70,

    # Call to a PTX kernel. Passes all arguments in parameter space.
    PTX_Kernel = 71,

    # Call to a PTX device function. Passes all arguments in register or
    # parameter space.
    PTX_Device = 72,

    # Used for SPIR non-kernel device functions. No lowering or expansion of
    # arguments. Structures are passed as a pointer to a struct with the
    # byval attribute. Functions can only call SPIR_FUNC and SPIR_KERNEL
    # functions. Functions can only have zero or one return values. Variable
    # arguments are not allowed, except for printf. How arguments/return
    # values are lowered are not specified. Functions are only visible to the
    # devices.
    SPIR_FUNC = 75,

    # Used for SPIR kernel functions. Inherits the restrictions of SPIR_FUNC,
    # except it cannot have non-void return values, it cannot have variable
    # arguments, it can also be called by the host or it is externally
    # visible.
    SPIR_KERNEL = 76,

    # Used for Intel OpenCL built-ins.
    Intel_OCL_BI = 77,

    # The C convention as specified in the x86-64 supplement to the System V
    # ABI, used on most non-Windows systems.
    X86_64_SysV = 78,

    # The C convention as implemented on Windows/x86-64 and AArch64. It
    # differs from the more common \c X86_64_SysV convention in a number of
    # ways, most notably in that XMM registers used to pass arguments are
    # shadowed by GPRs, and vice versa. On AArch64, this is identical to the
    # normal C (AAPCS) calling convention for normal functions, but floats are
    # passed in integer registers to variadic functions.
    Win64 = 79,

    # MSVC calling convention that passes vectors and vector aggregates in SSE
    # registers.
    X86_VectorCall = 80,

    # Placeholders for HHVM calling conventions (deprecated, removed).
    DUMMY_HHVM = 81,
    DUMMY_HHVM_C = 82,

    # x86 hardware interrupt context. Callee may take one or two parameters,
    # where the 1st represents a pointer to hardware context frame and the 2nd
    # represents hardware error code, the presence of the later depends on the
    # interrupt vector taken. Valid for both 32- and 64-bit subtargets.
    X86_INTR = 83,

    # Used for AVR interrupt routines.
    AVR_INTR = 84,

    # Used for AVR signal routines.
    AVR_SIGNAL = 85,

    # Used for special AVR rtlib functions which have an "optimized"
    # convention to preserve registers.
    AVR_BUILTIN = 86,

    # Used for Mesa vertex shaders, or AMDPAL last shader stage before
    # rasterization (vertex shader if tessellation and geometry are not in
    # use, or otherwise copy shader if one is needed).
    AMDGPU_VS = 87,

    # Used for Mesa/AMDPAL geometry shaders.
    AMDGPU_GS = 88,

    # Used for Mesa/AMDPAL pixel shaders.
    AMDGPU_PS = 89,

    # Used for Mesa/AMDPAL compute shaders.
    AMDGPU_CS = 90,

    # Used for AMDGPU code object kernels.
    AMDGPU_KERNEL = 91,

    # Register calling convention used for parameters transfer optimization
    X86_RegCall = 92,

    # Used for Mesa/AMDPAL hull shaders (= tessellation control shaders).
    AMDGPU_HS = 93,

    # Used for special MSP430 rtlib functions which have an "optimized"
    # convention using additional registers.
    MSP430_BUILTIN = 94,

    # Used for AMDPAL vertex shader if tessellation is in use.
    AMDGPU_LS = 95,

    # Used for AMDPAL shader stage before geometry shader if geometry is in
    # use. So either the domain (= tessellation evaluation) shader if
    # tessellation is in use, or otherwise the vertex shader.
    AMDGPU_ES = 96,

    # Used between AArch64 Advanced SIMD functions
    AArch64_VectorCall = 97,

    # Used between AArch64 SVE functions
    AArch64_SVE_VectorCall = 98,

    # For emscripten __invoke_* functions. The first argument is required to
    # be the function ptr being indirectly called. The remainder matches the
    # regular calling convention.
    WASM_EmscriptenInvoke = 99,

    # Used for AMD graphics targets.
    AMDGPU_Gfx = 100,

    # Used for M68k interrupt routines.
    M68k_INTR = 101,

    # Preserve X0-X13, X19-X29, SP, Z0-Z31, P0-P15.
    AArch64_SME_ABI_Support_Routines_PreserveMost_From_X0 = 102,

    # Preserve X2-X15, X19-X29, SP, Z0-Z31, P0-P15.
    AArch64_SME_ABI_Support_Routines_PreserveMost_From_X2 = 103,

    # Used on AMDGPUs to give the middle-end more control over argument
    # placement.
    AMDGPU_CS_Chain = 104,

    # Used on AMDGPUs to give the middle-end more control over argument
    # placement. Preserves active lane values for input VGPRs.
    AMDGPU_CS_ChainPreserve = 105,

    # Used for M68k rtd-based CC (similar to X86's stdcall).
    M68k_RTD = 106,

    # Used by GraalVM. Two additional registers are reserved.
    GRAAL = 107,

    # Calling convention used in the ARM64EC ABI to implement calls between
    # x64 code and thunks. This is basically the x64 calling convention using
    # ARM64 register names. The first parameter is mapped to x9.
    ARM64EC_Thunk_X64 = 108,

    # Calling convention used in the ARM64EC ABI to implement calls between
    # ARM64 code and thunks. This is just the ARM64 calling convention,
    # except that the first parameter is mapped to x9.
    ARM64EC_Thunk_Native = 109,

    # Calling convention used for RISC-V V-extension.
    RISCV_VectorCall = 110,

    # Preserve X1-X15, X19-X29, SP, Z0-Z31, P0-P15.
    AArch64_SME_ABI_Support_Routines_PreserveMost_From_X1 = 111,

    # The highest possible ID. Must be some 2^k - 1.
    MaxID = 1023

type
  Linkage {.size: sizeof(cint).} = enum
    # https://web.archive.org/web/20240224034505/https://bluesadi.me/2024/01/05/Linkage-types-in-LLVM/
    # Weak linkage means unreferenced globals may not be discarded when linking.
    #
    # Also relevant: https://stackoverflow.com/a/55599037
    #   The necessity of making code relocatable in order allow shared objects to be loaded a different addresses
    #   in different process means that statically allocated variables,
    #   whether they have global or local scope,
    #   can't be accessed with directly with a single instruction on most architectures.
    #   The only exception I know of is the 64-bit x86 architecture, as you see above.
    #   It supports memory operands that are both PC-relative and have large 32-bit displacements
    #   that can reach any variable defined in the same component.
    linkExternal,                   ## Externally visible function
    linkAvailableExternally,        ## no description
    linkOnceAny,                    ## Keep one copy of function when linking (inline)
    linkOnceODR,                    ## Same, but only replaced by something equivalent. (ODR: one definition rule)
    linkOnceODRAutoHide,            ## Obsolete
    linkWeakAny,                    ## Keep one copy of function when linking (weak)
    linkWeakODR,                    ## Same, but only replaced by something equivalent.
    linkAppending,                  ## Special purpose, only applies to global arrays
    linkInternal,                   ## Rename collisions when linking (static functions)
    linkPrivate,                    ## Like Internal, but omit from symbol table
    linkDLLImport,                  ## Obsolete
    linkDLLExport,                  ## Obsolete
    linkExternalWeak,               ## ExternalWeak linkage description
    linkGhost,                      ## Obsolete
    linkCommon,                     ## Tentative definitions
    linkLinkerPrivate,              ## Like Private, but linker removes.
    linkLinkerPrivateWeak           ## Like LinkerPrivate, but is weak.

  Visibility {.size: sizeof(cint).} = enum
    # Note: Function with internal or private linkage must have default visibility
    visDefault
    visHidden
    visProtected


proc function_t*(
       returnType: TypeRef,
       paramTypes: openArray[TypeRef],
       isVarArg: LlvmBool): TypeRef {.wrapOpenArrayLenType: cuint, importc: "LLVMFunctionType".}

proc addFunction*(m: ModuleRef, name: cstring, ty: TypeRef): ValueRef {.importc: "LLVMAddFunction".}
  ## Declare a function `name` in a module.
  ## Returns a handle to specify its instructions

proc getFunction*(m: ModuleRef, name: cstring): ValueRef {.importc: "LLVMGetNamedFunction".}
  ## Get a function by name from the curent module.
  ## Return nil if not found.

proc getReturnType*(functionTy: TypeRef): TypeRef {.importc: "LLVMGetReturnType".}
proc countParamTypes*(functionTy: TypeRef): uint32 {.importc: "LLVMCountParamTypes".}

proc getCalledFunctionType*(fn: ValueRef): TypeRef {.importc: "LLVMGetCalledFunctionType".}

proc getFnCallConv*(function: ValueRef): CallingConvention {.importc: "LLVMGetFunctionCallConv".}
proc setFnCallConv*(function: ValueRef, cc: CallingConvention) {.importc: "LLVMSetFunctionCallConv".}

proc getInstrCallConv*(instr: ValueRef): CallingConvention {.importc: "LLVMGetInstructionCallConv".}
proc setInstrCallConv*(instr: ValueRef, cc: CallingConvention) {.importc: "LLVMSetInstructionCallConv".}

type
  AttributeIndex* {.size: sizeof(cint).} = enum
    ## Attribute index is either -1 for the function
    ## 0 for the return value
    ## or 1..n for each function parameter
    kAttrFnIndex = -1
    kAttrRetIndex = 0

proc toAttrId*(name: openArray[char]): cuint {.importc: "LLVMGetEnumAttributeKindForName".}
proc toAttr*(ctx: ContextRef, attr_id: uint64, val = 0'u64): AttributeRef {.importc: "LLVMCreateEnumAttribute".}
proc addAttribute*(fn: ValueRef, index: cint, attr: AttributeRef) {.importc: "LLVMAddAttributeAtIndex".}
proc addAttribute*(fn: ValueRef, index: AttributeIndex, attr: AttributeRef) {.importc: "LLVMAddAttributeAtIndex".}

# ############################################################
#
#                         Values
#
# ############################################################

# {.push header: "<llvm-c/Core.h>".}

proc getGlobal*(module: ModuleRef, name: cstring): ValueRef {.importc: "LLVMGetNamedGlobal".}
proc addGlobal*(module: ModuleRef, ty: TypeRef, name: cstring): ValueRef {.importc: "LLVMAddGlobal".}
proc setGlobal*(globalVar: ValueRef, constantVal: ValueRef) {.importc: "LLVMSetInitializer".}
proc setImmutable*(globalVar: ValueRef, immutable = LlvmBool(true)) {.importc: "LLVMSetGlobalConstant".}

proc getGlobalParent*(global: ValueRef): ModuleRef {.importc: "LLVMGetGlobalParent".}

proc setLinkage*(global: ValueRef, linkage: Linkage) {.importc: "LLVMSetLinkage".}
proc setVisibility*(global: ValueRef, vis: Visibility) {.importc: "LLVMSetVisibility".}
proc setAlignment*(v: ValueRef, bytes: cuint) {.importc: "LLVMSetAlignment".}
proc setSection*(global: ValueRef, section: cstring) {.importc: "LLVMSetSection".}

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
proc constIntOfArbitraryPrecision(ty: TypeRef, numWords: cuint, words: ptr uint64): ValueRef {.used, importc: "LLVMConstIntOfArbitraryPrecision".}
proc constIntOfStringAndSize(ty: TypeRef, text: openArray[char], radix: uint8): ValueRef {.used, importc: "LLVMConstIntOfStringAndSize".}

proc constReal*(ty: TypeRef, n: cdouble): ValueRef {.importc: "LLVMConstReal".}

proc constNull*(ty: TypeRef): ValueRef {.importc: "LLVMConstNull".}
proc constAllOnes*(ty: TypeRef): ValueRef {.importc: "LLVMConstAllOnes".}
proc constArray*(
       ty: TypeRef,
       constantVals: openArray[ValueRef],
    ): ValueRef {.wrapOpenArrayLenType: cuint, importc: "LLVMConstArray".}

# Undef & Poison
# ------------------------------------------------------------
# https://llvm.org/devmtg/2020-09/slides/Lee-UndefPoison.pdf

proc poison*(ty: TypeRef): ValueRef {.importc: "LLVMGetPoison".}
proc undef*(ty: TypeRef): ValueRef {.importc: "LLVMGetUndef".}



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

  Predicate* {.size: sizeof(cint).} = enum
    kEQ = 32               ## equal
    kNE                    ## not equal
    kUGT                   ## unsigned greater than
    kUGE                   ## unsigned greater or equal
    kULT                   ## unsigned less than
    kULE                   ## unsigned less or equal
    kSGT                   ## signed greater than
    kSGE                   ## signed greater or equal
    kSLT                   ## signed less than
    kSLE                   ## signed less or equal

  InlineAsmDialect* {.size: sizeof(cint).} = enum
    InlineAsmDialectATT
    InlineAsmDialectIntel

proc isNil*(v: BasicBlockRef): bool {.borrow.}

# "<llvm-c/Core.h>"

# Instantiation
# ------------------------------------------------------------

proc appendBasicBlock*(ctx: ContextRef, fn: ValueRef, name: cstring = ""): BasicBlockRef {.importc: "LLVMAppendBasicBlockInContext".}
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

proc phi*(builder: BuilderRef, ty: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildPhi".}
proc condBr*(builder: BuilderRef, ifCond: ValueRef, then, els: BasicBlockRef) {.importc: "LLVMBuildCondBr".}
proc br*(builder: BuilderRef, dest: BasicBlockRef) {.importc: "LLVMBuildBr".}
proc addIncoming*(phi: ValueRef, incomingVals: ptr UncheckedArray[ValueRef], incomingBlks: ptr UncheckedArray[BasicBlockRef], count: uint32) {.importc: "LLVMAddIncoming".}

proc addIncoming*(phi: ValueRef, incomingVal: ValueRef, incomingBlk: BasicBlockRef) =
  let iv = [incomingVal]; let ib = [incomingBlk]
  ## NOTE: Could of course also just mark `addIncoming` as receiving `ptr T` instead
  template toPOA(x): untyped =
    type T = typeof(x[0])
    cast[ptr UncheckedArray[T]](addr x)
  phi.addIncoming(toPOA iv, toPOA ib, 1)

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
  ## Addition No Signed Wrap, i.e. guaranteed to not overflow
proc addNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWAdd".}
  ## Addition No Unsigned Wrap, i.e. guaranteed to not overflow

proc sub*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildSub".}
proc subNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWSub".}
  ## Substraction No Signed Wrap, i.e. guaranteed to not overflow
proc subNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWSub".}
  ## Substraction No Unsigned Wrap, i.e. guaranteed to not overflow

proc neg*(builder: BuilderRef, operand: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNeg".}
proc negNSW*(builder: BuilderRef, operand: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWNeg".}
  ## Negation No Signed Wrap, i.e. guaranteed to not overflow
proc negNUW*(builder: BuilderRef, operand: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWNeg".}
  ## Negation No Unsigned Wrap, i.e. guaranteed to not overflow

proc mul*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildMul".}
proc mulNSW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNSWMul".}
  ## Multiplication No Signed Wrap, i.e. guaranteed to not overflow
proc mulNUW*(builder: BuilderRef, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildNUWMul".}
  ## Multiplication No Unsigned Wrap, i.e. guaranteed to not overflow

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

proc icmp*(builder: BuilderRef, op: Predicate, lhs, rhs: ValueRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildICmp".}

proc bitcast*(builder: BuilderRef, val: ValueRef, destTy: TypeRef, name: cstring = ""): ValueRef {.importc: "LLVMBuildBitCast".}
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
proc insertValue*(builder: BuilderRef, aggVal: ValueRef, eltVal: ValueRef, index: uint32, name: cstring = ""): ValueRef {.importc: "LLVMBuildInsertValue".}

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
