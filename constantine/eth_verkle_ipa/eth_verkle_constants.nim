# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
# All the Helper Functions needed for Verkle Cryptography API
#
# ############################################################

import
  ../platforms/primitives,
  ../math/config/[type_ff, curves],
  ../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_affine],
  ../math/arithmetic,
  ../math/io/[io_fields],
  ../hashes,
  ../curves_primitives

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Aff* = ECP_TwEdwards_Aff[Fp[Banderwagon]]

type 
    IPAProof* = object
     L_vector*: array[8,EC_P]
     R_vector*: array[8,EC_P]
     A_scalar*: Fr[Banderwagon]

type 
    MultiProof* = object
     IPAprv*: IPAProof
     D*: EC_P

const
 VerkleDomain*: int = 256

type 
 PrecomputedWeights* = object
  barycentricWeights*: array[510,Fr[Banderwagon]]
  invertedDomain*: array[510,Fr[Banderwagon]]

type
   IPASettings* = object
    SRS*: array[VerkleDomain,EC_P]
    Q_val*: EC_P
    precompWeights*: PrecomputedWeights
    numRounds*: uint32

const VerkleSeed* = asBytes"eth_verkle_oct_2021"

type Bytes* = array[32, byte]

type IpaTranscript* [H: CryptoHash, N: static int] = object
  ctx*: H
  label*: array[N, byte]

type
    Coord* = object 
     x*: Fr[Banderwagon]
     y*: Fr[Banderwagon]

var generator* = Banderwagon.getGenerator()
