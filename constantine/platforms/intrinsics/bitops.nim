# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../config

when GCC_Compatible:
  func builtin_clz(n: uint32): cint {.importc: "__builtin_clz", nodecl.}
    ## Count the number of leading zeros
    ## undefined if n is zero
  func builtin_clzll(n: uint64): cint {.importc: "__builtin_clzll", nodecl.}
    ## Count the number of leading zeros
    ## undefined if n is zero
  func builtin_ctz(n: uint32): cint {.importc: "__builtin_ctz", nodecl.}
    ## Count the number of trailing zeros
    ## undefined if n is zero
  func builtin_ctzll(n: uint64): cint {.importc: "__builtin_ctzll", nodecl.}
    ## Count the number of trailing zeros
    ## undefined if n is zero

  func log2_c_compiler_vartime*(n: SomeUnsignedInt): cint {.inline.} =
    ## Compute the log2 of n using compiler builtin
    ## ⚠ Depending on the compiler:
    ## - It is undefined if n == 0
    ## - It is not constant-time as a zero input is checked
    if n == 0:
      0
    else:
      when sizeof(n) == 8:
        cint(63) - builtin_clzll(n)
      else:
        cint(31) - builtin_clz(n.uint32)

  func ctz_c_compiler_vartime*(n: SomeUnsignedInt): cint {.inline.} =
    ## Compute the number of trailing zeros
    ## in the bit representation of n using compiler builtin
    ## ⚠ Depending on the compiler:
    ## - It is undefined if n == 0
    ## - It is not constant-time as a zero input is checked
    if n == 0:
      sizeof(n) * 8
    else:
      when sizeof(n) == 8:
        builtin_ctzll(n)
      else:
        builtin_ctz(n.uint32)

  func builtin_swapBytes(n: uint32): uint32 {.importc: "__builtin_bswap32", nodecl.}
  func builtin_swapBytes(n: uint64): uint64 {.importc: "__builtin_bswap64", nodecl.}

  func swapBytes_c_compiler*(n: SomeUnsignedInt): SomeUnsignedInt {.inline.} =
    builtin_swapBytes(n)

elif defined(icc):
  func bitScanReverse(r: var uint32, n: uint32): uint8 {.importc: "_BitScanReverse", header: "<immintrin.h>".}
    ## Returns 0 if n is zero and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from MSB to LSB
  func bitScanReverse64(r: var uint32, n: uint64): uint8 {.importc: "_BitScanReverse64", header: "<immintrin.h>".}
    ## Returns 0 if n is zero and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from MSB to LSB
  func bitScanForward(r: var uint32, n: uint32): uint8 {.importc: "_BitScanForward", header: "<immintrin.h>".}
    ## Returns 0 if n is zero and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from LSB to MSB
  func bitScanForward64(r: var uint32, n: uint64): uint8 {.importc: "_BitScanForward64", header: "<immintrin.h>".}
    ## Returns 0 if n is zero and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from LSB to MSB

  template bitscan(fnc: untyped; v: untyped, default: static int): int {.inline.} =
    var index: uint32
    if fnc(index.addr, v) == 0:
      return default
    return index.int

  func log2_c_compiler_vartime*(n: SomeUnsignedInt): cint {.inline.} =
    ## Compute the log2 of n using compiler builtin
    ## ⚠ Depending on the compiler:
    ## - It is undefined if n == 0
    ## - It is not constant-time as a zero input is checked
    when sizeof(n) == 8:
      bitscan(bitScanReverse64, n, default = 0)
    else:
      bitscan(bitScanReverse, c.uint32, default = 0)

  func ctz_c_compiler_vartime*(n: SomeUnsignedInt): cint {.inline.} =
    ## Compute the number of trailing zero bits of n using compiler builtin
    ## ⚠ Depending on the compiler:
    ## - It is undefined if n == 0
    ## - It is not constant-time as a zero input is checked
    when sizeof(n) == 8:
      bitscan(bitScanForward64, n, default = 0)
    else:
      bitscan(bitScanForward, c.uint32, default = 0)

  func builtin_swapBytes(n: uint32): uint32 {.importc: "_bswap", nodecl.}
  func builtin_swapBytes(n: uint64): uint64 {.importc: "_bswap64", nodecl.}

  func swapBytes_c_compiler*(n: SomeUnsignedInt): SomeUnsignedInt {.inline.} =
    builtin_swapBytes(n)

elif defined(vcc):
  func bitScanReverse(p: ptr uint32, b: uint32): uint8 {.importc: "_BitScanReverse", header: "<intrin.h>".}
    ## Returns 0 if n s no set bit and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from MSB to LSB
  func bitScanReverse64(p: ptr uint32, b: uint64): uint8 {.importc: "_BitScanReverse64", header: "<intrin.h>".}
    ## Returns 0 if n s no set bit and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from MSB to LSB
  func bitScanForward(r: var uint32, n: uint32): uint8 {.importc: "_BitScanForward", header: "<intrin.h>".}
    ## Returns 0 if n is zero and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from LSB to MSB
  func bitScanForward64(r: var uint32, n: uint64): uint8 {.importc: "_BitScanForward64", header: "<intrin.h>".}
    ## Returns 0 if n is zero and non-zero otherwise
    ## Returns the position of the first set bit in `r`
    ## from LSB to MSB

  template bitscan(fnc: untyped; v: untyped): int =
    var index: uint32
    if fnc(index.addr, v) == 0:
      return 0
    return index.int

  func log2_c_compiler_vartime*(n: SomeUnsignedInt): cint {.inline.} =
    ## Compute the log2 of n using compiler builtin
    ## ⚠ Depending on the compiler:
    ## - It is undefined if n == 0
    ## - It is not constant-time as a zero input is checked
    when sizeof(n) == 8:
      bitscan(bitScanReverse64, n, default = 0)
    else:
      bitscan(bitScanReverse, c.uint32, default = 0)

  func ctz_c_compiler_vartime*(n: SomeUnsignedInt): cint {.inline.} =
    ## Compute the number of trailing zero bits of n using compiler builtin
    ## ⚠ Depending on the compiler:
    ## - It is undefined if n == 0
    ## - It is not constant-time as a zero input is checked
    when sizeof(n) == 8:
      bitscan(bitScanForward64, n, default = sizeof(n) * 8)
    else:
      bitscan(bitScanForward, c.uint32, default = sizeof(n) * 8)

  func builtin_swapBytes(n: uint32): uint32 {.importc: "_byteswap_ulong", cdecl, header: "<intrin.h>".}
  func builtin_swapBytes(n: uint64): uint64 {.importc: "_byteswap_uint64", cdecl, header: "<intrin.h>".}

  func swapBytes_c_compiler*(n: SomeUnsignedInt): SomeUnsignedInt {.inline.} =
    builtin_swapBytes(n)

else:
  {. error: "Unsupported compiler".}