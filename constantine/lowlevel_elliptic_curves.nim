# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ./platforms/abstractions,
    ./named/algebras,
    ./named/[zoo_subgroups, zoo_generators],
    ./math/ec_shortweierstrass,
    ./math/elliptic/[
      ec_scalar_mul_vartime,
      ec_multi_scalar_mul],
    ./math/io/io_ec,
    ./hash_to_curve/hash_to_curve

# ############################################################
#
#            Low-level named Elliptic Curve API
#
# ############################################################

# Warning ⚠️:
#     The low-level APIs have no stability guarantee.
#     Use high-level protocols which are designed according to a stable specs
#     and with misuse resistance in mind.

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push inline.}

# Base types
# ------------------------------------------------------------

export
  abstractions,
  algebras.Algebra

# Elliptic curve
# ------------------------------------------------------------

export
  ec_shortweierstrass.Subgroup,
  ec_shortweierstrass.EC_ShortW_Aff,
  ec_shortweierstrass.EC_ShortW_Jac,
  ec_shortweierstrass.EC_ShortW_Prj,
  ec_shortweierstrass.EC_ShortW

export ec_shortweierstrass.`==`
export ec_shortweierstrass.isNeutral
export ec_shortweierstrass.setNeutral
export ec_shortweierstrass.setGenerator
export ec_shortweierstrass.ccopy
export ec_shortweierstrass.isOnCurve
export ec_shortweierstrass.neg
export ec_shortweierstrass.cneg

export ec_shortweierstrass.affine
export ec_shortweierstrass.fromAffine
export ec_shortweierstrass.batchAffine

export ec_shortweierstrass.sum
export ec_shortweierstrass.sum_vartime
export ec_shortweierstrass.`+=`
export ec_shortweierstrass.`~+=`
export ec_shortweierstrass.double
export ec_shortweierstrass.diff
export ec_shortweierstrass.diff_vartime
export ec_shortweierstrass.`-=`
export ec_shortweierstrass.`~-=`
export ec_shortweierstrass.mixedSum
export ec_shortweierstrass.mixedDiff

export ec_shortweierstrass.scalarMul
export ec_scalar_mul_vartime.scalarMul_vartime
export ec_multi_scalar_mul.multiScalarMul_vartime

export zoo_generators.getGenerator
export zoo_subgroups.clearCofactor
export zoo_subgroups.isInSubgroup

# Hashing to Elliptic Curve
# ------------------------------------------------------------

export hash_to_curve.hash_to_curve
