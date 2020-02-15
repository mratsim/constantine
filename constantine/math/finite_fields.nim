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
#     mres*: matchingBigInt(C)
export Fq # defined in ../config/curves to avoid recursive module dependencies

debug:
  func `==`*(a, b: Fq): CTBool[Word] =
    ## Returns true if 2 big ints are equal
    a.mres == b.mres

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#                        Conversion
#
# ############################################################

func fromBig*(T: type Fq, src: BigInt): T =
  ## Convert a BigInt to its Montgomery form
  result.mres.unsafeMontyResidue(src, Fq.C.Mod.mres, Fq.C.getR2modP(), MontyNegInvModWord[Fq.C])

func toBig*(src: Fq): auto =
  ## Convert a finite-field element to a BigInt in natral representation
  result = src.mres
  result.unsafeRedC(Fq.C.Mod.mres, MontyNegInvModWord[Fq.C])

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
  add(a.mres, b.mres, ctl)

template sub(a: var Fq, b: Fq, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  sub(a.mres, b.mres, ctl)

# ############################################################
#
#                Field arithmetic primitives
#
# ############################################################
#
# Note: the library currently implements generic routine for odd field modulus.
#       Routines for special field modulus form:
#       - Mersenne Prime (2^k - 1),
#       - Generalized Mersenne Prime (NIST Prime P256: 2^256 - 2^224 + 2^192 + 2^96 - 1)
#       - Pseudo-Mersenne Prime (2^m - k for example Curve25519: 2^255 - 19)
#       - Golden Primes (φ^2 - φ - 1 with φ = 2^k for example Ed448-Goldilocks: 2^448 - 2^224 - 1)
#       exist and can be implemented with compile-time specialization.

func `+=`*(a: var Fq, b: Fq) =
  ## Addition over Fq
  var ctl = add(a, b, CtTrue)
  ctl = ctl or not sub(a, Fq.C.Mod, CtFalse)
  discard sub(a, Fq.C.Mod, ctl)

func `-=`*(a: var Fq, b: Fq) =
  ## Substraction over Fq
  let ctl = sub(a, b, CtTrue)
  discard add(a, Fq.C.Mod, ctl)

func `*`*(a, b: Fq): Fq {.noInit.} =
  ## Multiplication over Fq
  ##
  ## It is recommended to assign with {.noInit.}
  ## as Fq elements are usually large and this
  ## routine will zero init internally the result.
  result.mres.setInternalBitLength()
  result.mres.montyMul(a.mres, b.mres, Fq.C.Mod.mres, MontyNegInvModWord[Fq.C])
