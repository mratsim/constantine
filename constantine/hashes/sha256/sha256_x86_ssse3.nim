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

{.localpassC:"-mssse3".}

# SHA256, SSSE3 optimizations
# --------------------------------------------------------------------------------
#
# References:
# - NIST: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
# - IETF: US Secure Hash Algorithms (SHA and HMAC-SHA) https://tools.ietf.org/html/rfc4634
# - Fast SHA-256 Implementations on Intel® Architecture Processors
#   https://www.intel.com/content/dam/www/public/us/en/documents/white-papers/sha-256-implementations-paper.pdf
# - Parallelizing message schedules
#   to accelerate the computations of hash functions
#   Shay Gueron, Vlad Krasnov, 2012
#   https://eprint.iacr.org/2012/067.pdf

# Following the intel whitepaper we split our code into:
# We keep track of a 256-bit state vector corresponding
# to {a, b, c, d, e, f, g, h} in specification
#
# Processing is done in 2 steps
# - Message scheduler:
#   Takes the input 16 DWORDs and
#   computes 48 new DWORDs. Together with the original 16 DWORDs, these
#   form a vector of 64 DWORDs that is the input to the second step.
#   This can be vectorized.
# - 64 SHA rounds:
#   This code is scalar.

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Vectorized message scheduler
# ------------------------------------------------

const VecNum = BlockSize div 16      # BlockSize / sizeof(m128i)
const VecWords = 16 div sizeof(Word) # sizeof(m128i) / sizeof(Word) 

func initMessageSchedule(
       msnext: var array[VecNum, m128i],
       ms: var Sha256_MessageSchedule,
       message: ptr UncheckedArray[byte]) {.inline.} =
  ## Initial state, from data
  ## - Precompute steps for the future message schedule `msnext`
  ## - compute the current message schedule `ms`
  
  let mask = setr_u32x4(0x00010203, 0x04050607, 0x08090a0b, 0x0c0d0e0f)
  let pK256 = K256.unsafeAddr()

  staticFor i, 0, VecNum:
    msnext[i] = loadu_u128(message[i * sizeof(m128i)].addr)
    msnext[i] = shuf_u8x16(msnext[i], mask)
    storea_u128(ms.w[VecWords*i].addr, add_u32x4(msnext[i], loadu_u128(pK256[VecWords*i].addr)))

func updateMessageSchedule(
       W: var array[4, m128i],
       loMask, hiMask: m128i) {.inline.} =
  # Steady state
  # ------------
  # The message schedule workspace W[16:0]
  # is updated with
  #   W[t mod 16] += s0 + s1 + W[(t-7) mod 16]
  # with
  #   s0 = σ₀(W[(t-15) mod 16])
  #   s1 = σ₁(W[(t-2)  mod 16])
  # by denoting the right rotation >>>, and xor ⊕
  #   σ₀(x) = (x >>>  7) ⊕ (x >>> 18) ⊕ (x >>>  3)
  #   σ₁(x) = (x >>> 17) ⊕ (x >>> 19) ⊕ (x >>> 10)

  const rot0 = [int32  7, 18,  3]
  const rot1 = [int32 17, 19, 10]

  var v{.noInit.}: array[4, m128i]

  v[0] = alignr_u128(W[1], W[0], 4)
  v[3] = alignr_u128(W[3], W[2], 4)
  v[2] = shr_u32x4(v[0], rot0[0])
  W[0] = add_u32x4(W[0], v[3])

  v[3] = shr_u32x4(v[0], rot0[2])
  v[1] = shl_u32x4(v[0], 32-rot0[1])
  v[0] = xor_u128(v[3], v[2])

  v[3] = shuf_u32x4(W[3], 0xfa)
  v[2] = shr_u32x4(v[2], rot0[1] - rot0[0])
  v[0] = xor_u128(v[0], v[1])
  v[0] = xor_u128(v[0], v[2])

  v[1] = shl_u32x4(v[1], rot0[1] - rot0[0])
  v[2] = shr_u32x4(v[3], rot1[2])
  v[3] = shr_u64x2(v[3], rot1[0])
  W[0] = add_u32x4(W[0], xor_u128(v[0], v[1]))

  v[2] = xor_u128(v[2], v[3])
  v[3] = shr_u64x2(v[3], rot1[1] - rot1[0])
  v[2] = shuf_u8x16(xor_u128(v[2], v[3]), lo_mask)
  W[0] = add_u32x4(W[0], v[2])

  v[3] = shuf_u32x4(W[0], 0x50)
  v[2] = shr_u32x4(v[3], rot1[2])
  v[3] = shr_u64x2(v[3], rot1[0])
  v[2] = xor_u128(v[2], v[3])
  v[3] = shr_u64x2(v[3], rot1[1] - rot1[0])

  W[0] = add_u32x4(W[0], shuf_u8x16(xor_u128(v[2], v[3]), hi_mask)) 

  W.rotateLeft()

# Hash Computation
# ------------------------------------------------

func sha256_rounds_0_47(
       s: var Sha256_state,
       ms: var Sha256_MessageSchedule,
       msnext: var array[VecNum, m128i]) {.inline.} =
  ## Process Sha256 rounds 0 to 47
  
  let loMask = setr_u32x4(0x03020100, 0x0b0a0908, -1, -1)
  let hiMask = setr_u32x4(-1, -1, 0x03020100, 0x0b0a0908)

  # The first items of K256 were processed in initMessageSchedule
  var k256_idx = 16

  # Rounds 0-15, 16-31, 32-47
  for r in 0 ..< 3:

    # Important unrolling for 2 reasons, see Intel paper
    # - State updates:
    #   In each round calculation six out of the eight state variables are shifted to the
    #   next state variable. Rather than do these using mov instructions, we rename
    #   the virtual registers (symbols) to effect this “shift”. Thus each round
    #   effectively rotates the set of state register names by one place. By doing 8 or
    #   16 rounds in the body of the loop, the names have rotated back to their
    #   starting values, so no register moves are needed before looping.
    #
    # - Message schedule:
    #   Similarly on the vector unit for the message scheduling, the 16 necessary
    #   scheduled DWORDs are stored in four XMM registers, as described earlier. For
    #   example, the initial data DWORDs are stored in order as {X0, X1, X2, X3}.
    #   When we compute four new scheduled DWORDs, we store them in X0
    #   (overwriting the “oldest” data DWORDs), so now the scheduled DWORDs are
    #   stored in order in {X1, X2, X3, X0}. Once again, we handle this by “rotating”
    #   the four names, where in this case the names rotate one place every four
    #   rounds (because we compute four scheduled DWORDs in each calculation).
    #   By having 16 rounds (four scheduling operations) in the body of the loop,
    #   these XMM register names rotate back to their initial value, and again no
    #   register moves are needed before looping.

    staticFor i, 0, VecNum:
      # We interleave computing the message scheduled at {t+4, t+5, t+6, t+7}
      # with SHA256 state update for {t, t+1, t+2, t+3}

      # As they are independent, hopefully the compiler reorders instructions
      # for maximum throughput.
      # Also it optimize away the moves and use register renaming to avoid rotations
      const pos = VecWords * i

      msnext.updateMessageSchedule(loMask, hiMask)
      let wnext = add_u32x4(msnext[3], loadu_u128(K256[k256_idx].unsafeAddr))

      # K256 was already included in the computation of wnext, hence kt = 0
      s.sha256_round(wt = ms.w[pos + 0], kt = 0)
      s.sha256_round(wt = ms.w[pos + 1], kt = 0)
      s.sha256_round(wt = ms.w[pos + 2], kt = 0)
      s.sha256_round(wt = ms.w[pos + 3], kt = 0)

      storea_u128(ms.w[pos].addr, wnext)
      k256_idx += VecWords


func sha256_rounds_48_63(
       s: var Sha256_state,
       ms: var Sha256_MessageSchedule) {.inline.} =
  ## Process Sha256 rounds 48 to 63
  staticFor t, 48, 64:
    # Wt[i mod 16] and K256 was already integrated in the computation of wnext
    s.sha256_round(wt = ms.w[t and 15], kt = 0)

func hashMessageBlocks_ssse3*(
       H: var Sha256_state,
       message: ptr UncheckedArray[byte],
       numBlocks: uint)=
  ## Hash a message block by block
  ## Sha256 block size is 64 bytes hence
  ## a message will be process 64 by 64 bytes.

  var msg = message
  var ms{.noInit.}: Sha256_MessageSchedule
  var msnext{.noInit.}: array[VecNum, m128i]
  var s{.noInit.}: Sha256_state

  s.copy(H)

  for _ in 0 ..< numBlocks:
    initMessageSchedule(msnext, ms, msg)
    msg +%= BlockSize

    sha256_rounds_0_47(s, ms, msnext)
    sha256_rounds_48_63(s, ms)

    s.accumulate(H) # accumulate on register variables
    H.copy(s)
