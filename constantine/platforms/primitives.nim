# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./config,
  constant_time/[
    ct_types,
    ct_routines,
    multiplexers,
    ct_division
  ],
  intrinsics/[
    addcarry_subborrow,
    extended_precision
  ],
  ./bithacks,
  ./static_for,
  ./allocs

export
  config,
  ct_types,
  ct_routines,
  multiplexers,
  addcarry_subborrow,
  extended_precision,
  ct_division,
  bithacks,
  staticFor,
  allocs

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

func asBytes*(s: static string): auto =
  ## Reinterpret a compile-time string as an array of bytes
  const N = s.len
  var r: array[N, byte]
  for i in 0 ..< s.len:
    r[i] = byte s[i]
  return r

func rawCopy*(
       dst: var openArray[byte],
       dStart: SomeInteger,
       src: openArray[byte],
       sStart: SomeInteger,
       len: SomeInteger) {.inline.} =
  ## Copy dst[dStart ..< dStart+len] = src[sStart ..< sStart+len]
  ## Unlike the standard library, this cannot throw
  ## even a defect.
  debug:
    doAssert 0 <= dStart and int(dStart+len) <= dst.len, "dStart: " & $dStart & ", dStart+len: " & $(dStart+len) & ", dst.len: " & $dst.len
    doAssert 0 <= sStart and int(sStart+len) <= src.len, "sStart: " & $sStart & ", sStart+len: " & $(sStart+len) & ", src.len: " & $src.len

  {.push checks: off.} # No OverflowError or IndexError allowed
  for i in 0 ..< len:
    dst[dStart + i] = src[sStart + i]

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

# ############################################################
#
#                       Prefetching
#
# ############################################################

type
  PrefetchRW* {.size: cint.sizeof.} = enum
    Read = 0
    Write = 1
  PrefetchLocality* {.size: cint.sizeof.} = enum
    NoTemporalLocality = 0 # Data can be discarded from CPU cache after access
    LowTemporalLocality = 1
    ModerateTemporalLocality = 2
    HighTemporalLocality = 3 # Data should be left in all levels of cache possible
    # Translation
    # 0 - use no cache eviction level
    # 1 - L1 cache eviction level
    # 2 - L2 cache eviction level
    # 3 - L1 and L2 cache eviction level

when GCC_Compatible:
  proc builtin_prefetch(data: pointer, rw: PrefetchRW, locality: PrefetchLocality) {.importc: "__builtin_prefetch", noDecl.}

template prefetch*(
            data: ptr or pointer,
            rw: static PrefetchRW = Read,
            locality: static PrefetchLocality = HighTemporalLocality) =
  ## Prefetch examples:
  ##   - https://scripts.mit.edu/~birge/blog/accelerating-code-using-gccs-prefetch-extension/
  ##   - https://stackoverflow.com/questions/7327994/prefetching-examples
  ##   - https://lemire.me/blog/2018/04/30/is-software-prefetching-__builtin_prefetch-useful-for-performance/
  ##   - https://www.naftaliharris.com/blog/2x-speedup-with-one-line-of-code/
  when GCC_Compatible:
    builtin_prefetch(data, rw, locality)
  else:
    discard

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