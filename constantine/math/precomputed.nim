# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./bigints_checked,
  ../primitives/constant_time,
  ../config/common

# Precomputed constants
# ############################################################

# ############################################################
#
#          Montgomery Magic Constants precomputation
#
# ############################################################

func negInvModWord*(M: BigInt): BaseType =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   µ = -1/M[0] mod M
  ##
  ## M[0] is the least significant limb of M
  ## M must be odd and greater than 2.
  # We use BaseType for return value because static distinct type
  # confuses Nim semchecks [UPSTREAM BUG]
  # We don't enforce compile-time evaluation here
  # because static BigInt[bits] also causes semcheck troubles [UPSTREAM BUG]

  # Modular inverse algorithm:
  # Explanation p11 "Dumas iterations" based on Newton-Raphson:
  # - Cetin Kaya Koc (2017), https://eprint.iacr.org/2017/411
  # - Jean-Guillaume Dumas (2012), https://arxiv.org/pdf/1209.6626v2.pdf
  # - Colin Plumb (1994), http://groups.google.com/groups?selm=1994Apr6.093116.27805%40mnemosyne.cs.du.edu
  # Other sources:
  # - https://crypto.stackexchange.com/questions/47493/how-to-determine-the-multiplicative-inverse-modulo-64-or-other-power-of-two
  # - https://mumble.net/~campbell/2015/01/21/inverse-mod-power-of-two
  # - http://marc-b-reynolds.github.io/math/2017/09/18/ModInverse.html

  # For Montgomery magic number, we are in a special case
  # where a = M and m = 2^LimbSize.
  # For a and m to be coprimes, a must be odd.

  # We have the following relation
  # ax ≡ 1 (mod 2^k) <=> ax(2 - ax) ≡ 1 (mod 2^(2k))
  #
  # To get  -1/M0 mod LimbSize
  # we can either negate the resulting x of `ax(2 - ax) ≡ 1 (mod 2^(2k))`
  # or do ax(2 + ax) ≡ 1 (mod 2^(2k))
  #
  # To get the the modular inverse of 2^k' with arbitrary k' (like k=63 in our case)
  # we can do modInv(a, 2^64) mod 2^63 as mentionned in Koc paper.

  let
    M0 = BaseType(M.limbs[0])
    k = log2(WordPhysBitSize)

  result = M0                 # Start from an inverse of M0 modulo 2, M0 is odd and it's own inverse
  for _ in 0 ..< k:           # at each iteration we get the inverse mod(2^2k)
    result *= 2 + M0 * result # x' = x(2 + ax) (`+` to avoid negating at the end)

  # Our actual word size is 2^63 not 2^64
  result = result and BaseType(MaxWord)
