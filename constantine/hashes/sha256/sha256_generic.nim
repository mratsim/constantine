# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/primitives

# SHA256, a hash function from the SHA2 family
# --------------------------------------------------------------------------------
#
# References:
# - NIST: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
# - IETF: US Secure Hash Algorithms (SHA and HMAC-SHA) https://tools.ietf.org/html/rfc4634
# Vectors:
# - https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Types & Constants
# ------------------------------------------------
# The enforced alignment should help the compiler produce optimized code

type Word* = uint32

const
  DigestSize* = 32
  BlockSize* = 64
  HashSize* = DigestSize div sizeof(Word) # 8

type Sha256_MessageSchedule* = object
  w*{.align: 64.}: array[BlockSize div sizeof(Word), Word]

type Sha256_state* = object
  H*{.align: 64.}: array[HashSize, Word]

const K256* = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32, 0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
  0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32, 0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
  0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32, 0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32, 0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
  0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32, 0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
  0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32, 0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32, 0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
  0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32, 0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32
]

# Primitives
# ------------------------------------------------

template rotr(x, n: uint32): uint32 =
  ## Rotate right the bits
  # We always use it with constants in 0 ..< 32
  # so no undefined behaviour.
  (x shr n) or (x shl (32 - n))

template ch(x, y, z: uint32): uint32 =
  ## "Choose" function of SHA256
  ## Choose bit i from yi or zi depending on xi
  when false: # Spec FIPS 180-4
    (x and y) xor (not(x) and z)
  else:       # RFC4634
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

# Message schedule
# ------------------------------------------------

template u32BE(blob: array[4, byte]): uint32 =
  ## Interpret a data blob as a big-endian uint32
  when nimvm:
    (blob[0].uint32 shl 24) or (blob[1].uint32 shl 16) or (blob[2].uint32 shl 8) or blob[3].uint32
  else:
    when cpuEndian == littleEndian:
      (blob[0].uint32 shl 24) or (blob[1].uint32 shl 16) or (blob[2].uint32 shl 8) or blob[3].uint32
    else:
      cast[uint32](blob)

template getU32at(msg: ptr UncheckedArray[byte], pos: SomeInteger): uint32 =
  u32BE(cast[ptr array[4, byte]](msg[pos].addr)[])

# State updates
# ------------------------------------------------

template copy*(dst: var Sha256_state, src: Sha256_state) =
  ## State copy
  # Should compile with a specialized aligned copy.
  # No bounds check
  for i in 0 ..< HashSize:
    dst.H[i] = src.H[i]

template accumulate*(dst: var Sha256_state, src: Sha256_state) =
  ## State accumulation
  # No bounds check
  for i in 0 ..< HashSize:
    dst.H[i] += src.H[i]

template sha256_round*(s: var Sha256_state, wt, kt: Word) =
  template a: Word = s.H[0]
  template b: Word = s.H[1]
  template c: Word = s.H[2]
  template d: Word = s.H[3]
  template e: Word = s.H[4]
  template f: Word = s.H[5]
  template g: Word = s.H[6]
  template h: Word = s.H[7]

  let T1 = h + S1(e) + ch(e, f, g) + kt + wt
  let T2 = S0(a) + maj(a, b, c)
  d += T1
  h = T1 + T2

  s.H.rotateRight()

# Hash Computation
# ------------------------------------------------

func sha256_rounds_0_15(
       s: var Sha256_state,
       ms: var Sha256_MessageSchedule,
       message: ptr UncheckedArray[byte]) {.inline.} =
  staticFor t, 0, 16:
    ms.w[t] = message.getU32at(t * sizeof(Word))
    sha256_round(s, ms.w[t], K256[t])

func sha256_rounds_16_63(
       s: var Sha256_state,
       ms: var Sha256_MessageSchedule) {.inline.}  =
  staticFor t, 16, 64:
    ms.w[t and 15] += s1(ms.w[(t -  2) and 15])+
                         ms.w[(t -  7) and 15] +
                      s0(ms.w[(t - 15) and 15])

    sha256_round(s, ms.w[t and 15], K256[t])

func hashMessageBlocks_generic*(
       H: var Sha256_state,
       message: ptr UncheckedArray[byte],
       numBlocks: uint) =
  ## Hash a message block by block
  ## Sha256 block size is 64 bytes hence
  ## a message will be process 64 by 64 bytes.
  ## FIPS.180-4 6.2.2. SHA-256 Hash Computation

  var msg = message
  var ms{.noInit.}: Sha256_MessageSchedule
  var s{.noInit.}: Sha256_state

  s.copy(H)

  for _ in 0 ..< numBlocks:
    sha256_rounds_0_15(s, ms, msg)
    msg +%= BlockSize

    sha256_rounds_16_63(s, ms)

    s.accumulate(H) # accumulate on register variables
    H.copy(s)
