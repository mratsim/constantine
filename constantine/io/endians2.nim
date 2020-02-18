# Copyright (c) 2018-2019 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# From https://github.com/status-im/nim-stew/blob/master/stew/endians2.nim
#
# Nim standard library "endians" work with pointers which doesn't work at compile-time
# For auditing purpose and to ensure constant-time safety
# it's better not to introduce a dependency for such a small piece of code

type
  SomeEndianInt* = uint8|uint16|uint32|uint64
    ## types that we support endian conversions for - uint8 is there for
    ## for syntactic / generic convenience. Other candidates:
    ## * int/uint - uncertain size, thus less suitable for binary interop
    ## * intX - over and underflow protection in nim might easily cause issues -
    ##          need to consider before adding here

when defined(gcc) or defined(llvm_gcc) or defined(clang):
  func swapBytesBuiltin(x: uint8): uint8 = x
  func swapBytesBuiltin(x: uint16): uint16 {.
      importc: "__builtin_bswap16", nodecl.}

  func swapBytesBuiltin(x: uint32): uint32 {.
      importc: "__builtin_bswap32", nodecl.}

  func swapBytesBuiltin(x: uint64): uint64 {.
      importc: "__builtin_bswap64", nodecl.}

elif defined(icc):
  func swapBytesBuiltin(x: uint8): uint8 = x
  func swapBytesBuiltin(a: uint16): uint16 {.importc: "_bswap16", nodecl.}
  func swapBytesBuiltin(a: uint32): uint32 {.importc: "_bswap", nodec.}
  func swapBytesBuiltin(a: uint64): uint64 {.importc: "_bswap64", nodecl.}

elif defined(vcc):
  func swapBytesBuiltin(x: uint8): uint8 = x
  proc builtin_bswap16(a: uint16): uint16 {.
      importc: "_byteswap_ushort", cdecl, header: "<intrin.h>".}

  proc builtin_bswap32(a: uint32): uint32 {.
      importc: "_byteswap_ulong", cdecl, header: "<intrin.h>".}

  proc builtin_bswap64(a: uint64): uint64 {.
      importc: "_byteswap_uint64", cdecl, header: "<intrin.h>".}

func swapBytesNim(x: uint8): uint8 = x
func swapBytesNim(x: uint16): uint16 = (x shl 8) or (x shr 8)

func swapBytesNim(x: uint32): uint32 =
  let v = (x shl 16) or (x shr 16)

  ((v shl 8) and 0xff00ff00'u32) or ((v shr 8) and 0x00ff00ff'u32)

func swapBytesNim(x: uint64): uint64 =
  var v = (x shl 32) or (x shr 32)
  v =
    ((v and 0x0000ffff0000ffff'u64) shl 16) or
    ((v and 0xffff0000ffff0000'u64) shr 16)

  ((v and 0x00ff00ff00ff00ff'u64) shl 8) or
    ((v and 0xff00ff00ff00ff00'u64) shr 8)

template swapBytes*[T: SomeEndianInt](x: T): T =
  ## Reverse the bytes within an integer, such that the most significant byte
  ## changes place with the least significant one, etc
  ##
  ## Example:
  ## doAssert swapBytes(0x01234567'u32) == 0x67452301
  when nimvm:
    swapBytesNim(x)
  else:
    when defined(swapBytesBuiltin):
      swapBytesBuiltin(x)
    else:
      swapBytesNim(x)
