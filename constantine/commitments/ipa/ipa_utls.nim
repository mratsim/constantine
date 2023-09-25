# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#      All the util functions for Inner Product Arguments
#
# ############################################################

import
    std/typetraits,
    ../../platforms/primitives,
    ../../serialization/endians,
    ../../../constantine/platforms/primitives,
    ../../math/config/[type_ff, curves],
    ../../math/elliptic/ec_twistededwards_projective,
    ../../../constantine/hashes,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]

type 
    IPAProof* = object
     L_vector: seq[EC_P]
     R_vector: seq[EC_P]
     A_scalar: EC_P


