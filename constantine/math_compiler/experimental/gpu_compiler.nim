# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/[macros, sequtils, tables]

import ./gpu_types
import ./backends/backends
import ./nim_to_gpu

export gpu_types

import builtins/builtins # all the builtins for the backend to make the Nim compiler happy
export builtins

macro toGpuAst*(body: typed): (GpuGenericsInfo, GpuAst) =
  ## Converts the body of this macro into a `GpuAst` from where it can be converted
  ## into CUDA or WGSL code at runtime.
  var ctx = GpuContext()
  let ast = ctx.toGpuAst(body)
  let genProcs = toSeq(ctx.genericInsts.values)
  let genTypes = toSeq(ctx.types.values)
  let g = GpuGenericsInfo(procs: genProcs, types: genTypes)
  newLit((g, ast))

macro cuda*(body: typed): string =
  ## Converts the body of this macro into a `GpuAst` and from there into a string of
  ## CUDA or WGSL code.
  ##
  ## TODO: make `cuda` choose CUDA backend, `wgsl` WGSL etc. Need to change code
  ## that chooses backend etc.
  #echo body.treerepr
  var ctx = GpuContext()
  let gpuAst = ctx.toGpuAst(body)
  # NOTE: it doesn't seem like it's possible to add a header to a NVRTC kernel.
  # NVRTC safe stdlib is implemented at https://github.com/NVIDIA/jitify
  let body = ctx.codegen(gpuAst)
  result = newLit(body)

proc codegen*(gen: GpuGenericsInfo, ast: GpuAst, kernel: string = ""): string =
  ## Generates the code based on the given AST (optionally at runtime) and restricts
  ## it to a single global kernel (WebGPU) if any given.
  var ctx = GpuContext()
  for fn in gen.procs: # assign generics info to correct table
    ctx.genericInsts[fn.pName] = fn
  for typ in gen.types: # assign generics info to correct table
    case typ.kind
    of gpuTypeDef:
      ctx.types[typ.tTyp] = typ
    of gpuAlias:
      ctx.types[typ.aTyp] = typ
    else: raiseAssert "Unexpected node kind assigning to `types`: " & $typ
  result = ctx.codegen(ast, kernel)


when isMainModule:
  # Mini example
  let kernel = cuda:
    proc square(x: float32): float32 {.device.} =
      if x < 0.0'f32:
        result = 0.0'f32
      else:
        result = x * x

    proc computeSquares(
      output: ptr float32,
      input: ptr float32,
      n: int32
    ) {.global.} =
      let idx: uint32 = blockIdx.x * blockDim.x + threadIdx.x
      if idx < n:
        var temp: float32 = 0.0'f32
        for i in 0..<4:
          temp += square(input[idx + i * n])
        output[idx] = temp

  echo kernel
