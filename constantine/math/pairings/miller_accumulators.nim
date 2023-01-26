# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../extension_fields,
  ../elliptic/ec_shortweierstrass_affine,
  ../arithmetic,
  ./pairings_generic

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# ############################################################
#
#                  Miller Loop accumulators
#
# ############################################################

# Accumulators stores partial lines or Miller Loops results.
# They allow supporting pairings in a streaming fashion
# or to enable parallelization of multi-pairings.
#
# See ./multi-pairing.md for 2 approaches to a miller loop accumulator:
#
# - Software Implementation, Algorithm 11.2 & 11.3
#   Aranha, Dominguez Perez, A. Mrabet, Schwabe,
#   Guide to Pairing-Based Cryptography, 2015
#
# - Pairing Implementation Revisited
#   Mike Scott, 2019
#   https://eprint.iacr.org/2019/077.pdf
#
#
# Aranha uses:
# - 1 𝔽pᵏ accumulator `f` for Miller loop output
# - N 𝔾2 accumulator `T`, with N our choice.
# The Miller Loop can be batched on up to N pairings with this approach.
#
# Scott uses:
# - M 𝔽pᵏ accumulator `f` for line functions, with M the number of bits in the ate param (68 for BLS12-381).
# - 1 𝔾2 accumulator `T`
#   The Miller Loop can be batched on any amount of pairings
#
# Fp12 points are really large (576 bytes for BLS12-381), a projective G2 point is half that (288 bytes)
# and we can choose N to be way less than 68.
# So for compactness we take Aranha's approach.

const AccumMax = 8
# Max buffer size before triggering a Miller Loop.
# Assuming pairing costs 100, with 50 for Miller Loop and 50 for Final exponentiation.
#
# N unbatched pairings would cost              N*100
# N maximally batched pairings would cost      N*50 + 50
# N AccumMax batched pairings would cost       N*50 + N/AccumMax*(Fpᵏ mul) + 50
#
# Fpᵏ mul costs 0.7% of a Miller Loop and so is negligeable.
# By choosing AccumMax = 8, we amortized the cost to below 0.1% per pairing.

type MillerAccumulator*[FF1, FF2; FpK: ExtensionField] = object
  accum: FpK
  Ps: array[AccumMax, ECP_ShortW_Aff[FF1, G1]]
  Qs: array[AccumMax, ECP_ShortW_Aff[FF2, G2]]
  cur: uint32
  accOnce: bool

func init*(ctx: var MillerAccumulator) =
  ctx.cur = 0
  ctx.accOnce = false

func consumeBuffers[FF1, FF2, FpK](ctx: var MillerAccumulator[FF1, FF2, FpK]) =
  if ctx.cur == 0:
    return

  var t{.noInit.}: FpK
  t.millerLoop(ctx.Qs.asUnchecked(), ctx.Ps.asUnchecked(), ctx.cur.int)
  if ctx.accOnce:
    ctx.accum *= t
  else:
    ctx.accum = t
    ctx.accOnce = true
  ctx.cur = 0

func update*[FF1, FF2, FpK](ctx: var MillerAccumulator[FF1, FF2, FpK], P: ECP_ShortW_Aff[FF1, G1], Q: ECP_ShortW_Aff[FF2, G2]): bool =
  ## Aggregate another set for pairing
  ## This returns `false` if P or Q are the infinity point
  ##
  ## ⚠️: This reveals if a point is infinity through timing side-channels

  if P.isInf().bool or Q.isInf().bool:
    return false

  if ctx.cur == AccumMax:
    ctx.consumeBuffers()

  ctx.Ps[ctx.cur] = P
  ctx.Qs[ctx.cur] = Q
  ctx.cur += 1
  return true

func merge*(ctxDst: var MillerAccumulator, ctxSrc: MillerAccumulator) =
  ## Merge ctxDst <- ctxDst + ctxSrc
  var dCur = ctxDst.cur
  var sCur = 0'u
  var itemsLeft = ctxSrc.cur

  if dCur != 0 and dCur+itemsLeft >= AccumMax:
    # Previous partial update, fill the buffer and do one miller loop
    let free = AccumMax - dCur
    for i in 0 ..< free:
      ctxDst[dCur+i] = ctxSrc[i]
    ctxDst.consumeBuffers()
    dCur = 0
    sCur = free
    itemsLeft -= free

  if itemsLeft != 0:
    # Store the tail
    for i in 0 ..< itemsLeft:
      ctxDst[dCur+i] = ctxSrc[sCur+i]

func finish*[FF1, FF2, FpK](ctx: var MillerAccumulator[FF1, FF2, FpK], multiMillerLoopResult: var Fpk) =
  ## Output the accumulation of multiple Miller Loops
  ctx.consumeBuffers()
  multiMillerLoopResult = ctx.accum