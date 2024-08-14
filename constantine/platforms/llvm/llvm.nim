# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/platforms/abis/llvm_abi {.all.}
import std/macros
export llvm_abi

# ############################################################
#
#                    LLVM API
#
# ############################################################

# This file exposes a Nimified LLVM API.
# Most functions are reexported as-is except functions involving:
# - LLVM cstring
# - LLVM Memory buffer
# - LLVM bool
# - LLVM metadata
# The cstring and memory buffers require manual memory management on the LLVM side.
# The LLVM bool uses 32-bit representation instead of 1-bit.
# LLVM metadata is easier to use with dedicated procedures.

# ⚠ Warning: To provide full diagnostic (filename:line), we wrap some LLVM procedures in template
# Templates copy-paste their inputs parameters.
# For example if `module` parameter is passed `foo.launchMissiles()`
# and that parameter is used twice within the template, `foo.launchMissiles()` will be called twice.

# Module
# ------------------------------------------------------------
proc createModule*(ctx: ContextRef, name: cstring): ModuleRef {.inline.} =
  createModule(name, ctx)

proc `$`*(ty: ModuleRef): string =
  let s = ty.toIR_LLVMstring()
  result = $cstring(s)
  s.dispose()

proc toBitcode*(m: ModuleRef): seq[byte] =
  ## Print a module IR to bitcode
  let mb = m.writeBitcodeToMemoryBuffer()
  let len = mb.getBufferSize()
  result.newSeq(len)
  copyMem(result[0].addr, mb.getBufferStart(), len)
  mb.dispose()

proc verify*(module: ModuleRef, failureAction: VerifierFailureAction) =
  ## Verify the IR code in a module
  var errMsg: LLVMstring
  let err = bool verify(module, failureAction, errMsg)
  if err:
    writeStackTrace()
    stderr.write("\"verify\" for module '" & astToStr(module) & "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

proc getIdentifier*(module: ModuleRef): string =
  var rLen: csize_t
  let rStr = getIdentifier(module, rLen)

  result = newString(rLen.int)
  copyMem(result[0].addr, rStr, rLen.int)

# Target
# ------------------------------------------------------------

proc toTarget*(triple: cstring): TargetRef =
  var target: TargetRef
  var errMsg: LLVMstring
  let err = bool triple.getTargetFromTriple(target, errMsg)
  if err:
    writeStackTrace()
    echo "\"toTarget\" for triple '", triple, "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n'
    errMsg.dispose()
    quit 1
  target

proc initializeFullNativeTarget* {.inline.} =
  static: doAssert defined(amd64) or defined(i386), "Only x86 is configured at the moment"
  initializeX86TargetInfo()
  initializeX86Target()
  initializeX86TargetMC()
  # With usual `initializeNativeTarget`
  # it's a separate call but it's mandatory so include it
  initializeX86AsmPrinter()

proc initializeFullNVPTXTarget* {.inline.} =
  initializeNVPTXTargetInfo()
  initializeNVPTXTarget()
  initializeNVPTXTargetMC()
  initializeNVPTXAsmPrinter()

proc initializeFullAMDGPUTarget* {.inline.} =
  initializeAMDGPUTargetInfo()
  initializeAMDGPUTarget()
  initializeAMDGPUTargetMC()
  initializeAMDGPUAsmPrinter()

# Execution Engine
# ------------------------------------------------------------

proc createJITCompilerForModule*(
       engine: var ExecutionEngineRef,
       module: ModuleRef,
       optLevel: uint32) =
  var errMsg: LLVMstring
  let err = bool createJITCompilerForModule(engine, module, optLevel, errMsg)
  if err:
    writeStackTrace()
    stderr.write("\"createJITCompilerForModule\" for module '" & astToStr(module) & "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

# Target Machine
# ------------------------------------------------------------

proc emitToFile*(t: TargetMachineRef, m: ModuleRef,
                 fileName: string, codegen: CodeGenFileType) =
  var errMsg: LLVMstring
  let err = bool targetMachineEmitToFile(t, m, cstring(fileName), codegen, errMsg)
  if err:
    writeStackTrace()
    stderr.write("\"emitToFile\" for module '" & astToStr(module) & "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

proc emitTo*[T: string or seq[byte]](t: TargetMachineRef, m: ModuleRef, codegen: CodeGenFileType): T =
  ## Codegen to string
  var errMsg: LLVMstring
  var mb: MemoryBufferRef
  let err = bool targetMachineEmitToMemoryBuffer(t, m, codegen, errMsg, mb)
  if err:
    writeStackTrace()
    stderr.write("\"emitToString\" for module '" & astToStr(module) & "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1
  let len = mb.getBufferSize()
  result.setLen(len)
  copyMem(result[0].addr, mb.getBufferStart(), len)
  mb.dispose()

# Builder
# ------------------------------------------------------------

proc getCurrentFunction*(builder: BuilderRef): ValueRef =
  builder.getInsertBlock().getBasicBlockParent()

proc getContext*(builder: BuilderRef): ContextRef =
  # LLVM C API does not expose IRBuilder.getContext()
  # making this unnecessary painful
  # https://github.com/llvm/llvm-project/issues/59875
  builder.getCurrentFunction().getTypeOf().getContext()

proc getCurrentModule*(builder: BuilderRef): ModuleRef =
  builder.getCurrentFunction().getGlobalParent()

# Types
# ------------------------------------------------------------

proc `$`*(ty: TypeRef): string =
  let s = ty.toLLVMstring()
  result = $cstring(s)
  s.dispose()

proc isVoid*(ty: TypeRef): bool {.inline.} =
  ty.getTypeKind == tkVoid

proc pointer_t*(elementTy: TypeRef): TypeRef {.inline.} =
  pointerType(elementTy, addressSpace = 0)

proc array_t*(elemType: TypeRef, elemCount: SomeInteger): TypeRef {.inline.}=
  array_t(elemType, uint32(elemCount))

proc function_t*(returnType: TypeRef, paramTypes: openArray[TypeRef]): TypeRef {.inline.} =
  function_t(returnType, paramTypes, isVarArg = LlvmBool(false))

# Functions
# ------------------------------------------------------------

proc createAttr*(ctx: ContextRef, name: openArray[char]): AttributeRef =
  ctx.toAttr(name.toAttrId())

proc toTypes*[N: static int](v: array[N, ValueRef]): array[N, TypeRef] =
  for i in 0 ..< v.len:
    result[i] = v[i].getTypeOf()

macro unpackParams*[N: static int](
        br: BuilderRef,
        paramsTys: tuple[wrapped, src: array[N, TypeRef]]): untyped =
  ## Unpack function parameters.
  ##
  ## The new function basic block MUST be setup before calling unpackParams.
  ##
  ## In the future we may automatically unwrap types.

  result = nnkPar.newTree()
  for i in 0 ..< N:
    result.add quote do:
      # let tySrc = `paramsTys`.src[`i`]
      # let tyCC = `paramsTys`.wrapped[`i`]
      let fn = `br`.getCurrentFunction()
      fn.getParam(uint32 `i`)

# Values
# ------------------------------------------------------------

proc isNil*(v: ValueRef): bool {.borrow.}

proc getName*(v: ValueRef): string =
  var rLen: csize_t
  let rStr = getValueName2(v, rLen)

  result = newString(rLen.int)
  copyMem(result[0].addr, rStr, rLen.int)

proc constInt*(ty: TypeRef, n: SomeInteger, signExtend = false): ValueRef {.inline.} =
  constInt(ty, culonglong(n), LlvmBool(signExtend))
