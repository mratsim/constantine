# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/isa_arm64/simd_neon,
  constantine/platforms/primitives,
  ./sha256_generic

{.localpassC:"-march=armv8-a+crypto".}

# SHA256, a hash function from the SHA2 family
# --------------------------------------------------------------------------------
#
# ARM doesn't really provide documentation or guidelines.
#
# Instructions specs and pseudocode:
# - https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256su0q_u32
# - https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256su1q_u32
# - https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256hq_u32
# - https://developer.arm.com/architectures/instruction-sets/intrinsics/vsha256h2q_u32
# - https://developer.arm.com/documentation/ddi0596/2021-03/Shared-Pseudocode/Shared-Functions?lang=en#impl-shared.SHA256hash.4
#
# vsha256su0q_u32 does σ₀ and a sum
# vsha256su1q_u32 does σ₁ and 2 sums
# vsha256hq_u32 and vsha256h2q_u32 do
#
#  let T1 = h + S1(e) + ch(e, f, g) + kt + wt
#  let T2 = S0(a) + maj(a, b, c)
#  d += T1
#  h = T1 + T2
#  ROR(h, 32) // Note: ARM spec is big-endian and so rotates left.

# Hash Computation
# ------------------------------------------------
#
# The message schedule and the hash computation
# can be done by alternating 4 hashing rounds
# then 4 scheduling rounds
# It makes for easier code to read but while Apple CPUs can prefetch up to 8 instructions ahead
# it's best to interleave independent instructions to maximize throughput with an out-of-order 9superscalar) processor.

func hashMessageBlocks_arm_sha*(
       H: var Sha256_state,
       message: ptr UncheckedArray[byte],
       numBlocks: uint)=
  ## Hash a message block by block
  ## Sha256 block size is 64 bytes hence
  ## a message will be process 64 by 64 bytes.

  var
    state0 {.noInit.}: uint32x4_t
    state1 {.noInit.}: uint32x4_t
    W {.noInit.}: array[4, uint32x4_t]

    data = message

  var abcd_efgh {.noInit.} = vld1q_u32_x2(H.H[0].addr)
  template abcd: untyped = abcd_efgh.val[0]
  template efgh: untyped = abcd_efgh.val[1]

  var
    # Local variables in loops. Set there so we don't need the no-init all the time
    K {.noInit.}: array[2, uint32x4_t]
    abcd0 {.noInit.}: uint32x4_t

  for _ in 0 ..< numBlocks:
    # Save current state
    # ---------------------------------------
    state0 = abcd
    state1 = efgh

    # Load W[0] to W[15]
    # ---------------------------------------
    let input = vld1q_u8_x4(data)
    W[0] = vreinterpretq_u32_u8(vrev32q_u8(input.val[0]))
    W[1] = vreinterpretq_u32_u8(vrev32q_u8(input.val[1]))
    W[2] = vreinterpretq_u32_u8(vrev32q_u8(input.val[2]))
    W[3] = vreinterpretq_u32_u8(vrev32q_u8(input.val[3]))

    # Round 0-47
    # ---------------------------------------
    # We interleave:
    # - message schedule updates
    # - K constant loads and mixing
    # - hash state updates
    # with next round's
    # to maximize instruction level parallelism
    K[0] = vld1q_u32(K256[0].addr)
    K[0] = vaddq_u32(W[0], K[0])
    staticFor i, 0, 12:
      const i0 =  i    and 3
      const i1 = (i+1) and 3
      const i2 = (i+2) and 3
      const i3 = (i+3) and 3

      const k0 =  i    and 1
      const k1 = (i+1) and 1

      abcd0 = abcd
      W[i0] = vsha256su0q_u32(W[i0], W[i1])
      K[k1] = vld1q_u32(K256[(i+1)*4].addr)
      K[k1] = vaddq_u32(W[i1], K[k1])
      abcd  = vsha256hq_u32(abcd0, efgh, K[k0])
      efgh  = vsha256h2q_u32(efgh, abcd0, K[k0])
      W[i0] = vsha256su1q_u32(W[i0], W[i2], W[i3])

    # Round 48-59
    # ---------------------------------------
    staticFor i, 12, 15:
      const i1 = (i+1) and 3

      const k0 =  i    and 1
      const k1 = (i+1) and 1

      abcd0 = abcd
      K[k1] = vld1q_u32(K256[(i+1)*4].addr)
      K[k1] = vaddq_u32(W[i1], K[k1])
      abcd = vsha256hq_u32(abcd0, efgh, K[k0])
      efgh = vsha256h2q_u32(efgh, abcd0, K[k0])

    # Rounds 60-63
    # ---------------------------------------
    abcd0 = abcd
    abcd = vsha256hq_u32(abcd0, efgh, K[15 and 1])
    efgh = vsha256h2q_u32(efgh, abcd0, K[15 and 1])

    # Accumulate
    # ---------------------------------------
    abcd = vaddq_u32(abcd, state0)
    efgh = vaddq_u32(efgh, state1)

    data +%= BlockSize

  vst1q_u32_x2(H.H[0].addr, abcd_efgh)
