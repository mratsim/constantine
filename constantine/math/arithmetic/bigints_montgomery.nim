# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../io/io_bigints,
  ./limbs,
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

func getMont*(mres: var BigInt, a, N, r2modM: BigInt, m0ninv: BaseType, spareBits: static int) =
  ## Convert a BigInt from its natural representation
  ## to the Montgomery residue form
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
  getMont(mres.limbs, a.limbs, N.limbs, r2modM.limbs, m0ninv, spareBits)

func fromMont*[mBits](r: var BigInt[mBits], a, M: BigInt[mBits], m0ninv: BaseType, spareBits: static int) =
  ## Convert a BigInt from its Montgomery residue form
  ## to the natural representation
  ##
  ## `mres` is modified in-place
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  fromMont(r.limbs, a.limbs, M.limbs, m0ninv, spareBits)

func mulMont*(r: var BigInt, a, b, M: BigInt, negInvModWord: BaseType,
              spareBits: static int, skipFinalSub: static bool = false) =
  ## Compute r <- a*b (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  mulMont(r.limbs, a.limbs, b.limbs, M.limbs, negInvModWord, spareBits, skipFinalSub)

func squareMont*(r: var BigInt, a, M: BigInt, negInvModWord: BaseType,
                 spareBits: static int, skipFinalSub: static bool = false) =
  ## Compute r <- a^2 (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  squareMont(r.limbs, a.limbs, M.limbs, negInvModWord, spareBits, skipFinalSub)

func sumprodMont*[N: static int](
      r: var BigInt,
      a, b: array[N, BigInt],
      M: BigInt, negInvModWord: BaseType,
      spareBits: static int, skipFinalSub: static bool = false) =
  ## Compute r <- ⅀aᵢ.bᵢ (mod M) (sum of products) in the Montgomery domain
  # We rely on BigInt and Limbs having the same repr to avoid array copies
  sumprodMont(
    r.limbs,
    cast[ptr array[N, typeof(a[0].limbs)]](a.unsafeAddr)[],
    cast[ptr array[N, typeof(b[0].limbs)]](b.unsafeAddr)[],
    M.limbs, negInvModWord, spareBits, skipFinalSub
  )

func powMont*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: BaseType, windowSize: static int,
       spareBits: static int
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
  powMont(a.limbs, exponent, M.limbs, one.limbs, negInvModWord, scratchSpace, spareBits)

func powMont_vartime*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: BaseType, windowSize: static int,
       spareBits: static int
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
  powMont_vartime(a.limbs, exponent, M.limbs, one.limbs, negInvModWord, scratchSpace, spareBits)

func powMont*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: BaseType, windowSize: static int,
       spareBits: static int
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
  var expBE {.noInit.}: array[ebits.ceilDiv_vartime(8), byte]
  expBE.marshal(exponent, bigEndian)

  powMont(a, expBE, M, one, negInvModWord, windowSize, spareBits)

func powMont_vartime*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: BaseType, windowSize: static int,
       spareBits: static int
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
  var expBE {.noInit.}: array[ebits.ceilDiv_vartime(8), byte]
  expBE.marshal(exponent, bigEndian)

  powMont_vartime(a, expBE, M, one, negInvModWord, windowSize, spareBits)

{.pop.} # inline
{.pop.} # raises no exceptions
