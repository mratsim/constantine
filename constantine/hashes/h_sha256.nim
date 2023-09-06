# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../zoo_exports

import
  ../platforms/[abstractions, views],
  ../serialization/endians,
  ./sha256/sha256_generic

when UseASM_X86_32:
  import ./sha256/[
    sha256_x86_ssse3,
    sha256_x86_shaext]

# SHA256, a hash function from the SHA2 family
# --------------------------------------------------------------------------------
#
# References:
# - NIST: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
# - IETF: US Secure Hash Algorithms (SHA and HMAC-SHA) https://tools.ietf.org/html/rfc4634
#
# Vectors:
# - https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf

# Types and constants
# ----------------------------------------------------------------

type
  Sha256Context* = object
    ## Align to 64 for cache line and SIMD friendliness
    s{.align: 64}: Sha256_state
    buf{.align: 64}: array[BlockSize, byte]
    msgLen: uint64

  sha256* = Sha256Context

# Internals
# ----------------------------------------------------------------

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

func hashMessageBlocks(
       s: var Sha256_state,
       message: ptr UncheckedArray[byte],
       numBlocks: uint) =
  when UseASM_X86_32:
    if ({.noSideEffect.}: hasSha()):
      hashMessageBlocks_shaext(s, message, numBlocks)
    elif ({.noSideEffect.}: hasSSSE3()):
      hashMessageBlocks_ssse3(s, message, numBlocks)
    else:
      hashMessageBlocks_generic(s, message, numBlocks)
  else:
    hashMessageBlocks_generic(s, message, numBlocks)

func dumpHash(
       digest: var array[DigestSize, byte],
       s: Sha256_state) {.inline.} =
  ## Convert the internal hash into a message digest
  var dstIdx = 0'u
  for i in 0 ..< s.H.len:
    digest.dumpRawInt(s.H[i], dstIdx, bigEndian)
    dstIdx += uint sizeof(uint32)

func hashBuffer(ctx: var Sha256Context) {.inline.} =
  ctx.s.hashMessageBlocks(ctx.buf.asUnchecked(), numBlocks = 1)
  ctx.buf.setZero()

# Public API
# ----------------------------------------------------------------

template digestSize*(H: type sha256): int =
  ## Returns the output size in bytes
  DigestSize

template internalBlockSize*(H: type sha256): int =
  ## Returns the byte size of the hash function ingested blocks
  BlockSize

func init*(ctx: var Sha256Context) {.libPrefix: prefix_sha256.} =
  ## Initialize or reinitialize a Sha256 context

  ctx.msgLen = 0
  ctx.buf.setZero()

  ctx.s.H[0] = 0x6a09e667'u32
  ctx.s.H[1] = 0xbb67ae85'u32
  ctx.s.H[2] = 0x3c6ef372'u32
  ctx.s.H[3] = 0xa54ff53a'u32
  ctx.s.H[4] = 0x510e527f'u32
  ctx.s.H[5] = 0x9b05688c'u32
  ctx.s.H[6] = 0x1f83d9ab'u32
  ctx.s.H[7] = 0x5be0cd19'u32

func initZeroPadded*(ctx: var Sha256Context) =
  ## Initialize a Sha256 context
  ## with the result of
  ## ctx.init()
  ## ctx.update default(array[BlockSize, byte])
  #
  # This work arounds `toOpenArray`
  # not working in the Nim VM, preventing `sha256.update`
  # at compile-time

  ctx.msgLen = 64
  ctx.buf.setZero()

  ctx.s.H[0] = 0xda5698be'u32
  ctx.s.H[1] = 0x17b9b469'u32
  ctx.s.H[2] = 0x62335799'u32
  ctx.s.H[3] = 0x779fbeca'u32
  ctx.s.H[4] = 0x8ce5d491'u32
  ctx.s.H[5] = 0xc0d26243'u32
  ctx.s.H[6] = 0xbafef9ea'u32
  ctx.s.H[7] = 0x1837a9d8'u32

func update*(ctx: var Sha256Context, message: openarray[byte]) {.libPrefix: prefix_sha256, genCharAPI.} =
  ## Append a message to a SHA256 context
  ## for incremental SHA256 computation
  ##
  ## Security note: the tail of your message might be stored
  ## in an internal buffer.
  ## if sensitive content is used, ensure that
  ## `ctx.finish(...)` and `ctx.clear()` are called as soon as possible.
  ## Additionally ensure that the message(s) passed were stored
  ## in memory considered secure for your threat model.
  ##
  ## For passwords and secret keys, you MUST NOT use raw SHA-256
  ## use a Key Derivation Function instead (KDF)

  # Message processing state machine
  var bufIdx = uint(ctx.msgLen mod BlockSize)
  var cur = 0'u
  var bytesLeft = message.len.uint

  if bufIdx != 0 and bufIdx+bytesLeft >= BlockSize:
    # Previous partial update, fill the buffer and do one sha256 hash
    let free = BlockSize - bufIdx
    ctx.buf.rawCopy(dStart = bufIdx, message, sStart = 0, len = free)
    ctx.hashBuffer()
    bufIdx = 0
    cur = free
    bytesLeft -= free

  if bytesLeft >= BlockSize:
    # Process n blocks (64 byte each)
    let numBlocks = bytesLeft div BlockSize
    ctx.s.hashMessageBlocks(message.asUnchecked +% cur, numBlocks)
    cur += numBlocks * BlockSize
    bytesLeft -= numBlocks * BlockSize

  if bytesLeft != 0:
    # Store the tail in buffer
    ctx.buf.rawCopy(dStart = bufIdx, message, sStart = cur, len = bytesLeft)

  ctx.msgLen += message.len.uint

func finish*(ctx: var Sha256Context, digest: var array[32, byte]) {.libPrefix: prefix_sha256.} =
  ## Finalize a SHA256 computation and output the
  ## message digest to the `digest` buffer.
  ##
  ## Security note: this does not clear the internal buffer.
  ## if sensitive content is used, use "ctx.clear()"
  ## and also make sure that the message(s) passed were stored
  ## in memory considered secure for your threat model.
  ##
  ## For passwords and secret keys, you MUST NOT use raw SHA-256
  ## use a Key Derivation Function instead (KDF)

  let bufIdx = uint(ctx.msgLen mod BlockSize)

  # Add '1' bit at the end of the message (+7 zero bits)
  ctx.buf[bufIdx] = 0b1000_0000

  # Add k bits so that msgLenBits + 1 + k ≡ 448 mod 512
  # Hence in bytes msgLen + 1 + K ≡ 56 mod 64
  const padZone = 56
  if bufIdx >= padZone:
    # We are in the 56..<64 mod 64 byte count
    # and need to rollover to 0
    ctx.hashBuffer()

  let lenInBits = ctx.msgLen.uint64 * 8
  ctx.buf.dumpRawInt(lenInBits, padZone, bigEndian)
  ctx.s.hashMessageBlocks(ctx.buf.asUnchecked(), numBlocks = 1)
  digest.dumpHash(ctx.s)

func clear*(ctx: var Sha256Context) {.libPrefix: prefix_sha256.} =
  ## Clear the context internal buffers
  ## Security note:
  ## For passwords and secret keys, you MUST NOT use raw SHA-256
  ## use a Key Derivation Function instead (KDF)
  # TODO: ensure compiler cannot optimize the code away
  ctx.s.H.setZero()
  ctx.buf.setZero()
  ctx.msgLen = 0
