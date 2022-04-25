# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../platforms/abstractions,
  ../math/[arithmetic, extension_fields]

# https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-14#section-4.1

func sgn0*(x: Fp): SecretBool =
  ## Returns a conventional "sign" for a field element.
  ## Even numbers are considered positive by convention
  ## and odd negative.
  ##
  ## https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-4.1
  #
  # In Montgomery representation
  # each number a is represented as aR (mod M)
  # with R a Montgomery constant
  # hence the LSB of the Montgomery representation
  # cannot be used for this use-case.
  #
  # Another angle is that if M is odd,
  # a+M and a have different parity even though they are
  # the same modulo M.
  let canonical {.noInit.} = x.toBig()
  result = canonical.isOdd()

func sgn0*(x: Fp2): SecretBool =
  # https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-4.1
  # sgn0_m_eq_2(x)
  #
  # Input: x, an element of GF(p^2).
  # Output: 0 or 1.
  #
  # Steps:
  # 1. sign_0 = x_0 mod 2
  # 2. zero_0 = x_0 == 0
  # 3. sign_1 = x_1 mod 2
  # 4. return sign_0 OR (zero_0 AND sign_1)  # Avoid short-circuit logic ops

  result = x.c0.sgn0()
  let z0 = x.c0.isZero()
  let s1 = x.c1.sgn0()
  result = result or (z0 and s1)