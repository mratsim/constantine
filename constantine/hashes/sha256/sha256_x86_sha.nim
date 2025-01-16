# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/isa_x86/simd_x86,
  constantine/platforms/primitives,
  ./sha256_generic

{.localpassC:"-msse4.1 -msha".}

# SHA256, a hash function from the SHA2 family
# --------------------------------------------------------------------------------
#
# References:
# - Intel SHA extensions whitepaper
#   https://www.intel.com/content/dam/develop/external/us/en/documents/intel-sha-extensions-white-paper-402097.pdf
# - Intel SHA extensions article
#   https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sha-extensions.html

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Primitives
# ------------------------------------------------

template setr_K(i: int): m128i =
  setr_u32x4(K256[4*i], K256[4*i+1], K256[4*i+2], K256[4*i+3])

# Hash Computation
# ------------------------------------------------

func hashMessageBlocks_x86_sha*(
       H: var Sha256_state,
       message: ptr UncheckedArray[byte],
       numBlocks: uint)=
  ## Hash a message block by block
  ## Sha256 block size is 64 bytes hence
  ## a message will be process 64 by 64 bytes.

  var
    state0 {.noInit.}: m128i
    state1 {.noInit.}: m128i
    abef {.noInit.}: m128i
    cdgh {.noInit.}: m128i
    W {.noInit.}: array[4, m128i]
    mix {.noInit.}: m128i
    tmp {.noInit.}: m128i

    data = message

  let shuf_mask = set_u64x2(0x0c0d0e0f08090a0b, 0x0405060700010203)

  # The SHA state is stored in this order:
  #   D, C, B, A, H, G, F, E
  #
  # abef contains ABEF, cdgh contains CDGH

  state0 = shuf_u32x4(loada_u128(H.H[0].addr), 0xB1) # CDAB
  state1 = shuf_u32x4(loada_u128(H.H[4].addr), 0x1B) # EFGH
  abef = alignr_u128(state0, state1, 8)              # ABEF
  cdgh = blend_u16x8(state1, state0, 0xF0)           # CDGH

  for _ in 0 ..< numBlocks:
    # Save current state
    # ---------------------------------------
    state0 = abef
    state1 = cdgh

    # Rounds 0-3
    # ---------------------------------------
    W[0] = shuf_u8x16(loadu_u128(data[0].addr), shuf_mask)
    mix  = add_u32x4(W[0], setr_K(0))
    cdgh = sha256_2rounds(cdgh, abef, mix)
    mix  = shuf_u32x4(mix, 0x0E)
    abef = sha256_2rounds(abef, cdgh, mix)

    # Rounds 4-7 and 8-11
    # ---------------------------------------
    # start interleaving message schedule updates
    # to maximize instruction level parallelism
    staticFor i, 1, 3:
      W[i]   = shuf_u8x16(loadu_u128(data[16*i].addr), shuf_mask)
      mix    = add_u32x4(W[i], setr_K(i))
      cdgh   = sha256_2rounds(cdgh, abef, mix)
      mix    = shuf_u32x4(mix, 0x0E)
      abef   = sha256_2rounds(abef, cdgh, mix)
      W[i-1] = sha256_msg1(W[i-1], W[i])

    W[3] = shuf_u8x16(loadu_u128(data[16*3].addr), shuf_mask)

    # Rounds 12-59
    # ---------------------------------------
    staticFor i, 3, 15:
      const prev = (i-1) and 3 # mod 4, we rotate buffers
      const curr =  i    and 3
      const next = (i+1) and 3

      mix     = add_u32x4(W[curr], setr_K(i))
      cdgh    = sha256_2rounds(cdgh, abef, mix)
      tmp     = alignr_u128(W[curr], W[prev], 4)
      W[next] = add_u32x4(W[next], tmp)
      W[next] = sha256_msg2(W[next], W[curr])
      mix     = shuf_u32x4(mix, 0x0E)
      abef    = sha256_2rounds(abef, cdgh, mix)
      W[prev] = sha256_msg1(W[prev], W[curr])

    # Rounds 60-63
    # ---------------------------------------
    mix  = add_u32x4(W[3], setr_K(15))
    cdgh = sha256_2rounds(cdgh, abef, mix)
    mix  = shuf_u32x4(mix, 0x0E)
    abef = sha256_2rounds(abef, cdgh, mix)

    # Accumulate
    # ---------------------------------------
    abef = add_u32x4(abef, state0)
    cdgh = add_u32x4(cdgh, state1)

    data +%= BlockSize

  # The SHA state is stored in this order:
  #   D, C, B, A, H, G, F, E
  #
  # abef contains ABEF, cdgh contains CDGH

  state0 = shuf_u32x4(abef, 0x1B)          # FEBA
  state1 = shuf_u32x4(cdgh, 0xB1)          # DCHG
  abef = blend_u16x8(state0, state1, 0xF0) # DCBA
  cdgh = alignr_u128(state1, state0, 8)    # HGFE

  storea_u128(H.H[0].addr, abef)
  storea_u128(H.H[4].addr, cdgh)
