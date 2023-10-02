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
  ./[transcript_gen, common_utils],
  ../../../constantine/platforms/primitives,
  ../../math/config/[type_ff, curves],
  ../../math/elliptic/ec_twistededwards_projective,
  ../../../constantine/hashes,
  ../../../constantine/math/arithmetic,
  ../../../constantine/math/elliptic/ec_scalar_mul, 
  ../../../constantine/platforms/[bithacks,views],
  ../../../constantine/math/io/[io_fields],
  ../../../constantine/curves_primitives,
  ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = ECP_TwEdwards_Prj[Fr[Banderwagon]]

type 
    IPAProof* = object
     L_vector: openArray[EC_P]
     R_vector: openArray[EC_P]
     A_scalar: EC_P_Fr

const
 DOMAIN: uint64 = 256

# ############################################################
#
#     Inner Product Argument using Pedersen Commitments
#
# ############################################################

# This Pedersen Commitment function shall be used in specifically the Split scalars 
# and Split points that are used in the IPA polynomial

# Further reference refer to this https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

func createIPAProof*[IPAProof] (res: var IPAProof, transcript: var Transcript, ic: IPASettings, commitment: EC_P, a: openArray[EC_P_Fr], evalPoint: EC_P_Fr )=
  transcript.domain_separator(asBytes"ipa")
  var b {.noInit.}: array[DOMAIN, EC_P_Fr]
  
  b = ic.PrecomputedWeights.computeBarycentricCoefficients(evalPoint)
  var innerProd {.noInit.}: EC_P_Fr

  var check {.noInit.}: bool
  
  innerProd.computeInnerProducts(a,b.toBig())

  transcript.pointAppend(commitment, asBytes"C")
  transcript.scalarAppend(evalPoint, asBytes"input point")
  transcript.scalarAppend(innerProd, asBytes"output point")

  let w = transcript.generateChallengeScalar("w")

  var q {.noInit.} : EC_P
  q.scalarMul(ic.Q_val, w.toBig())

  let num_rounds = ic.numRounds

  let current_basis = ic.SRS

  var L {.noInit.}: array[num_rounds, EC_P]

  var R {.noInit.}: array[num_rounds, EC_P]

  for i in 0..<int(num_rounds):
    
    var a_L, a_R {.noInit.}: EC_P_Fr

    a_L.toStridedView()
    a_R.toStridedView()

    (a_L, a_R).splitScalars(a)

    var b_L, b_R {.noInit.}: EC_P_Fr

    b_L.toStridedView()
    b_R.toStridedView()

    (b_L, b_R).splitScalars(b)

    var G_L, G_R {.noInit.}: EC_P

    G_L.toStridedView()
    G_R.toStridedView()

    (G_L, G_R).splitPoints(current_basis)

    var z_L {.noInit.}: EC_P_Fr
    z_L.computeInnerProducts(a_R.data, b_L.data)

    var z_R {.noInit.}: EC_P_Fr
    z_R.computeInnerProducts(a_L.data, b_R.data)

    var C_L_1 {.noInit.}: EC_P
    C_L_1.pedersen_commit_single(G_L.data, a_R.data)

    var C_L {.noInit.}: EC_P
    C_L.pedersen_commit_single([C_L_1, q], [EC_P_Fr.setOne(), z_L.data])

    var C_R_1 {.noInit.}: EC_P
    C_R_1.pedersen_commit_single(G_R.data, a_L.data)

    var C_R {.noInit.}: EC_P
    C_R.pedersen_commit_single([C_R_1, q], [EC_P_Fr.setOne(), z_R.data])

    L[i] = C_L
    R[i] = C_R

    transcript.pointAppend(C_L,asBytes"L")
    transcript.pointAppend(C_R,asBytes"R")

    var x {.noInit.}: EC_P_Fr
    x.generateChallengeScalar(asBytes"x")

    var xInv {.noInit.}: EC_P_Fr
    xInv.inv(x)

    a.foldScalars(a_L.data, a_R.data, x)

    b.foldScalars(b_L.data, b_R.data, xInv)

    current_basis.foldPoints(G_L.data, G_R.data, xInv)

  debug: doAssert not(a.len == 1), "Length of `a` should be 1 at the end of the reduction"

  res.L_vector = L
  res.R_vector = R
  res.A_scalar = a[0]


# func serializeIPA* [IPAProof] (res: var IPAProof)=
  




  



