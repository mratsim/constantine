# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constant_time/[
    ct_types,
    ct_routines,
    multiplexers,
    ct_division
  ],
  compilers/[
    addcarry_subborrow,
    extended_precision
  ],
  ./bithacks,
  ../../../helpers/static_for

export
  ct_types,
  ct_routines,
  multiplexers,
  addcarry_subborrow,
  extended_precision,
  ct_division,
  bithacks,
  staticFor

when X86 and GCC_Compatible:
  import isa/[cpuinfo_x86, macro_assembler_x86]
  export cpuinfo_x86, macro_assembler_x86

# ############################################################
#
#                      Instrumentation
#
# ############################################################

template debug*(body: untyped): untyped =
  when defined(debugConstantine):
    body

# ############################################################
#
#                         Buffers
#
# ############################################################

func setZero*[N](a: var array[N, SomeNumber]){.inline.} =
  for i in 0 ..< a.len:
    a[i] = 0

func copy*[N: static int, T: byte|char](
       dst: var array[N, byte],
       dStart: SomeInteger,
       src: openArray[T],
       sStart: SomeInteger,
       len: SomeInteger
     ) {.inline.} =
  ## Copy dst[dStart ..< dStart+len] = src[sStart ..< sStart+len]
  ## Unlike the standard library, this cannot throw
  ## even a defect.
  ## It also handles copy of char into byte arrays
  debug:
    doAssert 0 <= dStart and dStart+len <= dst.len.uint, "dStart: " & $dStart & ", dStart+len: " & $(dStart+len) & ", dst.len: " & $dst.len
    doAssert 0 <= sStart and sStart+len <= src.len.uint, "sStart: " & $sStart & ", sStart+len: " & $(sStart+len) & ", src.len: " & $src.len

  for i in 0 ..< len:
    dst[dStart + i] = byte src[sStart + i]