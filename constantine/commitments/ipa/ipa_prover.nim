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
  ./[transcript_gen, common_utils, helper_types, barycentric_form],
  ../../../constantine/platforms/primitives,
  ../../../constantine/hashes,
  ../../math/config/[type_ff, curves],
  ../../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
  ../../../constantine/math/arithmetic,
  ../../../constantine/math/elliptic/ec_scalar_mul, 
  ../../../constantine/platforms/[views],
  ../../../constantine/math/io/[io_fields],
  ../../../constantine/curves_primitives,
  ../../../constantine/ethereum_verkle_primitives

# ############################################################
#
#     Inner Product Argument using Pedersen Commitments
#
# ############################################################

# This Pedersen Commitment function shall be used in specifically the Split scalars 
# and Split points that are used in the IPA polynomial

# Further reference refer to this https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

# Initiates a new IPASetting
func genIPAConfig*(res: var IPASettings) : bool {.inline.}=
  res.SRS.generate_random_points(uint64(DOMAIN))
  res.Q_val.fromAffine(Banderwagon.getGenerator())
  res.precompWeights.newPrecomputedWeights()
  res.numRounds.computeNumRounds(uint64(DOMAIN))
  return true

func createIPAProof*[IPAProof] (res: var IPAProof, transcript: var sha256, ic: IPASettings, commitment: EC_P, a: openArray[EC_P_Fr], evalPoint: EC_P_Fr )=
  transcript.domain_separator(asBytes"ipa")
  var b {.noInit.}: array[DOMAIN, EC_P_Fr]
  
  b = ic.PrecomputedWeights.computeBarycentricCoefficients(evalPoint)
  var innerProd {.noInit.}: EC_P_Fr

  var check {.noInit.}: bool
  
  innerProd.computeInnerProducts(a,b.toBig())

  transcript.pointAppend(commitment, asBytes"C")
  transcript.scalarAppend(evalPoint, asBytes"input point")
  transcript.scalarAppend(innerProd, asBytes"output point")

  var w = transcript.generateChallengeScalar("w")

  var q {.noInit.} : EC_P
  q.scalarMul(ic.Q_val, w.toBig())

  var num_rounds = ic.numRounds

  var current_basis = ic.SRS

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

type 
  serIPA* = object
   lv*: Bytes
   rv*: Bytes
   asc*: Bytes


func serialzeIPAProof* [serIPA] (res : var serIPA, proof : IPAProof)=
  let stat1 = res.lv.serializeBatch(proof.L_vector)
  doAssert stat1 == cttCodecEcc_Success, "Serialization Failed"
  let stat2 = res.rv.serializeBatch(proof.R_vector)
  doAssert stat2 == cttCodecEcc_Success, "Serialization Failed"

  res.asc.serialize_scalar(proof.A_scalar)









  




  



