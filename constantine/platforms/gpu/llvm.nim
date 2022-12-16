# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./bindings/llvm_abi {.all.}
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

{.push hint[Name]: off.}

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

template verify*(module: ModuleRef{lvalue}, failureAction: VerifierFailureAction) =
  ## Verify the IR code in a module
  ## The returned string is empty on success
  var errMsg: LLVMstring
  let err = bool verify(module, failureAction, errMsg)
  if err:
    stderr.write("verification of module '" & astToStr(module) & "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

# Target
# ------------------------------------------------------------

proc initializeNativeTarget* {.inline.} =
  static: doAssert defined(amd64) or defined(i386), "Only x86 is configured at the moment"
  initializeX86TargetInfo()
  initializeX86Target()
  initializeX86TargetMC()

proc initializeNativeAsmPrinter* {.inline.} =
  static: doAssert defined(amd64) or defined(i386), "Only x86 is configured at the moment"
  initializeX86AsmPrinter()

# Execution Engine
# ------------------------------------------------------------

template createJITCompilerForModule*(
       engine: var ExecutionEngineRef,
       module: ModuleRef{lvalue},
       optLevel: uint32) =
  var errMsg: LLVMstring
  let err = bool createJITCompilerForModule(engine, module, optLevel, errMsg)
  if err:
    stderr.write("JIT compiler creation for module '" & astToStr(module) & "' " & $instantiationInfo() & " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

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

proc constInt*(ty: TypeRef, n: uint64, signExtend: bool): ValueRef {.inline.} =
  constInt(ty, culonglong(n), LlvmBool(signExtend))

proc constStruct*(constantVals: openArray[ValueRef], packed = false): ValueRef {.inline.} =
  constStruct(constantVals, LlvmBool(packed))

# ############################################################
#
#                    Sanity Check
#
# ############################################################

when isMainModule:
  echo "LLVM JIT compiler sanity check"

  let ctx = createContext()
  var module = ctx.createModule("addition")
  let i32 = ctx.int32_t()

  let addType = function_t(i32, [i32, i32], isVarArg = LlvmBool(false))
  let addBody = module.addFunction("add", addType)

  let builder = ctx.createBuilder()
  let blck = ctx.appendBasicBlock(addBody, "addBody")
  builder.positionAtEnd(blck)

  block:
    let a = addBody.getParam(0)
    let b = addBody.getParam(1)
    let sum = builder.add(a, b, "sum")
    builder.ret(sum)

  module.verify(AbortProcessAction)

  var engine: ExecutionEngineRef
  block:
    initializeNativeTarget()
    initializeNativeAsmPrinter()
    createJITCompilerForModule(engine, module, optLevel = 0)

  let jitAdd = cast[proc(a, b: int32): int32 {.noconv.}](
    engine.getFunctionAddress("add"))

  echo "jitAdd(1, 2) = ", jitAdd(1, 2)
  doAssert jitAdd(1, 2) == 1 + 2

  block:
    # Cleanup
    builder.dispose()
    engine.dispose()  # also destroys the module attached to it
    ctx.dispose()
  echo "LLVM JIT - SUCCESS"