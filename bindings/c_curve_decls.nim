# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../constantine/math/config/curves,
  ../constantine/curves_primitives

export curves, curves_primitives

# Overview
# ------------------------------------------------------------
#
# This files provides template for C bindings generation

template genBindingsField*(Field: untyped) =
  when appType == "lib":
    {.push noconv, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.push noconv, exportc,  raises: [].} # No exceptions allowed

  func `ctt _ Field _ unmarshalBE`(dst: var Field, src: openarray[byte]): bool =
    ## Deserialize
    unmarshalBE(dst, src)

  func `ctt _ Field _ marshalBE`(dst: var openarray[byte], src: Field): bool =
    marshalBE(dst, src)
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ is_eq`(a, b: Field): SecretBool =
    a == b

  func `ctt _ Field _ is_zero`(a: Field): SecretBool =
    a.isZero()

  func `ctt _ Field _ is_one`(a: Field): SecretBool =
    a.isOne()

  func `ctt _ Field _ is_minus_one`(a: Field): SecretBool =
    a.isMinusOne()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ set_zero`(a: var Field) =
    a.setZero()

  func `ctt _ Field _ set_one`(a: var Field) =
    a.setOne()

  func `ctt _ Field _ set_minus_one`(a: var Field) =
    a.setMinusOne()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ neg`(r: var Field, a: Field) =
    r.neg(a)

  func `ctt _ Field _ neg_in_place`(a: var Field) =
    a.neg()

  func `ctt _ Field _ sum`(r: var Field, a, b: Field) =
    r.sum(a,b)

  func `ctt _ Field _ add_in_place`(a: var Field, b: Field) =
    a += b

  func `ctt _ Field _ diff`(r: var Field, a, b: Field) =
    r.diff(a,b)

  func `ctt _ Field _ sub_in_place`(a: var Field, b: Field) =
    a -= b

  func `ctt _ Field _ double`(r: var Field, a: Field) =
    r.double(a)

  func `ctt _ Field _ double_in_place`(a: var Field) =
    a.double()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ prod`(r: var Field, a, b: Field) =
    r.prod(a,b)

  func `ctt _ Field _ mul_in_place`(a: var Field, b: Field) =
    a *= b

  func `ctt _ Field _ square`(r: var Field, a: Field) =
    r.square(a)

  func `ctt _ Field _ square_in_place`(a: var Field) =
    a.square()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ div2`(a: var Field) =
    a.div2()

  func `ctt _ Field _ inv`(r: var Field, a: Field) =
    r.inv(a)

  func `ctt _ Field _ inv_in_place`(a: var Field) =
    a.inv()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ ccopy`(a: var Field, b: Field, ctl: SecretBool) =
    a.ccopy(b, ctl)

  func `ctt _ Field _ cswap`(a, b: var Field, ctl: SecretBool) =
    a.cswap(b, ctl)

  func `ctt _ Field _ cset_zero`(a: var Field, ctl: SecretBool) =
    a.csetZero(ctl)

  func `ctt _ Field _ cset_one`(a: var Field, ctl: SecretBool) =
    a.csetOne(ctl)

  func `ctt _ Field _ cneg_in_place`(a: var Field, ctl: SecretBool) =
    a.cneg(ctl)

  func `ctt _ Field _ cadd_in_place`(a: var Field, b: Field, ctl: SecretBool) =
    a.cadd(b, ctl)

  func `ctt _ Field _ csub_in_place`(a: var Field, b: Field, ctl: SecretBool) =
    a.csub(b, ctl)

  {.pop.}


template genBindingsFieldSqrt*(Field: untyped) =
  when appType == "lib":
    {.push noconv, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.push noconv, exportc,  raises: [].} # No exceptions allowed

  func `ctt _ Field _ is_square`(a: Field): SecretBool =
    a.isSquare()

  func `ctt _ Field _ invsqrt`(r: var Field, a: Field) =
    r.invsqrt(a)

  func `ctt _ Field _ invsqrt_in_place`(r: var Field, a: Field): SecretBool =
    r.invsqrt_if_square(a)

  func `ctt _ Field _ sqrt_in_place`(a: var Field) =
    a.sqrt()

  func `ctt _ Field _ sqrt_if_square_in_place`(a: var Field): SecretBool =
    a.sqrt_if_square()

  func `ctt _ Field _ sqrt_invsqrt`(sqrt, invsqrt: var Field, a: Field) =
    sqrt_invsqrt(sqrt, invsqrt, a)

  func `ctt _ Field _ sqrt_invsqrt_if_square`(sqrt, invsqrt: var Field, a: Field): SecretBool =
    sqrt_invsqrt_if_square(sqrt, invsqrt, a)

  func `ctt _ Field _ sqrt_ratio_if_square`(r: var Field, u, v: Field): SecretBool =
    r.sqrt_ratio_if_square(u, v)

  {.pop.}


template genBindingsExtField*(Field: untyped) =
  when appType == "lib":
    {.push noconv, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.push noconv, exportc,  raises: [].} # No exceptions allowed

  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ is_eq`(a, b: Field): SecretBool =
    a == b

  func `ctt _ Field _ is_zero`(a: Field): SecretBool =
    a.isZero()

  func `ctt _ Field _ is_one`(a: Field): SecretBool =
    a.isOne()

  func `ctt _ Field _ is_minus_one`(a: Field): SecretBool =
    a.isMinusOne()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ set_zero`(a: var Field) =
    a.setZero()

  func `ctt _ Field _ set_one`(a: var Field) =
    a.setOne()

  func `ctt _ Field _ set_minus_one`(a: var Field) =
    a.setMinusOne()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ neg`(a: var Field) =
    a.neg()

  func `ctt _ Field _ sum`(r: var Field, a, b: Field) =
    r.sum(a,b)

  func `ctt _ Field _ add_in_place`(a: var Field, b: Field) =
    a += b

  func `ctt _ Field _ diff`(r: var Field, a, b: Field) =
    r.diff(a,b)

  func `ctt _ Field _ sub_in_place`(a: var Field, b: Field) =
    a -= b

  func `ctt _ Field _ double`(r: var Field, a: Field) =
    r.double(a)

  func `ctt _ Field _ double_in_place`(a: var Field) =
    a.double()

  func `ctt _ Field _ conj`(r: var Field, a: Field) =
    r.conj(a)

  func `ctt _ Field _ conj_in_place`(a: var Field) =
    a.conj()

  func `ctt _ Field _ conjneg`(r: var Field, a: Field) =
    r.conjneg(a)

  func `ctt _ Field _ conjneg_in_place`(a: var Field) =
    a.conjneg()

  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ prod`(r: var Field, a, b: Field) =
    r.prod(a,b)

  func `ctt _ Field _ mul_in_place`(a: var Field, b: Field) =
    a *= b

  func `ctt _ Field _ square`(r: var Field, a: Field) =
    r.square(a)

  func `ctt _ Field _ square_in_place`(a: var Field) =
    a.square()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ div2`(a: var Field) =
    a.div2()

  func `ctt _ Field _ inv`(r: var Field, a: Field) =
    r.inv(a)

  func `ctt _ Field _ inv_in_place`(a: var Field) =
    a.inv()
  # --------------------------------------------------------------------------------------
  func `ctt _ Field _ ccopy`(a: var Field, b: Field, ctl: SecretBool) =
    a.ccopy(b, ctl)

  func `ctt _ Field _ cset_zero`(a: var Field, ctl: SecretBool) =
    a.csetZero(ctl)

  func `ctt _ Field _ cset_one`(a: var Field, ctl: SecretBool) =
    a.csetOne(ctl)

  func `ctt _ Field _ cneg_in_place`(a: var Field, ctl: SecretBool) =
    a.cneg(ctl)

  func `ctt _ Field _ cadd_in_place`(a: var Field, b: Field, ctl: SecretBool) =
    a.cadd(b, ctl)

  func `ctt _ Field _ csub_in_place`(a: var Field, b: Field, ctl: SecretBool) =
    a.csub(b, ctl)

  {.pop.}

template genBindingsExtFieldSqrt*(Field: untyped) =
  when appType == "lib":
    {.push noconv, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.push noconv, exportc,  raises: [].} # No exceptions allowed

  func `ctt _ Field _ is_square`(a: Field): SecretBool =
    a.isSquare()

  func `ctt _ Field _ sqrt_in_place`(a: var Field) =
    a.sqrt()

  func `ctt _ Field _ sqrt_if_square_in_place`(a: var Field): SecretBool =
    a.sqrt_if_square()

  {.pop}

template genBindings_EC_ShortW_Affine*(ECP, Field: untyped) =
  when appType == "lib":
    {.push noconv, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.push noconv, exportc,  raises: [].} # No exceptions allowed

  # --------------------------------------------------------------------------------------
  func `ctt _ ECP _ is_eq`(P, Q: ECP): SecretBool =
    P == Q

  func `ctt _ ECP _ is_inf`(P: ECP): SecretBool =
    P.isInf()

  func `ctt _ ECP _ set_inf`(P: var ECP) =
    P.setInf()

  func `ctt _ ECP _ ccopy`(P: var ECP, Q: ECP, ctl: SecretBool) =
    P.ccopy(Q, ctl)

  func `ctt _ ECP _ is_on_curve`(x, y: Field): SecretBool =
    isOnCurve(x, y, ECP.G)

  func `ctt _ ECP _ neg`(P: var ECP, Q: ECP) =
    P.neg(Q)

  func `ctt _ ECP _ neg_in_place`(P: var ECP) =
    P.neg()

  {.pop.}

template genBindings_EC_ShortW_NonAffine*(ECP, ECP_Aff: untyped) =
  when appType == "lib":
    {.push noconv, dynlib, exportc,  raises: [].} # No exceptions allowed
  else:
    {.push noconv, exportc,  raises: [].} # No exceptions allowed

  # --------------------------------------------------------------------------------------
  func `ctt _ ECP _ is_eq`(P, Q: ECP): SecretBool =
    P == Q

  func `ctt _ ECP _ is_inf`(P: ECP): SecretBool =
    P.isInf()

  func `ctt _ ECP _ set_inf`(P: var ECP) =
    P.setInf()

  func `ctt _ ECP _ ccopy`(P: var ECP, Q: ECP, ctl: SecretBool) =
    P.ccopy(Q, ctl)

  func `ctt _ ECP _ neg`(P: var ECP, Q: ECP) =
    P.neg(Q)

  func `ctt _ ECP _ neg_in_place`(P: var ECP) =
    P.neg()

  func `ctt _ ECP _ cneg_in_place`(P: var ECP, ctl: SecretBool) =
    P.neg()

  func `ctt _ ECP _ sum`(r: var ECP, P, Q: ECP) =
    r.sum(P, Q)

  func `ctt _ ECP _ add_in_place`(P: var ECP, Q: ECP) =
    P += Q

  func `ctt _ ECP _ diff`(r: var ECP, P, Q: ECP) =
    r.diff(P, Q)

  func `ctt _ ECP _ double`(r: var ECP, P: ECP) =
    r.double(P)

  func `ctt _ ECP _ double_in_place`(P: var ECP) =
    P.double()

  func `ctt _ ECP _ affine`(dst: var ECP_Aff, src: ECP) =
    dst.affine(src)

  func `ctt _ ECP _ from_affine`(dst: var ECP, src: ECP_Aff) =
    dst.fromAffine(src)

  {.pop.}