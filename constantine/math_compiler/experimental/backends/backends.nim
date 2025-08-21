# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./cuda, ./wgsl
import ../gpu_types

when defined(cuda):
  const Backend* = bkCuda
else:
  const Backend* = bkWGSL

proc gpuTypeToString*(t: GpuTypeKind): string =
  case Backend
  of bkCuda: cuda.gpuTypeToString(t)
  of bkWGSL: wgsl.gpuTypeToString(t)

proc gpuTypeToString*(t: GpuType, ident = newGpuIdent(), allowArrayToPtr = false,
                      allowEmptyIdent = false,
                     ): string =
  case Backend
  of bkCuda: cuda.gpuTypeToString(t, ident.ident(), allowArrayToPtr, allowEmptyIdent)
  of bkWGSL: wgsl.gpuTypeToString(t, ident, allowArrayToPtr, allowEmptyIdent)

proc genFunctionType*(typ: GpuType, fn: string, fnArgs: string): string =
  case Backend
  of bkCuda: cuda.genFunctionType(typ, fn, fnArgs)
  of bkWGSL: wgsl.genFunctionType(typ, fn, fnArgs)

proc codegen*(ctx: var GpuContext, ast: GpuAst, kernel: string = ""): string =
  case Backend
  of bkCuda:
    ctx.preprocess(ast, kernel)
    result = cuda.codegen(ctx)
  of bkWGSL:
    ctx.storagePass(ast, kernel)
    result = wgsl.codegen(ctx)
