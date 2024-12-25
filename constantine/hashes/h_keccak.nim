# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/[abstractions, views],
  ./keccak/keccak_generic

# Keccak, the hash function underlying SHA3
# --------------------------------------------------------------------------------
#
# References:
# - https://keccak.team/keccak_specs_summary.html
# - https://keccak.team/files/Keccak-reference-3.0.pdf
# - https://keccak.team/files/Keccak-implementation-3.2.pdf
# - SHA3 (different padding): https://csrc.nist.gov/publications/detail/fips/202/final
#   - https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.202.pdf

# Sponge API
# --------------------------------------------------------------------------------
#
# References:
# - https://keccak.team/keccak_specs_summary.html
# - https://keccak.team/files/SpongeFunctions.pdf
# - https://keccak.team/files/CSF-0.1.pdf
#
# Keccak[r,c](Mbytes || Mbits) {
#   # Padding
#   d = 2^|Mbits| + sum for i=0..|Mbits|-1 of 2^i*Mbits[i]
#   P = Mbytes || d || 0x00 || … || 0x00
#   P = P xor (0x00 || … || 0x00 || 0x80)
#
#   # Initialization
#   S[x,y] = 0,                               for (x,y) in (0…4,0…4)
#
#   # Absorbing phase
#   for each block Pi in P
#     S[x,y] = S[x,y] xor Pi[x+5*y],          for (x,y) such that x+5*y < r/w
#     S = Keccak-f[r+c](S)
#
#   # Squeezing phase
#   Z = empty string
#   while output is requested
#     Z = Z || S[x,y],                        for (x,y) such that x+5*y < r/w
#     S = Keccak-f[r+c](S)
#
#   return Z
# }

# Duplex construction
# --------------------------------------------------------
# - https://keccak.team/sponge_duplex.html
#   - https://keccak.team/files/SpongeDuplex.pdf
#   - https://eprint.iacr.org/2011/499.pdf: Duplexing the Sponge
# - https://eprint.iacr.org/2023/522.pdf: SAFE - Sponge API for Field Element
#   - https://hackmd.io/@7dpNYqjKQGeYC7wMlPxHtQ/ByIbpfX9c
#
# The original duplex construction described by the Keccak team
# is "absorb-permute-squeeze"
# Paper https://eprint.iacr.org/2022/1340.pdf
# goes over other approaches.
#
# We follow the original intent:
# - permute required when transitioning between absorb->squeeze
# - no permute required when transitioning between squeeze->absorb
# This may change depending on protocol requirement.
# This is in-line with the SAFE (Sponge API for FIeld Element) approach

# Types and constants
# ----------------------------------------------------------------

type
  KeccakContext*[bits: static int, delimiter: static byte] = object

    # Context description
    # - `state` is the permutation state, it is update only
    #   prior to a permutation
    # - `buf` is a message buffer to store partial state updates
    # - `absorb_offset` tracks how filled the message buffer is
    # - `squeeze_offset` tracks the write position in the output buffer
    #
    # Subtilities:
    #   Duplex construction requires a state permutation when
    #   transitioning between absorb and squeezing phase.
    #   After an absorb, squeeze_offset is incremented by the sponge `rate`
    #   This signals the need of a permutation before squeeze.
    #   Similarly after a squeeze, absorb_offset is incremented by the sponge rate.
    #   The real offset can be recovered with a substraction
    #   to properly update the state.
    H {.align: 64.}: KeccakState
    absorb_offset: int32
    squeeze_offset: int32

  keccak256* = KeccakContext[256, 0x01]
  sha3_256* = KeccakContext[256, 0x06]

template rate(ctx: KeccakContext): int =
  200 - 2*(ctx.bits div 8)

# Internals
# ----------------------------------------------------------------

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Public API
# ----------------------------------------------------------------

template digestSize*(H: type KeccakContext): int =
  ## Returns the output size in bytes
  # hardcoded for now or concept match issue with CryptoHash
  32

template internalBlockSize*(H: type KeccakContext): int =
  ## Returns the byte size of the hash function ingested blocks
  # hardcoded for now or concept match issue with CryptoHash
  200

func init*(ctx: var KeccakContext) {.inline.} =
  ## Initialize or reinitialize a Keccak context
  ctx.reset()

# debug
import constantine/serialization/codecs

func absorb*(ctx: var KeccakContext, message: openArray[byte]) =
  ## Absorb a message in the Keccak sponge state
  ##
  ## Security note: the tail of your message might be stored
  ## in an internal buffer.
  ## if sensitive content is used, ensure that
  ## `ctx.finish(...)` and `ctx.clear()` are called as soon as possible.
  ## Additionally ensure that the message(s) passed were stored
  ## in memory considered secure for your threat model.

  var pos = int ctx.absorb_offset # offset in Keccak state
  var cur = 0                     # offset in message
  var bytesLeft = message.len

  # We follow the "absorb-permute-squeeze" approach
  # originally defined by the Keccak team.
  # It is compatible with SHA-3 hash spec.
  # See https://eprint.iacr.org/2022/1340.pdf
  #
  # There are no transition/permutation between squeezing -> absorbing
  # And within this `absorb` function
  #    the state pos == ctx.rate()
  # is always followed by a permute and setting `pos = 0`

  if (pos mod ctx.rate()) != 0 and pos+bytesLeft >= ctx.rate():
    # Previous partial update, fill the state and do one permutation
    let free = ctx.rate() - pos
    ctx.H.xorInPartial(pos, message.toOpenArray(0, free-1))
    ctx.H.permute_generic(NumRounds = 24)
    pos = 0
    cur = free
    bytesLeft -= free

  if bytesLeft >= ctx.rate():
    # Process multiple blocks
    let numBlocks = bytesLeft div ctx.rate()
    ctx.H.hashMessageBlocks_generic(message.asUnchecked() +% cur, numBlocks)
    cur += numBlocks * ctx.rate()
    bytesLeft -= numBlocks * ctx.rate()

  if bytesLeft != 0:
    # Store the tail in buffer
    ctx.H.xorInPartial(pos, message.toOpenArray(cur, cur+bytesLeft-1))

  # Epilogue
  ctx.absorb_offset = int32(pos+bytesLeft)
  # Signal that the next squeeze transition needs a permute
  ctx.squeeze_offset = int32 ctx.rate()

func squeeze*(ctx: var KeccakContext, digest: var openArray[byte]) =
  var pos = ctx.squeeze_offset # offset in Keccak state
  var cur = 0                  # offset in message
  var bytesLeft = digest.len

  if pos == ctx.rate():
    # Transition from absorbing to squeezing
    #   This state can only come from `absorb` function
    #   as within `squeeze`, pos == ctx.rate() is always followed
    #   by a permute and pos = 0
    ctx.H.pad(ctx.absorb_offset, ctx.delimiter, ctx.rate())
    ctx.H.permute_generic(NumRounds = 24)
    pos = 0
    ctx.absorb_offset = 0

  if (pos mod ctx.rate()) != 0 and pos+bytesLeft >= ctx.rate():
    # Previous partial squeeze, fill up to rate and do one permutation
    let free = ctx.rate() - pos
    ctx.H.copyOutPartial(hByteOffset = pos, digest.toOpenArray(0, free-1))
    ctx.H.permute_generic(NumRounds = 24)
    pos = 0
    ctx.absorb_offset = 0
    cur = free
    bytesLeft -= free

  if bytesLeft >= ctx.rate():
    # Process multiple blocks
    let numBlocks = bytesLeft div ctx.rate()
    ctx.H.squeezeDigestBlocks_generic(digest.asUnchecked() +% cur, numBlocks)
    ctx.absorb_offset = 0
    cur += numBlocks * ctx.rate()
    bytesLeft -= numBlocks * ctx.rate()

  if bytesLeft != 0:
    # Output the tail
    ctx.H.copyOutPartial(hByteOffset = pos, digest.toOpenArray(cur, bytesLeft-1))

  # Epilogue
  ctx.squeeze_offset = int32 bytesLeft
  # We don't signal absorb_offset to permute the state if called next
  # as per
  #   - original keccak spec that uses "absorb-permute-squeeze" protocol
  #   - https://eprint.iacr.org/2022/1340.pdf
  #   - https://eprint.iacr.org/2023/522.pdf
  #     https://hackmd.io/@7dpNYqjKQGeYC7wMlPxHtQ/ByIbpfX9c#2-SAFE-definition

func update*(ctx: var KeccakContext, message: openArray[byte]) =
  ## Append a message to a Keccak context
  ## for incremental Keccak computation
  ##
  ## Security note: the tail of your message might be stored
  ## in an internal buffer.
  ## if sensitive content is used, ensure that
  ## `ctx.finish(...)` and `ctx.clear()` are called as soon as possible.
  ## Additionally ensure that the message(s) passed was(were) stored
  ## in memory considered secure for your threat model.
  ctx.absorb(message)

func finish*(ctx: var KeccakContext, digest: var array[32, byte]) =
  ## Finalize a Keccak computation and output the
  ## message digest to the `digest` buffer.
  ##
  ## An `update` MUST be called before finish even with empty message.
  ##
  ## Security note: this does not clear the internal buffer.
  ## if sensitive content is used, use "ctx.clear()"
  ## and also make sure that the message(s) passed were stored
  ## in memory considered secure for your threat model.
  ctx.squeeze(digest)

func clear*(ctx: var KeccakContext) =
  ## Clear the context internal buffers
  # TODO: ensure compiler cannot optimize the code away
  ctx.reset()
