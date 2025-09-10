# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./common_builtins

type
  DimWgsl = uint32
  WgslGridDim = object
    x*: DimWgsl
    y*: DimWgsl
    z*: DimWgsl

## WebGPU specific
let global_id* {.builtin.} = WgslGridDim()
let num_workgroups* {.builtin.} = WgslGridDim()

## WebGPU select
proc select*[T](f, t: T, cond: bool): T {.builtin.} =
  # Implementation to run WebGPU code on CPU
  if cond: t
  else: f
