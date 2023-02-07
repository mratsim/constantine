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
  ./static_for

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

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

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

func copy*[T: byte|char](
       dst: var openArray[byte],
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

  {.push checks: off.} # No OverflowError or IndexError allowed
  for i in 0 ..< len:
    dst[dStart + i] = byte src[sStart + i]

func rotateRight*[N: static int, T](a: var array[N, T]) {.inline.} =
  # Rotate right (Somehow we can't use a generic template here)
  # Inline
  # Hopefully we want the compiler to see that N rounds of rotation
  # can be optimized away with register renaming
  let tmp = a[a.len-1]
  staticForCountdown i, a.len-1, 1:
    a[i] = a[i-1]
  a[0] = tmp

func rotateLeft*[N: static int, T](a: var array[N, T]) {.inline.} =
  # Rotate left (Somehow we can't use a generic template here)
  # Inline
  # Hopefully we want the compiler to see that N rounds of rotation
  # can be optimized away with register renaming
  let tmp = a[0]
  staticFor i, 0, a.len-1:
    a[i] = a[i+1]
  a[a.len-1] = tmp

# ############################################################
#
#                    Pointer arithmetics
#
# ############################################################

template asUnchecked*[T](a: openArray[T]): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](a[0].unsafeAddr)

# Warning for pointer arithmetics via inline C
# be careful of not passing a `var ptr`
# to a function as `var` are passed by hidden pointers in Nim and the wrong
# pointer will be modified. Templates are fine.

func `+%`*(p: ptr, offset: SomeInteger): type(p) {.inline, noInit.}=
  ## Pointer increment
  {.emit: [result, " = ", p, " + ", offset, ";"].}

func `+%=`*(p: var ptr, offset: SomeInteger){.inline.}=
  ## Pointer increment
  p = p +% offset