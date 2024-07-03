# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO ⚠️:
#   - Constant-time validation for parsing secret keys
#   - Burning memory to ensure secrets are not left after dealloc.

import
  ../platforms/abstractions,
  ./endians

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

# No exceptions for the byte API.
# In particular we don't want if-branches when indexing an array
# that contains secret data
{.push raises: [], checks: off.}

# Note: the parsing/serialization routines were initially developed
#       with an internal representation that used 31 bits out of a uint32
#       or 63-bits out of an uint64

func unmarshalLE[T](
        dst: var openArray[T],
        src: openarray[byte],
        wordBitWidth: static int): bool =
  ## Parse an unsigned integer from its canonical
  ## little-endian unsigned representation
  ## and store it into a BigInt
  ##
  ## Returns "true" on success
  ## Returns "false" if destination buffer is too small
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time
  ##
  ## It is possible to use a 63-bit representation out of a 64-bit words
  ## by setting `wordBitWidth` to something different from sizeof(T) * 8
  ## This might be useful for architectures with no add-with-carry instructions.

  var
    dst_idx = 0
    acc = T(0)
    acc_len = 0

  for src_idx in 0 ..< src.len:
    let src_byte = T(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= wordBitWidth:
      if dst_idx == dst.len:
        return false

      dst[dst_idx] = acc
      inc dst_idx
      acc_len -= wordBitWidth
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.len:
    dst[dst_idx] = acc

  for i in dst_idx + 1 ..< dst.len:
    dst[i] = T(0)

  return true

func unmarshalBE[T](
        dst: var openArray[T],
        src: openarray[byte],
        wordBitWidth: static int): bool =
  ## Parse an unsigned integer from its canonical
  ## big-endian unsigned representation (octet string)
  ## and store it into a BigInt.
  ##
  ## In cryptography specifications, this is often called
  ## "Octet string to Integer"
  ##
  ## Returns "true" on success
  ## Returns "false" if destination buffer is too small
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time
  ##
  ## It is possible to use a 63-bit representation out of a 64-bit words
  ## by setting `wordBitWidth` to something different from sizeof(T) * 8
  ## This might be useful for architectures with no add-with-carry instructions.

  var
    dst_idx = 0
    acc = T(0)
    acc_len = 0

  const wordBitWidth = sizeof(T) * 8

  for src_idx in countdown(src.len-1, 0):
    let src_byte = T(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= wordBitWidth:
      if dst_idx == dst.len:
        return false

      dst[dst_idx] = acc
      inc dst_idx
      acc_len -= wordBitWidth
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.len:
    dst[dst_idx] = acc

  for i in dst_idx + 1 ..< dst.len:
    dst[i] = T(0)

  return true

func unmarshal*[T](
        dst: var openArray[T],
        src: openarray[byte],
        wordBitWidth: static int,
        srcEndianness: static Endianness): bool {.inline, discardable.} =
  ## Parse an unsigned integer from its canonical
  ## big-endian or little-endian unsigned representation
  ##
  ## Returns "true" on success
  ## Returns "false" if destination buffer is too small
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time to embed curve moduli
  ## from a canonical integer representation

  when srcEndianness == littleEndian:
    return dst.unmarshalLE(src, wordBitWidth)
  else:
    return dst.unmarshalBE(src, wordBitWidth)

# ############################################################
#
# Serialising from internal representation to canonical format
#
# ############################################################

func marshalLE[T](
        dst: var openarray[byte],
        src: openArray[T],
        wordBitWidth: static int): bool =
  ## Serialize a bigint into its canonical little-endian representation
  ## I.e least significant bit first
  ##
  ## It is possible to use a 63-bit representation out of a 64-bit words
  ## by setting `wordBitWidth` to something different from sizeof(T) * 8
  ## This might be useful for architectures with no add-with-carry instructions.
  ##
  ## Returns "true" on success
  ## Returns "false" if destination buffer is too small

  var
    src_idx, dst_idx = 0
    acc_len = 0

  when sizeof(T) == 8:
    type BT = uint64
  elif sizeof(T) == 4:
    type BT = uint32
  else:
    {.error "Unsupported word size uint" & $(sizeof(T) * 8).}

  var acc = BT(0)

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.len: BT(src[src_idx])
            else: 0
    inc src_idx

    if acc_len == 0:
      # We need to refill the buffer to output 64-bit
      acc = w
      acc_len = wordBitWidth
    else:
      when wordBitWidth == sizeof(T) * 8:
        let lo = acc
        acc = w
      else: # If using 63-bit (or less) out of uint64
        let lo = (w shl acc_len) or acc
        dec acc_len
        acc = w shr (wordBitWidth - acc_len)

      if tail >= sizeof(T):
        # Unrolled copy
        dst.blobFrom(src = lo, dst_idx, littleEndian)
        dst_idx += sizeof(T)
        tail -= sizeof(T)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[dst_idx+i] = toByte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[dst_idx+i] = toByte(lo shr ((tail-i)*8))

        if src_idx < src.len:
          return false
        else:
          return true

  if src_idx < src.len:
    return false
  else:
    return true

func marshalBE[T](
        dst: var openarray[byte],
        src: openArray[T],
        wordBitWidth: static int): bool =
  ## Serialize a bigint into its canonical big-endian representation
  ## (octet string)
  ## I.e most significant bit first
  ##
  ## In cryptography specifications, this is often called
  ## "Octet string to Integer"
  ##
  ## It is possible to use a 63-bit representation out of a 64-bit words
  ## by setting `wordBitWidth` to something different from sizeof(T) * 8
  ## This might be useful for architectures with no add-with-carry instructions.
  ##
  ## Returns "true" on success
  ## Returns "false" if destination buffer is too small

  var
    src_idx = 0
    acc_len = 0

  when sizeof(T) == 8:
    type BT = uint64
  elif sizeof(T) == 4:
    type BT = uint32
  else:
    {.error "Unsupported word size uint" & $(sizeof(T) * 8).}

  var acc = BT(0)

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.len: BT(src[src_idx])
            else: 0
    inc src_idx

    if acc_len == 0:
      # We need to refill the buffer to output 64-bit
      acc = w
      acc_len = wordBitWidth
    else:
      when wordBitWidth == sizeof(T) * 8:
        let lo = acc
        acc = w
      else: # If using 63-bit (or less) out of uint64
        let lo = (w shl acc_len) or acc
        dec acc_len
        acc = w shr (wordBitWidth - acc_len)

      if tail >= sizeof(T):
        # Unrolled copy
        tail -= sizeof(T)
        dst.blobFrom(src = lo, tail, bigEndian)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[tail-1-i] = toByte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[tail-1-i] = toByte(lo shr ((tail-i)*8))
        if src_idx < src.len:
          return false
        else:
          return true

  if src_idx < src.len:
    return false
  else:
    return true

func marshal*[T](
        dst: var openArray[byte],
        src: openArray[T],
        wordBitWidth: static int,
        dstEndianness: static Endianness): bool {.inline, discardable.} =
  ## Serialize a bigint into its canonical big-endian or little endian
  ## representation.
  ##
  ## If the buffer is bigger, output will be zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## I.e least significant bit is aligned to buffer boundary
  ##
  ## Returns "true" on success
  ## Returns "false" if destination buffer is too small

  when dstEndianness == littleEndian:
    return marshalLE(dst, src, wordBitWidth)
  else:
    return marshalBE(dst, src, wordBitWidth)

{.pop.} # {.push raises: [].}