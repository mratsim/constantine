# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when defined(amd64): # TODO defined(i386) but it seems like RDTSC call is misconfigured
  import platforms/x86
  export getTicks, cpuName

  const SupportsCPUName* = true
  const SupportsGetTicks* = true
else:
  const SupportsCPUName* = false
  const SupportsGetTicks* = false

# Prevent compiler optimizing benchmark away
# -----------------------------------------------
# This doesn't always work unfortunately ...

proc volatilize(x: ptr byte) {.codegenDecl: "$# $#(char const volatile *x)", inline.} =
  discard

template preventOptimAway*[T](x: var T) =
  volatilize(cast[ptr byte](unsafeAddr x))

template preventOptimAway*[T](x: T) =
  volatilize(cast[ptr byte](x))
