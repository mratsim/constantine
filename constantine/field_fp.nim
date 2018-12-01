# Constantine
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                 Field arithmetic over Fp
#
# ############################################################

# We assume that p is prime known at compile-time

import
  ./word_types, ./bigints

type
  Fp[P: static BigInt] = object
    ## P is a prime number
    ## All operations on a field are modulo P
    value: type(P)

# ############################################################
#
#                         Aliases
#
# ############################################################

const
  True = ctrue(Limb)
  False = cfalse(Limb)

template add(a: var Fp, b: Fp, ctl: CTBool[Limb]): CTBool[Limb] =
  add(a.value, b.value, ctl)

template sub(a: var Fp, b: Fp, ctl: CTBool[Limb]): CTBool[Limb] =
  sub(a.value, b.value, ctl)

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################

func `+`*(a, b: Fp): Fp =
  ## Addition over Fp

  # Non-CT implementation from Stint
  #
  # let b_from_p = p - b    # Don't do a + b directly to avoid overflows
  # if a >= b_from_p:
  #   return a - b_from_p
  # return m - b_from_p + a

  result = a
  var ctl = add(result, b, True)
  ctl = ctl or not sub(result, Fp.P, False)
  sub(result, Fp.P, ctl)
