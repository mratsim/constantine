# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, type_bigint],
  ../primitives,
  ../io/io_bigints,
  ./limbs,
  ./limbs_modular,
  ./limbs_montgomery,
  ./bigints

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#                 Montgomery Arithmetic
#
# ############################################################

func montyResidue*(mres: var BigInt, a, N, r2modM: BigInt, m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Convert a BigInt from its natural representation
  ## to the Montgomery n-residue form
  ##
  ## `mres` is overwritten. It's bitlength must be properly set before calling this procedure.
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  ## Nesting Montgomery form is possible by applying this function twice.
  ##
  ## The Montgomery Magic Constants:
  ## - `m0ninv` is µ = -1/N (mod M)
  ## - `r2modM` is R² (mod M)
  ## with W = M.len
  ## and R = (2^WordBitWidth)^W
  montyResidue(mres.limbs, a.limbs, N.limbs, r2modM.limbs, m0ninv, canUseNoCarryMontyMul)

func redc*[mBits](r: var BigInt[mBits], a, M: BigInt[mBits], m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Convert a BigInt from its Montgomery n-residue form
  ## to the natural representation
  ##
  ## `mres` is modified in-place
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  let one = block:
    var one {.noInit.}: BigInt[mBits]
    one.setOne()
    one
  redc(r.limbs, a.limbs, one.limbs, M.limbs, m0ninv, canUseNoCarryMontyMul)

func montyMul*(r: var BigInt, a, b, M: BigInt, negInvModWord: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Compute r <- a*b (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  montyMul(r.limbs, a.limbs, b.limbs, M.limbs, negInvModWord, canUseNoCarryMontyMul)

func montySquare*(r: var BigInt, a, M: BigInt, negInvModWord: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Compute r <- a^2 (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  montySquare(r.limbs, a.limbs, M.limbs, negInvModWord, canUseNoCarryMontyMul)

func montyPow*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is a BigInt in canonical big-endian representation
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[mBits.wordsRequired]]
  montyPow(a.limbs, exponent, M.limbs, one.limbs, negInvModWord, scratchSpace, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

func montyPowUnsafeExponent*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is a BigInt in canonical big-endian representation
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[mBits.wordsRequired]]
  montyPowUnsafeExponent(a.limbs, exponent, M.limbs, one.limbs, negInvModWord, scratchSpace, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

from ../io/io_bigints import exportRawUint
# Workaround recursive dependencies

func montyPow*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is any BigInt, in the canonical domain
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  ##
  ## This is constant-time: the window optimization does
  ## not reveal the exponent bits or hamming weight
  var expBE {.noInit.}: array[(ebits + 7) div 8, byte]
  expBE.exportRawUint(exponent, bigEndian)

  montyPow(a, expBE, M, one, negInvModWord, windowSize, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

func montyPowUnsafeExponent*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is any BigInt, in the canonical domain
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  var expBE {.noInit.}: array[(ebits + 7) div 8, byte]
  expBE.exportRawUint(exponent, bigEndian)

  montyPowUnsafeExponent(a, expBE, M, one, negInvModWord, windowSize, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

{.pop.} # inline
{.pop.} # raises no exceptions
