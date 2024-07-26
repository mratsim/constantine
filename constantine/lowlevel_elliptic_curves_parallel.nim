# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./named/algebras,
  ./platforms/abstractions,
  ./threadpool,
  ./math/elliptic/ec_multi_scalar_mul_parallel,
  ./math/ec_shortweierstrass

# ############################################################
#
#         Low-level named Elliptic Curve Parallel API
#
# ############################################################

# Warning ⚠️:
#     The low-level APIs have no stability guarantee.
#     Use high-level protocols which are designed according to a stable specs
#     and with misuse resistance in mind.

# Threadpool
# ------------------------------------------------------------

export threadpool.Threadpool
export threadpool.new
export threadpool.shutdown

# Base types
# ------------------------------------------------------------

export algebras.Algebra
export abstractions.BigInt
export
  algebras.Fp,
  algebras.Fr,
  algebras.FF

# Elliptic curve
# ------------------------------------------------------------

export
  ec_shortweierstrass.Subgroup,
  ec_shortweierstrass.EC_ShortW_Aff,
  ec_shortweierstrass.EC_ShortW_Jac,
  ec_shortweierstrass.EC_ShortW_Prj,
  ec_shortweierstrass.EC_ShortW

export
  ec_multi_scalar_mul_parallel.multiScalarMul_vartime_parallel
