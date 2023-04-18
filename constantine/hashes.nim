# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import platforms/views

# ############################################################
#
#                Hash Function concept
#
# ############################################################

type
  CryptoHash* = concept h, var ctx, type H
    ## Interface of a cryptographic hash function
    ##
    ## - digestSizeInBytes is the hash output size in bytes
    ## - internalBlockSize, in bits:
    ##   hash functions are supposed to ingest fixed block size
    ##   that are padded if necessary
    ##   - SHA256 block size is 64 bits
    ##   - SHA512 block size is 128 bits
    ##   - SHA3-512 block size is 72 bits

    # should we avoid int to avoid exception? But they are compile-time
    H.digestSize is static int
    H.internalBlockSize is static int

    # Context
    # -------------------------------------------
    ctx.init()
    ctx.update(openarray[byte])
    ctx.finish(var array[H.digestSize, byte])
    ctx.clear()

func hash*[DigestSize: static int](
       HashKind: type CryptoHash,
       digest: var array[DigestSize, byte],
       message: openArray[byte],
       clearMem = false) {.genCharAPI.} =
  ## Produce a digest from a message
  static: doAssert DigestSize == HashKind.type.digestSize

  var ctx {.noInit.}: HashKind
  ctx.init()
  ctx.update(message)
  ctx.finish(digest)

  if clearMem:
    ctx.clear()

func hash*(
       HashKind: type CryptoHash,
       message: openArray[byte],
       clearmem = false): array[HashKind.digestSize, byte] {.noInit, genCharAPI.} =
  ## Produce a digest from a message
  HashKind.hash(result, message, clearMem)

# Exports
# -----------------------------------------------------------------------

import ./hashes/h_sha256
export h_sha256

static: doAssert sha256 is CryptoHash
