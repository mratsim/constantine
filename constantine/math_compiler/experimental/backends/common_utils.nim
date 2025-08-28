# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std / tables
import ../gpu_types

proc address*(a: string): string = "&" & a
proc size*(a: string): string = "sizeof(" & a & ")"

proc isGlobal*(fn: GpuAst): bool =
  doAssert fn.kind == gpuProc, "Not a function, but: " & $fn.kind
  result = attGlobal in fn.pAttributes

proc farmTopLevel*(ctx: var GpuContext, ast: GpuAst, kernel: string, varBlock, typBlock: var GpuAst) =
  ## Farms the top level of the code for functions, variable and type definition.
  ## All functions are added to the `allFnTab`, while only global ones (or even only
  ## `kernel` if any) is added to the `fnTab` as the starting point for the remaining
  ## logic.
  ## Variables and types are collected in `varBlock` and `typBlock`.
  case ast.kind
  of gpuProc:
    ctx.allFnTab[ast.pName] = ast
    if kernel.len > 0 and ast.pName.ident() == kernel and ast.isGlobal():
      ctx.fnTab[ast.pName] = ast.clone() # store global function extra
    elif kernel.len == 0 and ast.isGlobal():
      ctx.fnTab[ast.pName] = ast.clone() # store global function extra
  of gpuBlock:
    # could be a type definition or global variable
    for ch in ast:
      ctx.farmTopLevel(ch, kernel, varBlock, typBlock)
  of gpuVar, gpuConstexpr:
    varBlock.statements.add ast
  of gpuTypeDef, gpuAlias:
    typBlock.statements.add ast
  else:
    discard
