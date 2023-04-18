# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../hashes,
  ../platforms/[primitives, views]

# HMAC: Keyed-Hashing for Message Authentication
# ----------------------------------------------
#
# https://datatracker.ietf.org/doc/html/rfc2104
#
# Test vectors:
# - https://datatracker.ietf.org/doc/html/rfc4231
# - https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program
#   - http://csrc.nist.gov/groups/STM/cavp/documents/mac/hmactestvectors.zip

{.push raises: [].} # No exceptions

type HMAC*[H: CryptoHash] = object
  inner: H
  outer: H

func init*[H: CryptoHash](ctx: var HMAC[H], secretKey: openArray[byte]) {.genCharAPI.} =
  ## Initialize a HMAC-based Message Authentication Code
  ## with a pre-shared secret key
  ## between the parties that want to authenticate messages between each other.
  ##
  ## Keys should be at least the same size as the hash function output size.
  ##
  ## Keys need to be chosen at random (or using a cryptographically strong
  ## pseudo-random generator seeded with a random seed), and periodically
  ## refreshed.
  var key{.noInit.}: array[H.internalBlockSize(), byte]
  if secretKey.len <= key.len:
    rawCopy(key, 0, secretKey, 0, secretKey.len)
    for i in secretKey.len ..< key.len:
      key[i] = byte 0
  else:
    ctx.inner.init()
    ctx.inner.update(secretKey)
    ctx.inner.finish(cast[ptr array[32, byte]](key.addr)[])
    for i in H.digestSize() ..< key.len:
      key[i] = byte 0

  # Spec: inner hash
  for i in 0 ..< H.internalBlockSize():
    key[i] = key[i] xor byte 0x36

  ctx.inner.init()
  ctx.inner.update(key)

  # Spec: outer hash (by cancelling previous xor)
  for i in 0 ..< H.internalBlockSize():
    key[i] = key[i] xor (byte 0x36 xor byte 0x5C)

  ctx.outer.init()
  ctx.outer.update(key)

func update*[H: CryptoHash](ctx: var HMAC[H], message: openArray[byte]) {.genCharAPI.} =
  ## Append a message to a HMAC authentication context.
  ## for incremental HMAC computation.
  ctx.inner.update(message)

func finish*[H: CryptoHash, N: static int](ctx: var HMAC[H], tag: var array[N, byte]) =
  ## Finalize a HMAC authentication
  ## and output an authentication tag to the `tag` buffer
  ##
  ## Output may be used truncated, with the leftmost bits are kept.
  ## It is recommended that the tag length is at least half the length of the hash output
  ## and at least 80-bits.
  static: doAssert N == H.digestSize()
  ctx.inner.finish(tag)
  ctx.outer.update(tag)
  ctx.outer.finish(tag)

func clear*[H: CryptoHash](ctx: var HMAC[H]) =
  ## Clear the context internal buffers
  # TODO: ensure compiler cannot optimize the code away
  ctx.inner.clear()
  ctx.outer.clear()

func mac*[T0, T1: char|byte, H: CryptoHash, N: static int](
       Hash: type HMAC[H],
       tag: var array[N, byte],
       message: openArray[T0],
       secretKey: openArray[T1],
       clearMem = false) =
  ## Produce an authentication tag from a message
  ## and a preshared unique non-reused secret key
  # TODO: we can't use the {.genCharAPI.} macro
  #       due to 2 openArray[bytes] and the CryptoHash concept
  static: doAssert N == H.digestSize()

  var ctx {.noInit.}: HMAC[H]
  ctx.init(secretKey)
  ctx.update(message)
  ctx.finish(tag)

  if clearMem:
    ctx.clear()
