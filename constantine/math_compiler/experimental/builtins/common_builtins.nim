# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

#import std / [macros, strutils, sequtils, options, sugar, tables, strformat, hashes, sets]
#
#import ./gpu_types
#import ./backends/backends
#import ./nim_to_gpu
#
#export gpu_types

template nimonly*(): untyped {.pragma.}
template cudaName*(s: string): untyped {.pragma.}

## Dummy data for the typed nature of the `cuda` macro. These define commonly used
## CUDA specific names so that they produce valid Nim code in the context of a typed macro.
template global*() {.pragma.}
template device*() {.pragma.}
template forceinline*() {.pragma.}

## If attached to a function, type or variable it will refer to a built in
## in the target backend. This is used for all the functions, types and variables
## defined below to indicate that we do not intend to generate code for them.
template builtin*() {.pragma.}
# If attached to a `var` it will be treated as a
# `__constant__`! Only useful if you want to define a
# constant without initializing it (and then use
# `cudaMemcpyToSymbol` / `copyToSymbol` to initialize it
# before executing the kernel)
template constant*() {.pragma.}

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
