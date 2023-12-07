# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./math/config/[curves, type_bigint, type_ff],
  ./threadpool,
  ./math/elliptic/ec_multi_scalar_mul_parallel,
  ./math/ec_shortweierstrass

# ############################################################
#
#            Generator for low-level parallel primitives API
#
# ############################################################

# Threadpool
# ------------------------------------------------------------

export threadpool.Threadpool
export threadpool.new
export threadpool.shutdown

# Base types
# ------------------------------------------------------------

export curves.Curve
export type_bigint.BigInt
export
  type_ff.Fp,
  type_ff.Fr,
  type_ff.FF

# Elliptic curve
# ------------------------------------------------------------

export
  ec_shortweierstrass.Subgroup,
  ec_shortweierstrass.ECP_ShortW_Aff,
  ec_shortweierstrass.ECP_ShortW_Jac,
  ec_shortweierstrass.ECP_ShortW_Prj,
  ec_shortweierstrass.ECP_ShortW

export
  ec_multi_scalar_mul_parallel.multiScalarMul_vartime_parallel