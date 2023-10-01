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

func createIPAProof*[IPAProof] (res: var IPAProof, transcript: Transcript, ic: IPASettings, commitment: EC_P, a: openArray[EC_P_Fr], evalPoint: EC_P_Fr )=
  transcript.domain_separator(asBytes"ipa")
  var b {.noInit.}: array[DOMAIN, EC_P_Fr]
  
  b = ic.PrecomputedWeights.computeBarycentricCoefficients(evalPoint)
  var innerProd {.noInit.}: EC_P_Fr

  var check {.noInit.}: bool
  
  check = innerProd.computeInnerProducts(a,b.toBig())

  assert check == true, "Could not compute the Inner Product"

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

    (a_L, a_R).splitScalars()

    var b_L, b_R {.noInit.}: EC_P_Fr

    b_L.toStridedView()
    b_R.toStridedView()

    (b_L, b_R).splitScalars()

    var G_L, G_R {.noInit.}: EC_P

    (G_L, G_R).splitPoints()

    var z_L {.noInit.}: EC_P_Fr
    z_L.computeInnerProducts( )








  



