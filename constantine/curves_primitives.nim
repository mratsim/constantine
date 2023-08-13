# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ./platforms/abstractions,
    ./math/config/[curves, type_ff],
    ./math/[
      ec_shortweierstrass,
      extension_fields,
      arithmetic,
      constants/zoo_subgroups,
      constants/zoo_generators
    ],
    ./math/io/[io_bigints, io_fields],
    ./math/isogenies/frobenius,
    ./math/pairings/[
      cyclotomic_subgroups,
      lines_eval,
      pairings_generic
    ],
    ./math/constants/zoo_pairings,
    ./hash_to_curve/hash_to_curve

# ############################################################
#
#            Generator for low-level primitives API
#
# ############################################################

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push inline.}

# Base types
# ------------------------------------------------------------

export
  abstractions,
  curves.Curve

# Scalar field Fr and Prime Field Fp
# ------------------------------------------------------------

export
  type_ff.Fp,
  type_ff.Fr,
  type_ff.FF

func unmarshalBE*(dst: var FF, src: openarray[byte]): bool =
  ## Return true on success
  ## Return false if destination is too small compared to source
  var raw {.noInit.}: typeof dst.mres
  let ok = raw.unmarshal(src, bigEndian)
  if not ok:
    return false
  dst.fromBig(raw)
  return true

func marshalBE*(dst: var openarray[byte], src: FF): bool =
  ## Return true on success
  ## Return false if destination is too small compared to source
  var raw {.noInit.}: typeof src.mres
  raw.fromField(src)
  return dst.marshal(src, bigEndian)

export arithmetic.ccopy
export arithmetic.cswap

export arithmetic.`==`
export arithmetic.isZero
export arithmetic.isOne
export arithmetic.isMinusOne

export arithmetic.setZero
export arithmetic.setOne
export arithmetic.setMinusOne

export arithmetic.neg
export arithmetic.sum
export arithmetic.`+=`
export arithmetic.diff
export arithmetic.`-=`
export arithmetic.double

export arithmetic.prod
export arithmetic.`*=`
export arithmetic.square
export arithmetic.square_repeated

export arithmetic.csetZero
export arithmetic.csetOne
export arithmetic.cneg
export arithmetic.cadd
export arithmetic.csub

export arithmetic.div2
export arithmetic.inv

export arithmetic.isSquare
export arithmetic.invsqrt
export arithmetic.sqrt
export arithmetic.sqrt_invsqrt
export arithmetic.sqrt_invsqrt_if_square
export arithmetic.sqrt_if_square
export arithmetic.invsqrt_if_square
export arithmetic.sqrt_ratio_if_square

# Elliptic curve
# ------------------------------------------------------------

export
  ec_shortweierstrass.Subgroup,
  ec_shortweierstrass.ECP_ShortW_Aff,
  ec_shortweierstrass.ECP_ShortW_Jac,
  ec_shortweierstrass.ECP_ShortW_Prj,
  ec_shortweierstrass.ECP_ShortW

export ec_shortweierstrass.`==`
export ec_shortweierstrass.isInf
export ec_shortweierstrass.setInf
export ec_shortweierstrass.ccopy
export ec_shortweierstrass.isOnCurve
export ec_shortweierstrass.neg
export ec_shortweierstrass.cneg

export ec_shortweierstrass.affine
export ec_shortweierstrass.fromAffine
export ec_shortweierstrass.batchAffine

export ec_shortweierstrass.sum
export ec_shortweierstrass.`+=`
export ec_shortweierstrass.double
export ec_shortweierstrass.diff
# export ec_shortweierstrass.madd

export ec_shortweierstrass.scalarMul

export zoo_generators.getGenerator
export zoo_subgroups.clearCofactor
export zoo_subgroups.isInSubgroup

export frobenius.frobenius_psi

# Extension fields
# ------------------------------------------------------------

export
  extension_fields.Fp2
  # TODO: deal with Fp2->Fp6 vs Fp3->Fp6 and Fp2->Fp6->Fp12 vs Fp2->Fp4->Fp12
  # extension_fields.Fp4,
  # extension_fields.Fp6,
  # extension_fields.Fp12

# Generic sandwich - https://github.com/nim-lang/Nim/issues/11225
export extension_fields.c0, extension_fields.`c0=`
export extension_fields.c1, extension_fields.`c1=`
export extension_fields.c2, extension_fields.`c2=`

export extension_fields.setZero
export extension_fields.setOne
export extension_fields.setMinusOne

export extension_fields.`==`
export extension_fields.isZero
export extension_fields.isOne
export extension_fields.isMinusOne

export extension_fields.ccopy

export extension_fields.neg
export extension_fields.`+=`
export extension_fields.`-=`
export extension_fields.double
export extension_fields.div2
export extension_fields.sum
export extension_fields.diff
export extension_fields.conj
export extension_fields.conjneg

export extension_fields.csetZero
export extension_fields.csetOne
export extension_fields.cneg
export extension_fields.csub
export extension_fields.cadd

export extension_fields.`*=`
export extension_fields.prod
export extension_fields.square
export extension_fields.inv

export extension_fields.isSquare
export extension_fields.sqrt_if_square
export extension_fields.sqrt

export frobenius.frobenius_map

# Pairings
# ------------------------------------------------------------

export
  lines_eval.Line

export lines_eval.line_double
export lines_eval.line_add
export lines_eval.mul_by_line
export lines_eval.mul_by_2_lines

export cyclotomic_subgroups.finalExpEasy
export cyclotomic_subgroups.cyclotomic_inv
export cyclotomic_subgroups.cyclotomic_square
export cyclotomic_subgroups.cycl_sqr_repeated
export cyclotomic_subgroups.cyclotomic_exp
export cyclotomic_subgroups.isInCyclotomicSubgroup

export zoo_pairings.cycl_exp_by_curve_param
export zoo_pairings.cycl_exp_by_curve_param_div2
export zoo_pairings.millerLoopAddchain
export zoo_pairings.isInPairingSubgroup

export pairings_generic.pairing
export pairings_generic.millerLoop
export pairings_generic.finalExp

# Hashing to Elliptic Curve
# ------------------------------------------------------------

export hash_to_curve.hash_to_curve