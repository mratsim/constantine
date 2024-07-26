# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/platforms/llvm/llvm

echo "LLVM JIT compiler Hello World"

let ctx = createContext()
let module = ctx.createModule("addition")
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
  initializeFullNativeTarget()
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
