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

proc codegen*(ctx: var GpuContext, ast: GpuAst, kernel: string = ""): string =
  case Backend
  of bkCuda:
    cuda.preprocess(ctx, ast, kernel)
    result = cuda.codegen(ctx)
  of bkWGSL:
    wgsl.preprocess(ctx, ast, kernel)
    result = wgsl.codegen(ctx)
