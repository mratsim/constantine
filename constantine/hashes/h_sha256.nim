# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/[abstractions, endians],
  ./sha256/sha256_generic

when UseASM_X86_32:
  import ./sha256/sha256_x86_ssse3

# SHA256, a hash function from the SHA2 family
# --------------------------------------------------------------------------------
#
# References:
# - NIST: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
# - IETF: US Secure Hash Algorithms (SHA and HMAC-SHA) https://tools.ietf.org/html/rfc4634
# - Intel optimization https://www.intel.com/content/dam/www/public/us/en/documents/white-papers/sha-256-implementations-paper.pdf
# - Parallelizing message schedules
#   to accelerate the computations of hash functions
#   Shay Gueron, Vlad Krasnov, 2012
#   https://eprint.iacr.org/2012/067.pdf
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
    bufIdx: uint8

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
    if ({.noSideEffect.}: hasSSSE3()):
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
  ctx.bufIdx = 0

# Public API
# ----------------------------------------------------------------

template digestSize*(H: type sha256): int =
  ## Returns the output size in bytes
  DigestSize

template internalBlockSize*(H: type sha256): int =
  ## Returns the byte size of the hash function ingested blocks
  BlockSize

func init*(ctx: var Sha256Context) =
  ## Initialize or reinitialize a Sha256 context

  ctx.msgLen = 0
  ctx.buf.setZero()
  ctx.bufIdx = 0

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
  ctx.bufIdx = 0

  ctx.s.H[0] = 0xda5698be'u32
  ctx.s.H[1] = 0x17b9b469'u32
  ctx.s.H[2] = 0x62335799'u32
  ctx.s.H[3] = 0x779fbeca'u32
  ctx.s.H[4] = 0x8ce5d491'u32
  ctx.s.H[5] = 0xc0d26243'u32
  ctx.s.H[6] = 0xbafef9ea'u32
  ctx.s.H[7] = 0x1837a9d8'u32

func update*(ctx: var Sha256Context, message: openarray[byte]) =
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

  debug:
    doAssert: 0 <= ctx.bufIdx and ctx.bufIdx.int < ctx.buf.len
    for i in ctx.bufIdx ..< ctx.buf.len:
      doAssert ctx.buf[i] == 0

  if message.len == 0:
    return

  var # Message processing state machine
    cur = 0'u
    bytesLeft = message.len.uint

  ctx.msgLen += bytesLeft

  if ctx.bufIdx != 0: # Previous partial update
    let bufIdx = ctx.bufIdx.uint
    let free = ctx.buf.sizeof().uint - bufIdx

    if free > bytesLeft:
      # Enough free space, store in buffer
      ctx.buf.copy(dStart = bufIdx, message, sStart = 0, len = bytesLeft)
      ctx.bufIdx += bytesLeft.uint8
      return
    else:
      # Fill the buffer and do one sha256 hash
      ctx.buf.copy(dStart = bufIdx, message, sStart = 0, len = free)
      ctx.hashBuffer()

      # Update message state for further processing
      cur = free
      bytesLeft -= free

  # Process n blocks (64 byte each)
  let numBlocks = bytesLeft div BlockSize
  
  if numBlocks != 0:
    ctx.s.hashMessageBlocks(
      message.asUnchecked +% cur,
      numBlocks)
    let consumed = numBlocks * BlockSize
    cur += consumed
    bytesLeft -= consumed

  if bytesLeft != 0:
    # Store the tail in buffer
    debug: # TODO: state machine formal verification - https://nim-lang.org/docs/drnim.html
      doAssert ctx.bufIdx == 0
      doAssert cur + bytesLeft == message.len.uint

    ctx.buf.copy(dStart = 0'u, message, sStart = cur, len = bytesLeft)
    ctx.bufIdx = uint8 bytesLeft

func update*(ctx: var Sha256Context, message: openarray[char]) {.inline.} =
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
  ctx.update(message.toOpenArrayByte(message.low, message.high))

func finish*(ctx: var Sha256Context, digest: var array[32, byte]) =
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

  debug:
    doAssert: 0 <= ctx.bufIdx and ctx.bufIdx.int < ctx.buf.len
    for i in ctx.bufIdx ..< ctx.buf.len:
      doAssert ctx.buf[i] == 0

  # Add '1' bit at the end of the message (+7 zero bits)
  ctx.buf[ctx.bufIdx] = 0b1000_0000

  # Add k bits so that msgLenBits + 1 + k ≡ 448 mod 512
  # Hence in bytes msgLen + 1 + K ≡ 56 mod 64
  const padZone = 56
  if ctx.bufIdx >= padZone:
    # We are in the 56..<64 mod 64 byte count
    # and need to rollover to 0
    ctx.hashBuffer()

  let lenInBits = ctx.msgLen.uint64 * 8
  ctx.buf.dumpRawInt(lenInBits, padZone, bigEndian)
  ctx.s.hashMessageBlocks(ctx.buf.asUnchecked(), numBlocks = 1)
  digest.dumpHash(ctx.s)

func clear*(ctx: var Sha256Context) =
  ## Clear the context internal buffers
  ## Security note:
  ## For passwords and secret keys, you MUST NOT use raw SHA-256
  ## use a Key Derivation Function instead (KDF)
  # TODO: ensure compiler cannot optimize the code away
  ctx.s.H.setZero()
  ctx.buf.setZero()
  ctx.msgLen = 0
  ctx.bufIdx = 0