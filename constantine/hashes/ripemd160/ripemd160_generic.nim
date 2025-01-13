# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## Port of the bitcoin-core implementation of ripemd160:
## https://github.com/bitcoin-core/gui/blob/228aba2c4d9ac0b2ca3edd3c2cdf0a92e55f669b/src/crypto/ripemd160.cpp

import
  constantine/serialization/endians,
  constantine/platforms/abstractions
import std / macros

type Word* = uint32
const
  DigestSize* = 20
  BlockSize* = 64
  HashSize* = DigestSize div sizeof(Word) # 5 uint32 = 20 bytes = 160 bits

type
  Ripemd160Context* = object
    s*: array[HashSize, uint32]
    buf {.align: 64.}: array[BlockSize, byte]
    bytes: uint64

template f1(x, y, z: uint32): untyped = x xor y xor z
template f2(x, y, z: uint32): untyped = (x and y) or ((not x) and z)
template f3(x, y, z: uint32): untyped = (x or (not y)) xor z
template f4(x, y, z: uint32): untyped = (x and z) or (y and (not z))
template f5(x, y, z: uint32): untyped = x xor (y or (not z))

proc initialize*(s: var array[HashSize, uint32]) =
  ## Initialize RIPEMD-160 state.
  s[0] = 0x67452301'u32
  s[1] = 0xEFCDAB89'u32
  s[2] = 0x98BADCFE'u32
  s[3] = 0x10325476'u32
  s[4] = 0xC3D2E1F0'u32

proc initRipemdCtx(): Ripemd160Context =
  result.s.initialize()

template rol(x: uint32, i: int32): untyped = (x shl i) or (x shr (32 - i))

template Round(a: var uint32, b: uint32, c: var uint32, d, e, f, x, k: uint32, r: int32): untyped =
  a = rol(a + f + x + k, r) + e
  c = rol(c, 10)

template R11(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f1(b, c, d), x, 0, r)
template R21(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f2(b, c, d), x, 0x5A827999'u32, r)
template R31(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f3(b, c, d), x, 0x6ED9EBA1'u32, r)
template R41(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f4(b, c, d), x, 0x8F1BBCDC'u32, r)
template R51(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f5(b, c, d), x, 0xA953FD4E'u32, r)

template R12(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f5(b, c, d), x, 0x50A28BE6'u32, r)
template R22(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f4(b, c, d), x, 0x5C4DD124'u32, r)
template R32(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f3(b, c, d), x, 0x6D703EF3'u32, r)
template R42(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f2(b, c, d), x, 0x7A6D76E9'u32, r)
template R52(a: var uint32, b: uint32, c: var uint32, d, e, x: uint32, r: int32): untyped = Round(a, b, c, d, e, f1(b, c, d), x, 0, r)

template ReadLE32(chunk: openArray[byte], offset: int): untyped = uint32.fromBytes(chunk, offset, littleEndian)

macro generateWs(): untyped =
  ## Generates `var w<idx> = ReadLE(chunk, <idx>*4)` for `idx in [0,16]`.
  result = newStmtList()
  for i in 0 ..< 16:
    let wId = ident("w" & $i)
    let idx = i * 4
    result.add quote do:
      var `wId` = ReadLE32(chunk, `idx`)

proc transform(s: var array[HashSize, uint32], chunk: openArray[byte]) =
  ## Perform a RIPEMD-160 transformation, processing a 64-byte chunk. */
  var
    a1 = s[0]
    b1 = s[1]
    c1 = s[2]
    d1 = s[3]
    e1 = s[4]
    a2 = a1
    b2 = b1
    c2 = c1
    d2 = d1
    e2 = e1
  # generate `w<idx>` variables from `chunk`
  generateWs()

  R11(a1, b1, c1, d1, e1, w0 , 11)
  R12(a2, b2, c2, d2, e2, w5 ,  8)
  R11(e1, a1, b1, c1, d1, w1 , 14)
  R12(e2, a2, b2, c2, d2, w14,  9)
  R11(d1, e1, a1, b1, c1, w2 , 15)
  R12(d2, e2, a2, b2, c2, w7 ,  9)
  R11(c1, d1, e1, a1, b1, w3 , 12)
  R12(c2, d2, e2, a2, b2, w0 , 11)
  R11(b1, c1, d1, e1, a1, w4 ,  5)
  R12(b2, c2, d2, e2, a2, w9 , 13)
  R11(a1, b1, c1, d1, e1, w5 ,  8)
  R12(a2, b2, c2, d2, e2, w2 , 15)
  R11(e1, a1, b1, c1, d1, w6 ,  7)
  R12(e2, a2, b2, c2, d2, w11, 15)
  R11(d1, e1, a1, b1, c1, w7 ,  9)
  R12(d2, e2, a2, b2, c2, w4 ,  5)
  R11(c1, d1, e1, a1, b1, w8 , 11)
  R12(c2, d2, e2, a2, b2, w13,  7)
  R11(b1, c1, d1, e1, a1, w9 , 13)
  R12(b2, c2, d2, e2, a2, w6 ,  7)
  R11(a1, b1, c1, d1, e1, w10, 14)
  R12(a2, b2, c2, d2, e2, w15,  8)
  R11(e1, a1, b1, c1, d1, w11, 15)
  R12(e2, a2, b2, c2, d2, w8 , 11)
  R11(d1, e1, a1, b1, c1, w12,  6)
  R12(d2, e2, a2, b2, c2, w1 , 14)
  R11(c1, d1, e1, a1, b1, w13,  7)
  R12(c2, d2, e2, a2, b2, w10, 14)
  R11(b1, c1, d1, e1, a1, w14,  9)
  R12(b2, c2, d2, e2, a2, w3 , 12)
  R11(a1, b1, c1, d1, e1, w15,  8)
  R12(a2, b2, c2, d2, e2, w12,  6)

  R21(e1, a1, b1, c1, d1, w7 ,  7)
  R22(e2, a2, b2, c2, d2, w6 ,  9)
  R21(d1, e1, a1, b1, c1, w4 ,  6)
  R22(d2, e2, a2, b2, c2, w11, 13)
  R21(c1, d1, e1, a1, b1, w13,  8)
  R22(c2, d2, e2, a2, b2, w3 , 15)
  R21(b1, c1, d1, e1, a1, w1 , 13)
  R22(b2, c2, d2, e2, a2, w7 ,  7)
  R21(a1, b1, c1, d1, e1, w10, 11)
  R22(a2, b2, c2, d2, e2, w0 , 12)
  R21(e1, a1, b1, c1, d1, w6 ,  9)
  R22(e2, a2, b2, c2, d2, w13,  8)
  R21(d1, e1, a1, b1, c1, w15,  7)
  R22(d2, e2, a2, b2, c2, w5 ,  9)
  R21(c1, d1, e1, a1, b1, w3 , 15)
  R22(c2, d2, e2, a2, b2, w10, 11)
  R21(b1, c1, d1, e1, a1, w12,  7)
  R22(b2, c2, d2, e2, a2, w14,  7)
  R21(a1, b1, c1, d1, e1, w0 , 12)
  R22(a2, b2, c2, d2, e2, w15,  7)
  R21(e1, a1, b1, c1, d1, w9 , 15)
  R22(e2, a2, b2, c2, d2, w8 , 12)
  R21(d1, e1, a1, b1, c1, w5 ,  9)
  R22(d2, e2, a2, b2, c2, w12,  7)
  R21(c1, d1, e1, a1, b1, w2 , 11)
  R22(c2, d2, e2, a2, b2, w4 ,  6)
  R21(b1, c1, d1, e1, a1, w14,  7)
  R22(b2, c2, d2, e2, a2, w9 , 15)
  R21(a1, b1, c1, d1, e1, w11, 13)
  R22(a2, b2, c2, d2, e2, w1 , 13)
  R21(e1, a1, b1, c1, d1, w8 , 12)
  R22(e2, a2, b2, c2, d2, w2 , 11)

  R31(d1, e1, a1, b1, c1, w3 , 11)
  R32(d2, e2, a2, b2, c2, w15,  9)
  R31(c1, d1, e1, a1, b1, w10, 13)
  R32(c2, d2, e2, a2, b2, w5 ,  7)
  R31(b1, c1, d1, e1, a1, w14,  6)
  R32(b2, c2, d2, e2, a2, w1 , 15)
  R31(a1, b1, c1, d1, e1, w4 ,  7)
  R32(a2, b2, c2, d2, e2, w3 , 11)
  R31(e1, a1, b1, c1, d1, w9 , 14)
  R32(e2, a2, b2, c2, d2, w7 ,  8)
  R31(d1, e1, a1, b1, c1, w15,  9)
  R32(d2, e2, a2, b2, c2, w14,  6)
  R31(c1, d1, e1, a1, b1, w8 , 13)
  R32(c2, d2, e2, a2, b2, w6 ,  6)
  R31(b1, c1, d1, e1, a1, w1 , 15)
  R32(b2, c2, d2, e2, a2, w9 , 14)
  R31(a1, b1, c1, d1, e1, w2 , 14)
  R32(a2, b2, c2, d2, e2, w11, 12)
  R31(e1, a1, b1, c1, d1, w7 ,  8)
  R32(e2, a2, b2, c2, d2, w8 , 13)
  R31(d1, e1, a1, b1, c1, w0 , 13)
  R32(d2, e2, a2, b2, c2, w12,  5)
  R31(c1, d1, e1, a1, b1, w6 ,  6)
  R32(c2, d2, e2, a2, b2, w2 , 14)
  R31(b1, c1, d1, e1, a1, w13,  5)
  R32(b2, c2, d2, e2, a2, w10, 13)
  R31(a1, b1, c1, d1, e1, w11, 12)
  R32(a2, b2, c2, d2, e2, w0 , 13)
  R31(e1, a1, b1, c1, d1, w5 ,  7)
  R32(e2, a2, b2, c2, d2, w4 ,  7)
  R31(d1, e1, a1, b1, c1, w12,  5)
  R32(d2, e2, a2, b2, c2, w13,  5)

  R41(c1, d1, e1, a1, b1, w1 , 11)
  R42(c2, d2, e2, a2, b2, w8 , 15)
  R41(b1, c1, d1, e1, a1, w9 , 12)
  R42(b2, c2, d2, e2, a2, w6 ,  5)
  R41(a1, b1, c1, d1, e1, w11, 14)
  R42(a2, b2, c2, d2, e2, w4 ,  8)
  R41(e1, a1, b1, c1, d1, w10, 15)
  R42(e2, a2, b2, c2, d2, w1 , 11)
  R41(d1, e1, a1, b1, c1, w0 , 14)
  R42(d2, e2, a2, b2, c2, w3 , 14)
  R41(c1, d1, e1, a1, b1, w8 , 15)
  R42(c2, d2, e2, a2, b2, w11, 14)
  R41(b1, c1, d1, e1, a1, w12,  9)
  R42(b2, c2, d2, e2, a2, w15,  6)
  R41(a1, b1, c1, d1, e1, w4 ,  8)
  R42(a2, b2, c2, d2, e2, w0 , 14)
  R41(e1, a1, b1, c1, d1, w13,  9)
  R42(e2, a2, b2, c2, d2, w5 ,  6)
  R41(d1, e1, a1, b1, c1, w3 , 14)
  R42(d2, e2, a2, b2, c2, w12,  9)
  R41(c1, d1, e1, a1, b1, w7 ,  5)
  R42(c2, d2, e2, a2, b2, w2 , 12)
  R41(b1, c1, d1, e1, a1, w15,  6)
  R42(b2, c2, d2, e2, a2, w13,  9)
  R41(a1, b1, c1, d1, e1, w14,  8)
  R42(a2, b2, c2, d2, e2, w9 , 12)
  R41(e1, a1, b1, c1, d1, w5 ,  6)
  R42(e2, a2, b2, c2, d2, w7 ,  5)
  R41(d1, e1, a1, b1, c1, w6 ,  5)
  R42(d2, e2, a2, b2, c2, w10, 15)
  R41(c1, d1, e1, a1, b1, w2 , 12)
  R42(c2, d2, e2, a2, b2, w14,  8)

  R51(b1, c1, d1, e1, a1, w4 ,  9)
  R52(b2, c2, d2, e2, a2, w12,  8)
  R51(a1, b1, c1, d1, e1, w0 , 15)
  R52(a2, b2, c2, d2, e2, w15,  5)
  R51(e1, a1, b1, c1, d1, w5 ,  5)
  R52(e2, a2, b2, c2, d2, w10, 12)
  R51(d1, e1, a1, b1, c1, w9 , 11)
  R52(d2, e2, a2, b2, c2, w4 ,  9)
  R51(c1, d1, e1, a1, b1, w7 ,  6)
  R52(c2, d2, e2, a2, b2, w1 , 12)
  R51(b1, c1, d1, e1, a1, w12,  8)
  R52(b2, c2, d2, e2, a2, w5 ,  5)
  R51(a1, b1, c1, d1, e1, w2 , 13)
  R52(a2, b2, c2, d2, e2, w8 , 14)
  R51(e1, a1, b1, c1, d1, w10, 12)
  R52(e2, a2, b2, c2, d2, w7 ,  6)
  R51(d1, e1, a1, b1, c1, w14,  5)
  R52(d2, e2, a2, b2, c2, w6 ,  8)
  R51(c1, d1, e1, a1, b1, w1 , 12)
  R52(c2, d2, e2, a2, b2, w2 , 13)
  R51(b1, c1, d1, e1, a1, w3 , 13)
  R52(b2, c2, d2, e2, a2, w13,  6)
  R51(a1, b1, c1, d1, e1, w8 , 14)
  R52(a2, b2, c2, d2, e2, w14,  5)
  R51(e1, a1, b1, c1, d1, w11, 11)
  R52(e2, a2, b2, c2, d2, w0 , 15)
  R51(d1, e1, a1, b1, c1, w6 ,  8)
  R52(d2, e2, a2, b2, c2, w3 , 13)
  R51(c1, d1, e1, a1, b1, w15,  5)
  R52(c2, d2, e2, a2, b2, w9 , 11)
  R51(b1, c1, d1, e1, a1, w13,  6)
  R52(b2, c2, d2, e2, a2, w11, 11)

  let t = s[0]
  s[0] = s[1] + c1 + d2
  s[1] = s[2] + d1 + e2
  s[2] = s[3] + e1 + a2
  s[3] = s[4] + a1 + b2
  s[4] = t + b1 + c2

template `+!`(x: openArray[byte], offset: int|uint64): untyped = cast[pointer](cast[uint64](x[0].addr) + uint64(offset))

proc write*(ctx: var Ripemd160Context, data: openArray[byte], length: uint64) =
  var bufsize = ctx.bytes mod 64
  var dataPos = 0'u64
  if bufsize > 0 and bufsize + length >= 64:
    # Fill the buffer, and process it.
    copyMem(ctx.buf +! bufsize, data +! dataPos, 64 - bufsize)
    ctx.bytes += 64 - bufsize
    dataPos += 64 - bufsize
    ctx.s.transform(ctx.buf)
    bufsize = 0

  while length - dataPos >= 64:
    # Process full chunks directly from the source.
    ctx.s.transform(toOpenArray(data, dataPos.int, length.int - 1))
    ctx.bytes += 64
    dataPos += 64

  if length > dataPos:
    # Fill the buffer with what remains.
    copyMem(ctx.buf +! bufsize, data +! dataPos, length - dataPos)
    ctx.bytes += length - dataPos

template ReadLE32(chunk: openArray[byte], offset: int): untyped = uint32.fromBytes(chunk, offset, littleEndian)

proc arrayFirst(x: byte): array[64, byte] = result[0] = x

proc finalize*(ctx: var Ripemd160Context, hash: var array[DigestSize, byte]) =
  const pad: array[64, byte] = arrayFirst(0x80)
  var sizedesc: array[8, byte]
  sizedesc.blobFrom(ctx.bytes shl 3, 0, littleEndian)

  ctx.write(pad, 1 + ((119 - (ctx.bytes mod 64)) mod 64))
  ctx.write(sizedesc, 8)

  hash.blobFrom(ctx.s[0],  0, littleEndian)
  hash.blobFrom(ctx.s[1],  4, littleEndian)
  hash.blobFrom(ctx.s[2],  8, littleEndian)
  hash.blobFrom(ctx.s[3], 12, littleEndian)
  hash.blobFrom(ctx.s[4], 16, littleEndian)

proc reset*(ctx: var Ripemd160Context) =
  ctx.bytes = 0
  ctx.s.initialize()
  ctx.buf.setZero()
