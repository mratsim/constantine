# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO: This file is deprecated, all functionality is being replaced
# by commitments/eth_verkle_ipa

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
  ../math/polynomials/polynomials,
  ../hashes,
  ../curves_primitives

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Aff* = ECP_TwEdwards_Aff[Fp[Banderwagon]]

type Bytes* = array[32, byte]

type
  Point* = EC_P
  Field* = Fr[Banderwagon]

type
  IPAProofDeprecated* = object
    L_vector*: array[8, ECP_TwEdwards_Aff[Fp[Banderwagon]]]
    R_vector*: array[8, ECP_TwEdwards_Aff[Fp[Banderwagon]]]
    A_scalar*: Fr[Banderwagon]

type
  MultiProof* = object
    IPAprv*: IPAProofDeprecated
    D*: ECP_TwEdwards_Aff[Fp[Banderwagon]]

const
  EthVerkleDomain*: int = 256

type VerkleIPAProofSerialized* = array[544, byte]

type VerkleMultiproofSerialized* = array[576, byte]

type
  IPASettings* = object
    crs*: array[EthVerkleDomain, ECP_TwEdwards_Aff[Fp[Banderwagon]]]
    domain*: PolyEvalLinearDomain[EthVerkleDomain, Fr[Banderwagon]]
    numRounds*: uint32

const VerkleSeed* = asBytes"eth_verkle_oct_2021"

type IpaTranscript* [H: CryptoHash, N: static int] = object
  ctx*: H
  label*: array[N, byte]

type
  Coord* = object
    x*: Fr[Banderwagon]
    y*: Fr[Banderwagon]
