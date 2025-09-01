# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std / [macros, strutils, sequtils, options, sugar, tables, strformat, hashes, sets]

import ./gpu_types
import ./backends/backends
import ./nim_to_gpu

export gpu_types

template nimonly*(): untyped {.pragma.}
template cudaName*(s: string): untyped {.pragma.}

## Dummy data for the typed nature of the `cuda` macro. These define commonly used
## CUDA specific names so that they produce valid Nim code in the context of a typed macro.
template global*() {.pragma.}
template device*() {.pragma.}
template forceinline*() {.pragma.}

# If attached to a `var` it will be treated as a
# `__constant__`! Only useful if you want to define a
# constant without initializing it (and then use
# `cudaMemcpyToSymbol` / `copyToSymbol` to initialize it
# before executing the kernel)
template constant*() {.pragma.}
type
  Dim* = cint ## dummy to have access to math
  NvBlockIdx* = object
    x*: Dim
    y*: Dim
    z*: Dim
  NvBlockDim = object
    x*: Dim
    y*: Dim
    z*: Dim
  NvThreadIdx* = object
    x*: Dim
    y*: Dim
    z*: Dim
  NvGridDim = object
    x*: Dim
    y*: Dim
    z*: Dim

  DimWgsl = uint32
  WgslGridDim = object
    x*: DimWgsl
    y*: DimWgsl
    z*: DimWgsl


## These are dummy elements to make CUDA block / thread index / dim
## access possible in the *typed* `cuda` macro. It cannot be `const`,
## because then the typed code would evaluate the values before we
## can work with it from the typed macro.
let blockIdx* = NvBlockIdx()
let blockDim* = NvBlockDim()
let gridDim* = NvGridDim()
let threadIdx* = NvThreadIdx()

## WebGPU specific
let global_id* = WgslGridDim()

## Similar for procs. They don't need any implementation, as they won't ever be actually called.
proc printf*(fmt: string) {.varargs.} = discard
proc memcpy*(dst, src: pointer, size: int) = discard

## WebGPU select
proc select*[T](f, t: T, cond: bool): T =
  # Implementation to run WebGPU code on CPU
  if cond: t
  else: f

## `cuExtern` is mapped to `extern`, but has a different name, because Nim has its
## own `extern` pragma (due to requiring an argument it cannot be reused):
## https://nim-lang.org/docs/manual.html#foreign-function-interface-extern-pragma
template cuExtern*(): untyped {.pragma.}
template shared*(): untyped {.pragma.}
template private*(): untyped {.pragma.}
## You would typically use `cuExtern` and `shared` together:
## `var x {.cuExtern, shared.}: array[N, Foo]`
## for example to declare a constant array that is filled by the
## host before kernel execution.

## While you can use `malloc` on device with small sizes, it is usually not
## recommended to do so.
proc malloc*(size: csize_t): pointer  = discard
proc free*(p: pointer) = discard
proc syncthreads*() {.cudaName: "__syncthreads".} = discard

macro toGpuAst*(body: typed): GpuAst =
  ## WARNING: The following are *not* supported:
  ## - UFCS: because this is a pure untyped DSL, there is no way to disambiguate between
  ##         what is a field access and a function call. Hence we assume any `nnkDotExpr`
  ##         is actually a field access!
  ## - most regular Nim features :)
  echo body.treerepr
  echo body.repr
  var ctx = GpuContext()
  newLit(ctx.toGpuAst(body))

macro cuda*(body: typed): string =
  ## WARNING: The following are *not* supported:
  ## - UFCS: because this is a pure untyped DSL, there is no way to disambiguate between
  ##         what is a field access and a function call. Hence we assume any `nnkDotExpr`
  ##         is actually a field access!
  ## - most regular Nim features :)
  #echo body.treerepr
  var ctx = GpuContext()
  let gpuAst = ctx.toGpuAst(body)
  # NOTE: it doesn't seem like it's possible to add a header to a NVRTC kernel.
  # NVRTC safe stdlib is implemented at https://github.com/NVIDIA/jitify
  let body = ctx.codegen(gpuAst)
  result = newLit(body)

proc codegen*(ast: GpuAst, kernel: string = ""): string =
  ## Generates the code based on the given AST (optionally at runtime) and restricts
  ## it to a single global kernel (WebGPU) if any given.
  let ast = ast.clone() ## XXX: remove clone
  var ctx = GpuContext()
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
