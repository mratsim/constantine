# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
# All the util functions for Inner Product Arguments Prover
#
# ############################################################

import
  ../../../constantine/platforms/primitives,
  ../../../constantine/hashes,
  ../../math/config/[type_ff, curves],
  ../../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
  ../../../constantine/math/arithmetic,
  ../../../constantine/math/elliptic/ec_scalar_mul, 
  ../../../constantine/platforms/[views],
  ../../../constantine/math/io/[io_fields],
  ../../../constantine/curves_primitives

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = Fr[Banderwagon]

type 
    IPAProof* = object
     L_vector: openArray[EC_P]
     R_vector: openArray[EC_P]
     A_scalar: EC_P_Fr

type 
    MultiProof* = object
     IPAprv: IPAProof
     D: EC_P

const
 DOMAIN*: uint64 = 256

type 
 PrecomputedWeights* = object
  barycentricWeights: openArray[EC_P_Fr]
  invertedDomain: openArray[EC_P_Fr]

type
   IPASettings* = object
    SRS : openArray[EC_P]
    Q_val : EC_P
    PrecomputedWeights: PrecomputedWeights
    numRounds: uint32

const seed* = asBytes"eth_verkle_oct_2021"

type Bytes* = array[32, byte]

type
    Coord* = object 
     x*: EC_P_Fr
     y*: EC_P_Fr
