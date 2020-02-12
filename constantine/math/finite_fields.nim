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

import
  ../primitives/constant_time,
  ../config/[common, curves],
  ./bigints_checked

# type
#   Fp*[C: static Curve] = object
#     ## P is the prime modulus of the Curve C
#     ## All operations on a field are modulo P
#     value*: BigInt[CurveBitSize[C]]
export Fp # defined in ../config/curves to avoid recursive module dependencies

debug:
  func `==`*(a, b: Fp): CTBool[Word] =
    ## Returns true if 2 big ints are equal
    a.value == b.value

# ############################################################
#
#                         Aliases
#
# ############################################################

template add(a: var Fp, b: Fp, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  add(a.value, b.value, ctl)

template sub(a: var Fp, b: Fp, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  sub(a.value, b.value, ctl)

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################

# No exceptions allowed
{.push raises: [].}

func `+=`*(a: var Fp, b: Fp) =
  ## Addition over Fp
  var ctl = add(a, b, CtTrue)
  ctl = ctl or not sub(a, Fp.C.Mod, CtFalse)
  discard sub(a, Fp.C.Mod, ctl)

func `-=`*(a: var Fp, b: Fp) =
  ## Substraction over Fp
  let ctl = sub(a, b, CtTrue)
  discard add(a, Fp.C.Mod, ctl)
