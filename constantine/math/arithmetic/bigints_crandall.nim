# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  ./limbs,
  ./limbs_crandall,
  ./bigints

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#                 Crandall Arithmetic
#
# ############################################################

func mulCran*[m: static int](
      r: var BigInt[m], a, b: BigInt[m],
      c: static SecretWord,
      lazyReduce: static bool = false) =
  ## Compute r <- a*b (2ᵐ-c)
  mulCran(r.limbs, a.limbs, b.limbs, m, c, lazyReduce)

func squareCran*[m: static int](
      r: var BigInt[m], a: BigInt[m],
      c: static SecretWord,
      lazyReduce: static bool = false) =
  ## Compute r <- a² (2ᵐ-c), m = bits
  squareCran(r.limbs, a.limbs, m, c, lazyReduce)

func powCran*[m: static int](
       a: var BigInt[m], exponent: openarray[byte],
       windowSize: static int,
       c: static SecretWord,
       lazyReduce: static bool = false) =
  ## Compute a <- a^exponent (mod M)
  ## ``exponent`` is a BigInt in canonical big-endian representation
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  ##
  ## This is constant-time: the window optimization does
  ## not reveal the exponent bits or hamming weight
  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[m.wordsRequired()]]
  powCran(a.limbs, exponent, scratchSpace, m, c, lazyReduce)

func powCran_vartime*[m: static int](
       a: var BigInt[m], exponent: openarray[byte],
       windowSize: static int,
       c: static SecretWord,
       lazyReduce: static bool = false) =
  ## Compute a <- a^exponent (mod M)
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
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[m.wordsRequired()]]
  powCran_vartime(a.limbs, exponent, scratchSpace, m, c, lazyReduce)

func powCran*[m, eBits: static int](
       a: var BigInt[m], exponent: BigInt[eBits],
       windowSize: static int,
       c: static SecretWord,
       lazyReduce: static bool = false) =
  ## Compute a <- a^exponent (mod M)
  ## ``exponent`` is any BigInt, in the canonical domain
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  ##
  ## This is constant-time: the window optimization does
  ## not reveal the exponent bits or hamming weight
  var expBE {.noInit.}: array[ebits.ceilDiv_vartime(8), byte]
  expBE.marshal(exponent, bigEndian)

  powCran(a, expBE, windowSize, c, lazyReduce)

func powCran_vartime*[m, eBits: static int](
       a: var BigInt[m], exponent: BigInt[eBits],
       windowSize: static int,
       c: static SecretWord,
       lazyReduce: static bool = false) =
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

  powCran_vartime(a, expBE, windowSize, c, lazyReduce)

{.pop.} # inline
{.pop.} # raises no exceptions
