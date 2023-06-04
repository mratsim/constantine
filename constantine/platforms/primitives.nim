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
  intrinsics/[
    addcarry_subborrow,
    extended_precision,
    compiler_optim_hints
  ],
  ./bithacks,
  ./static_for,
  ./allocs

export
  ct_types,
  ct_routines,
  multiplexers,
  addcarry_subborrow,
  extended_precision,
  ct_division,
  bithacks,
  staticFor,
  allocs,
  compiler_optim_hints

# Note:
# - cpuinfo_x86 initialize globals with following CPU features detection.
#   This will impact benchmarks that do not need it, such as the threadpool.

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
  when defined(CTT_DEBUG):
    body

proc builtin_unreachable(){.nodecl, importc: "__builtin_unreachable".}

func unreachable*() {.noReturn, inline.} =
  doAssert false, "Unreachable"
  when GCC_Compatible:
    builtin_unreachable()

# ############################################################
#
#                       Arithmetic
#
# ############################################################

func ceilDiv_vartime*(a, b: auto): auto {.inline.} =
  ## ceil division, to be used only on length or at compile-time
  ## ceil(a / b)
  # "LengthInDigits: static int" doesn't match "int"
  # if "SomeInteger" is used instead of "auto"
  (a + b - 1) div b

# ############################################################
#
#                         Buffers
#
# ############################################################

func setZero*(a: var openArray[SomeNumber]){.inline.} =
  for i in 0 ..< a.len:
    a[i] = 0

func setOne*(a: var openArray[SomeNumber]){.inline.} =
  a[0] = 1
  for i in 1 ..< a.len:
    a[i] = 0

func rawCopy*(
       dst: var openArray[byte],
       dStart: SomeInteger,
       src: openArray[byte],
       sStart: SomeInteger,
       len: SomeInteger
     ) {.inline.} =
  ## Copy dst[dStart ..< dStart+len] = src[sStart ..< sStart+len]
  ## Unlike the standard library, this cannot throw
  ## even a defect.
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

func `+%`*(p: ptr or pointer, offset: SomeInteger): type(p) {.inline, noInit.}=
  ## Pointer increment
  {.emit: [result, " = ", p, " + ", offset, ";"].}

func `+%=`*(p: var (ptr or pointer), offset: SomeInteger){.inline.}=
  ## Pointer increment
  p = p +% offset

func prefetchLarge*[T](
        data: ptr T,
        rw: static PrefetchRW = Read,
        locality: static PrefetchLocality = HighTemporalLocality,
        maxCacheLines: static int = 0) {.inline.} =
  ## Prefetch a large value
  let pdata = pointer(data)
  const span = sizeof(T) div 64 # 64 byte cache line
  const N = if maxCacheLines == 0: span else: min(span, maxCacheLines)
  for i in 0 ..< N:
    prefetch(pdata +% (i*64), rw, locality)