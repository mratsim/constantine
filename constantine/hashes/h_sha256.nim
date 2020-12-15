# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../io/endians

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

const
  DigestSize = 32
  BlockSize = 64
  HashSize = DigestSize div sizeof(uint32) # 8

type
  Sha256Context* = object
    ## Align to 64 for cache line and SIMD friendliness
    H{.align: 64}: array[HashSize, uint32]
    buf{.align: 64}: array[BlockSize, byte]
    msgLen: uint64
    bufIdx: uint8

  sha256* = Sha256Context

# Internal
# ----------------------------------------------------------------
# TODO: vectorized implementations

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

template rotr(x, n: uint32): uint32 =
  ## Rotate right the bits
  # We always use it with constants in 0 ..< 32
  # so undefined behaviour.
  (x shr n) or (x shl (32 - n))

template ch(x, y, z: uint32): uint32 =
  ## "Choose" function of SHA256
  ## Choose bit i from yi or zi depending on xi
  when false: # Spec FIPS 180-4
    (x and y) xor (not(x) and z)
  else:      # RFC4634
    ((x and (y xor z)) xor z)

template maj(x, y, z: uint32): uint32 =
  ## "Majority" function of SHA256
  when false: # Spec FIPS 180-4
    (x and y) xor (x and z) xor (y and z)
  else:      # RFC4634
    (x and (y or z)) or (y and z)

template S0(x: uint32): uint32 =
  # Σ₀
  rotr(x, 2) xor rotr(x, 13) xor rotr(x, 22)

template S1(x: uint32): uint32 =
  # Σ₁
  rotr(x, 6) xor rotr(x, 11) xor rotr(x, 25)

template s0(x: uint32): uint32 =
  # σ₀
  rotr(x, 7) xor rotr(x, 18) xor (x shr 3)

template s1(x: uint32): uint32 =
  # σ₁
  rotr(x, 17) xor rotr(x, 19) xor (x shr 10)

func setZero[N](a: var array[N, SomeNumber]){.inline.} =
  for i in 0 ..< a.len:
    a[i] = 0

func hashMessageBlocks[T: byte|char](
       H: var array[HashSize, uint32],
       message: openarray[T]): uint =
  ## Hash a message block by block
  ## Sha256 block size is 64 bytes hence
  ## a message will be process 64 by 64 bytes.
  ## FIPS.180-4 6.2.2. SHA-256 Hash Computation

  result = 0
  let numBlocks = message.len.uint div BlockSize
  if numBlocks == 0:
    return 0

  const K256 = [
    0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
    0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32, 0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
    0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
    0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
    0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32, 0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
    0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
    0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
    0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32, 0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32
  ]

  var
    a = H[0]
    b = H[1]
    c = H[2]
    d = H[3]
    e = H[4]
    f = H[5]
    g = H[6]
    h = H[7]

  for _ in 0 ..< numBlocks:
    # The first 16 bytes have different handling
    # from bytes 16..<64.
    # Using an array[64, uint32] will span it
    # across 8 cache lines impacting performance

    # Workspace with message schedule Wₜ
    var W{.noInit.}: array[16, uint32]
    var t = 0'u32
    while t < 16: # Wₜ = Mⁱₜ
      W[t].parseFromBlob(message, result, bigEndian)
      let T1 = h + S1(e) + ch(e, f, g) + K256[t] + W[t]
      let T2 = S0(a) + maj(a, b, c)
      h = g
      g = f
      f = e
      e = d + T1
      d = c
      c = b
      b = a
      a = T1+T2

      t += 1

    while t < 64:
      W[t mod 16] += s1(W[(t-2) mod 16]) +
                     W[(t-7) mod 16] +
                     s0(W[(t-15) mod 16])
      let T1 = h + S1(e) + ch(e, f, g) + K256[t] + W[t mod 16]
      let T2 = S0(a) + maj(a, b, c)
      h = g
      g = f
      f = e
      e = d + T1
      d = c
      c = b
      b = a
      a = T1+T2

      t += 1

    a += H[0]; H[0] = a
    b += H[1]; H[1] = b
    c += H[2]; H[2] = c
    d += H[3]; H[3] = d
    e += H[4]; H[4] = e
    f += H[5]; H[5] = f
    g += H[6]; H[6] = g
    h += H[7]; H[7] = h

func dumpHash(
       digest: var array[DigestSize, byte],
       H: array[HashSize, uint32]) =
  ## Convert the internal hash into a message digest
  var dstIdx = 0'u
  for i in 0 ..< H.len:
    digest.dumpRawInt(H[i], dstIdx, bigEndian)
    dstIdx += uint sizeof(uint32)

func copy[N: static int, T: byte|char](
       dst: var array[N, byte],
       dStart: SomeInteger,
       src: openArray[T],
       sStart: SomeInteger,
       len: SomeInteger
     ) =
  ## Copy dst[dStart ..< dStart+len] = src[sStart ..< sStart+len]
  ## Unlike the standard library, this cannot throw
  ## even a defect.
  ## It also handles copy of char into byte arrays
  debug:
    doAssert 0 <= dStart and dStart+len <= dst.len.uint
    doAssert 0 <= sStart and sStart+len <= src.len.uint

  for i in 0 ..< len:
    dst[dStart + i] = byte src[sStart + i]

func hashBuffer(ctx: var Sha256Context) =
  discard ctx.H.hashMessageBlocks(ctx.buf)
  ctx.buf.setZero()
  ctx.bufIdx = 0

# Public API
# ----------------------------------------------------------------

func init*(ctx: var Sha256Context) =
  ## Initialize or reinitialize a Sha256 context

  ctx.msgLen = 0
  ctx.buf.setZero()
  ctx.bufIdx = 0

  ctx.H[0] = 0x6a09e667'u32;
  ctx.H[1] = 0xbb67ae85'u32;
  ctx.H[2] = 0x3c6ef372'u32;
  ctx.H[3] = 0xa54ff53a'u32;
  ctx.H[4] = 0x510e527f'u32;
  ctx.H[5] = 0x9b05688c'u32;
  ctx.H[6] = 0x1f83d9ab'u32;
  ctx.H[7] = 0x5be0cd19'u32;

func update*[T: char|byte](ctx: var Sha256Context, message: openarray[T]) =
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
  let consumed = ctx.H.hashMessageBlocks(
    message.toOpenArray(int cur, message.len-1))
  cur += consumed
  bytesLeft -= consumed

  if bytesLeft != 0:
    # Store the tail in buffer
    debug: # TODO: state machine formal verification - https://nim-lang.org/docs/drnim.html
      doAssert ctx.bufIdx == 0
      doAssert cur + bytesLeft == message.len.uint

    ctx.buf.copy(dStart = 0'u, message, sStart = cur, len = bytesLeft)
    ctx.bufIdx = uint8 bytesLeft

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
  discard ctx.H.hashMessageBlocks(ctx.buf)
  digest.dumpHash(ctx.H)

func clear*(ctx: var Sha256Context) =
  ## Clear the context internal buffers
  ## Security note:
  ## For passwords and secret keys, you MUST NOT use raw SHA-256
  ## use a Key Derivation Function instead (KDF)
  # TODO: ensure compiler cannot optimize the code away
  ctx.buf.setZero()

func hash*[T: char|byte](
       HashKind: type sha256,
       digest: var array[32, byte],
       message: openarray[T],
       clearMem = false) =
  ## Produce a SHA256 digest from a message
  var ctx {.noInit.}: HashKind
  ctx.init()
  ctx.update(message)
  ctx.finish(digest)

  if clearMem:
    ctx.clear()

func hash*[T: char|byte](
       HashKind: type sha256,
       message: openarray[T],
       clearmem = false): array[32, byte] =
  ## Produce a SHA256 digest from a message
  HashKind.hash(result, message, clearMem)
