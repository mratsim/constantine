# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#          Fq: Finite Field arithmetic over Q
#
# ############################################################

# We assume that q is known at compile-time
# We assume that q is not even:
# - Operations are done in the Montgomery domain
# - The Montgomery domain introduce a Montgomery constant that must be coprime
#   with the field modulus.
# - The constant is chosen a power of 2
# => to be coprime with a power of 2, q must be odd

import
  ../primitives/constant_time,
  ../config/[common, curves],
  ./bigints_checked

# type
#   `Fq`*[C: static Curve] = object
#     ## All operations on a field are modulo P
#     ## P being the prime modulus of the Curve C
#     ## Internally, data is stored in Montgomery n-residue form
#     ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
#     nres*: matchingBigInt(C)
export Fq # defined in ../config/curves to avoid recursive module dependencies

debug:
  func `==`*(a, b: Fq): CTBool[Word] =
    ## Returns true if 2 big ints are equal
    a.nres == b.nres

# No exceptions allowed
{.push raises: [].}

func toMonty*[C: static Curve](a: Fq[C]): Montgomery[C] =
  ## Convert a big integer over Fq to its montgomery representation
  ## over Fq.
  ## i.e. Does "a * (2^LimbSize)^W (mod p), where W is the number
  ## of words needed to represent p in base 2^LimbSize

  result = a
  for i in static(countdown(C.Mod.limbs.high, 1)):
    shiftAdd(result, 0)


# ############################################################
#
#                         Aliases
#
# ############################################################

template add(a: var Fq, b: Fq, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  add(a.value, b.value, ctl)

template sub(a: var Fq, b: Fq, ctl: CTBool[Word]): CTBool[Word] =
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

func `+=`*(a: var Fq, b: Fq) =
  ## Addition over Fq
  var ctl = add(a, b, CtTrue)
  ctl = ctl or not sub(a, Fq.C.Mod, CtFalse)
  discard sub(a, Fq.C.Mod, ctl)

func `-=`*(a: var Fq, b: Fq) =
  ## Substraction over Fq
  let ctl = sub(a, b, CtTrue)
  discard add(a, Fq.C.Mod, ctl)
