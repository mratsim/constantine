# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                Montgomery domain primitives
#
# ############################################################

import
  ./primitives, ./bigints, ./field_fp, ./curves_config

# No exceptions allowed
{.push raises: [].}

func toMonty*[C: static Curve](a: Fp[C]): Montgomery[C] =
  ## Convert a big integer over Fp to it's montgomery representation
  ## over Fp.
  ## i.e. Does "a * (2^LimbSize)^W (mod p), where W is the number
  ## of words needed to represent p in base 2^LimbSize

  result = a
  for i in static(countdown(C.Mod.limbs.high, 1)):
    shiftAdd(result, 0)
