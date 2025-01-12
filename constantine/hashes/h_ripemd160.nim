# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/zoo_exports

import
  constantine/platforms/[abstractions, views],
  constantine/serialization/endians,
  ./ripemd160/ripemd160_generic


# RIPEMD-160, a hash function from the RIPE family
# --------------------------------------------------------------------------------
#
# References:
# - ISO: ISO/IEC 10118-3:2004, https://www.iso.org/standard/67116.html (latest revision)
# - https://homes.esat.kuleuven.be/~bosselae/ripemd160.html
#   -> Includes a reference implementation in C, however only accessible via the Wayback Machine
#   as of Dec 2024.
# - Bitcoin implementation:
#   https://github.com/bitcoin-core/btcdeb/blob/e2c2e7b9fe2ecc0884129b53813a733f93a6e2c7/crypto/ripemd160.cpp#L242
#
# Vectors:
# - https://homes.esat.kuleuven.be/~bosselae/ripemd160.html
# - [ ] Find Bitcoin vectors

# Types and constants
# ----------------------------------------------------------------

type
  ripemd160* = Ripemd160Context # defined in generic file atm

export Ripemd160Context

# Internals
# ----------------------------------------------------------------
# defined in `ripemd160/ripemd160_generic.nim` at the moment

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Public API
# ----------------------------------------------------------------

template digestSize*(H: type ripemd160): int =
  ## Returns the output size in bytes
  DigestSize

template internalBlockSize*(H: type ripemd160): int =
  ## Returns the byte size of the hash function ingested blocks
  BlockSize

func init*(ctx: var Ripemd160Context) =
  ## Initialize or reinitialize a Ripemd160 context
  ctx.reset()

func update*(ctx: var Ripemd160Context, message: openarray[byte]) =
  ## Append a message to a Ripemd160 context for incremental Ripemd160 computation.
  ##
  ## Security note: the tail of your message might be stored
  ## in an internal buffer.
  ## if sensitive content is used, ensure that
  ## `ctx.finish(...)` and `ctx.clear()` are called as soon as possible.
  ## Additionally ensure that the message(s) passed was(were) stored
  ## in memory considered secure for your threat model.
  ctx.write(message, message.len.uint64)

func finish*(ctx: var Ripemd160Context, digest: var array[DigestSize, byte])  =
  ## Finalize a Ripemd160 computation and output the
  ## message digest to the `digest` buffer.
  ##
  ## Security note: this does not clear the internal buffer.
  ## if sensitive content is used, use "ctx.clear()"
  ## and also make sure that the message(s) passed were stored
  ## in memory considered secure for your threat model.
  ctx.finalize(digest)

func clear*(ctx: var Ripemd160Context) =
  ## Clear the context internal buffers
  # TODO: ensure compiler cannot optimize the code away
  ctx.reset()
