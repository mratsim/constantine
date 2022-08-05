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
  {.push cdecl, dynlib, exportc,  raises: [].} # No exceptions allowed

  func `ctt _ Field _ unmarshalBE`(dst: var Field, src: openarray[byte]) =
    ## Deserialize
    unmarshalBE(dst, src)

  func `ctt _ Field _ marshalBE`(dst: var openarray[byte], src: Field) =
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

  {.pop.}


template genBindingsExtField*(Field: untyped) =
  {.push cdecl, dynlib, exportc,  raises: [].} # No exceptions allowed

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

  {.pop.}

template genBindings_EC_ShortW_Affine*(ECP, Field: untyped) =
  {.push cdecl, dynlib, exportc,  raises: [].} # No exceptions allowed

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