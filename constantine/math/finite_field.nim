# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
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
# We assume that p is not even (requirement for Montgomery form)

import ./primitives, ./bigints, ./curves_config

type
  Fp*[C: static Curve] = object
    ## P is the prime modulus of the Curve C
    ## All operations on a field are modulo P
    value: BigInt[CurveBitSize[C]]

# ############################################################
#
#                         Aliases
#
# ############################################################

template add(a: var Fp, b: Fp, ctl: CTBool[Word]): CTBool[Word] =
  add(a.value, b.value, ctl)

template sub(a: var Fp, b: Fp, ctl: CTBool[Word]): CTBool[Word] =
  sub(a.value, b.value, ctl)

template `[]`(a: Fp, idx: int): Word =
  a.value.limbs[idx]

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################

# No exceptions allowed
{.push raises: [].}

func `+`*(a, b: Fp): Fp {.noInit.}=
  ## Addition over Fp

  # Non-CT implementation from Stint
  #
  # let b_from_p = p - b    # Don't do a + b directly to avoid overflows
  # if a >= b_from_p:
  #   return a - b_from_p
  # return m - b_from_p + a

  result = a
  var ctl = add(result, b, CtTrue)
  ctl = ctl or not sub(result, Fp.C.Mod, CtFalse)
  sub(result, Fp.C.Mod, ctl)
