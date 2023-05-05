# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/views,
  ../serialization/endians

# ############################################################
#
#                     ChaCha20 stream cipher
#
# ############################################################

# Implementation of IETF ChaCha20 stream cipher
# https://datatracker.ietf.org/doc/html/rfc8439
# ---------------------------------------------

{.push raises:[].}  # No exceptions for crypto
{.push checks:off.} # We want unchecked int and array accesses

template rotl(x, n: uint32): uint32 =
  ## Rotate left the bits
  # We always use it with constants in 0 ..< 32
  # so no undefined behaviour.
  (x shl n) or (x shr (32 - n))
template `^=`(x: var uint32, y: uint32) =
  x = x xor y
template `<<<=`(x: var uint32, n: uint32) =
  x = x.rotl(n)

template quarter_round(a, b, c, d: var uint32) =
  a += b; d ^= a; d <<<= 16
  c += d; b ^= c; b <<<= 12
  a += b; d ^= a; d <<<= 8
  c += d; b ^= c; b <<<= 7

template qround(state: var array[16, uint32], x, y, z, w: int) =
  quarterRound(state[x], state[y], state[z], state[w])

template inner_block(s: var array[16, uint32]) =
  # State
  #  0   1   2   3
  #  4   5   6   7
  #  8   9  10  11
  # 12  13  14  15

  # Column rounds
  state.qround(0, 4, 8, 12)
  state.qround(1, 5, 9, 13)
  state.qround(2, 6, 10, 14)
  state.qround(3, 7, 11, 15)
  # Diagonal rounds
  state.qround(0, 5, 10, 15)
  state.qround(1, 6, 11, 12)
  state.qround(2, 7, 8, 13)
  state.qround(3, 4, 9, 14)

func chacha20_block(
       key_stream: var array[64, byte],
       key: array[8, uint32],
       block_counter: uint32,
       nonce: array[3, uint32]) =
  const cccc = [uint32 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
  var state{.noInit.}: array[16, uint32]

  for i in 0 ..< 4:
    state[i] = cccc[i]
  for i in 4 ..< 12:
    state[i] = key[i-4]
  state[12] = block_counter
  for i in 13 ..< 16:
    state[i] = nonce[i-13]

  for i in 0 ..< 10:
    state.inner_block()

  # uint32 are 4 bytes so multiply destination by 4
  for i in 0'u ..< 4:
    key_stream.dumpRawInt(state[i] + cccc[i], i shl 2, littleEndian)
  for i in 4'u ..< 12:
    key_stream.dumpRawInt(state[i] + key[i-4], i shl 2, littleEndian)
  key_stream.dumpRawInt(state[12] + block_counter, 12 shl 2, littleEndian)
  for i in 13'u ..< 16:
    key_stream.dumpRawInt(state[i] + nonce[i-13], i shl 2, littleEndian)

func chacha20_cipher*(
       key: array[32, byte],
       counter: uint32,
       nonce: array[12, byte],
       data: var openArray[byte]): uint32 {.genCharAPI.} =
  ## Encrypt or decrypt `data` using the ChaCha20 cipher
  ## - `key` is a 256-bit (32 bytes) secret shared encryption/decryption key.
  ## - `counter`. A monotonically increasing value per encryption.
  ##    The counter can be initially set to any value.
  ## - `nonce` (Number-used-once), nonce MUST NOT be reused for the same key.
  ##   If multiple senders are using the same key,
  ##   `nonce` MUST be made unique per sender.
  ##
  ## Encryption/decryption is done in-place.
  ## Returns the new counter
  var keyU{.noInit.}: array[8, uint32]
  var nonceU{.noInit.}: array[3, uint32]

  var pos = 0'u
  for i in 0 ..< 8:
    keyU[i].parseFromBlob(key, pos, littleEndian)
  pos = 0'u
  for i in 0 ..< 3:
    nonceU[i].parseFromBlob(nonce, pos, littleEndian)

  var counter = counter
  var eaten = 0
  while eaten < data.len:
    var key_stream{.noInit.}: array[64, byte]
    key_stream.chacha20_block(keyU, counter, nonceU)

    # Plaintext length can be leaked, it doesn't reveal the content.
    for i in eaten ..< min(eaten+64, data.len):
      data[i].byte() ^= key_stream[i-eaten]

    eaten += 64
    counter += 1

  return counter