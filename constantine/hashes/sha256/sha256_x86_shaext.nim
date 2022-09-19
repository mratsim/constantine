# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/isa/simd_x86,
  ../../platforms/primitives,
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

func hashMessageBlocks_shaext*(
       H: var Sha256_state,
       message: ptr UncheckedArray[byte],
       numBlocks: uint)=
  ## Hash a message block by block
  ## Sha256 block size is 64 bytes hence
  ## a message will be process 64 by 64 bytes.
  
  var
    abef_save {.noInit.}: m128i
    cdgh_save {.noInit.}: m128i
    state0 {.noInit.}: m128i
    state1 {.noInit.}: m128i
    msgtmp {.noInit.}: array[4, m128i]
    msg {.noInit.}: m128i
    tmp {.noInit.}: m128i

    data = message

  let shuf_mask = set_u64x2(0x0c0d0e0f08090a0b, 0x0405060700010203)

  # The SHA state is stored in this order:
  #   D, C, B, A, H, G, F, E
  #
  # state0 contains ABEF, state1 contains CDGH

  tmp    = shuf_u32x4(loada_u128(H.H[0].addr), 0xB1) # CDAB
  state1 = shuf_u32x4(loada_u128(H.H[4].addr), 0x1B) # EFGH
  state0 = alignr_u128(tmp, state1, 8)               # ABEF
  state1 = blend_u16x8(state1, tmp, 0xF0)            # CDGH

  for _ in 0 ..< numBlocks:
    # Save current state
    abef_save = state0
    cdgh_save = state1

    # Rounds 0-3
    msgtmp[0] = shuf_u8x16(loadu_u128(data[0].addr), shuf_mask)
    msg       = add_u32x4(msgtmp[0], setr_K(0))
    state1    = sha256_2rounds(state1, state0, msg)
    msg       = shuf_u32x4(msg, 0x0E)
    state0    = sha256_2rounds(state0, state1, msg)

    # Rounds 4-7 and 8-11
    staticFor i, 1, 3:
      msgtmp[i]   = shuf_u8x16(loadu_u128(data[16*i].addr), shuf_mask)
      msg         = add_u32x4(msgtmp[i], setr_K(i))
      state1      = sha256_2rounds(state1, state0, msg)
      msg         = shuf_u32x4(msg, 0x0E)
      state0      = sha256_2rounds(state0, state1, msg)
      msgtmp[i-1] = sha256_msg1(msgtmp[i-1], msgtmp[i])

    # Rounds 12-59
    msgtmp[3] = shuf_u8x16(loadu_u128(data[16*3].addr), shuf_mask)
    
    staticFor i, 3, 15:
      let prev = (i-1) and 3 # mod 4, we rotate buffers
      let curr =  i    and 3
      let next = (i+1) and 3

      msg          = add_u32x4(msgtmp[curr], setr_K(i))
      state1       = sha256_2rounds(state1, state0, msg)
      tmp          = alignr_u128(msgtmp[curr], msgtmp[prev], 4)
      msgtmp[next] = add_u32x4(msgtmp[next], tmp)
      msgtmp[next] = sha256_msg2(msgtmp[next], msgtmp[curr])
      msg          = shuf_u32x4(msg, 0x0E)
      state0       = sha256_2rounds(state0, state1, msg)
      msgtmp[prev] = sha256_msg1(msgtmp[prev], msgtmp[curr])

    # Rounds 60-63
    msg    = add_u32x4(msgtmp[3], setr_K(15))
    state1 = sha256_2rounds(state1, state0, msg)
    msg    = shuf_u32x4(msg, 0x0E)
    state0 = sha256_2rounds(state0, state1, msg)

    # Accumulate
    state0 = add_u32x4(state0, abef_save)
    state1 = add_u32x4(state1, cdgh_save)

    data +%= BlockSize
  
  # The SHA state is stored in this order:
  #   D, C, B, A, H, G, F, E
  #
  # state0 contains ABEF, state1 contains CDGH

  tmp    = shuf_u32x4(state0, 0x1B)       # FEBA
  state1 = shuf_u32x4(state1, 0xB1)       # DCHG
  state0 = blend_u16x8(tmp, state1, 0xF0) # DCBA
  state1 = alignr_u128(state1, tmp, 8)    # HGFE

  storea_u128(H.H[0].addr, state0)
  storea_u128(H.H[4].addr, state1)