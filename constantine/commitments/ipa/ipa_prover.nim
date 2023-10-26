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

func createIPAProof*[IPAProof] (res: var IPAProof, transcript: var sha256, ic: IPASettings, commitment: EC_P, a: var openArray[EC_P_Fr], evalPoint: EC_P_Fr ) : bool {.inline.}=
  transcript.domain_separator(asBytes"ipa")
  var b {.noInit.}: array[DOMAIN, EC_P_Fr]
  
  b.computeBarycentricCoefficients(ic.precompWeights,evalPoint)
  var innerProd {.noInit.}: EC_P_Fr

  var check {.noInit.}: bool

  innerProd.computeInnerProducts(a,b)

  transcript.pointAppend(asBytes"C", commitment)
  transcript.scalarAppend(asBytes"input point", evalPoint.toBig())
  transcript.scalarAppend(asBytes"output point", innerProd.toBig())

  var w : matchingOrderBigInt(Banderwagon)
  w.generateChallengeScalar(transcript,asBytes"w")

  var q {.noInit.} : EC_P
  q = ic.Q_val
  q.scalarMul(w)

  var current_basis {.noInit.}: array[DOMAIN, EC_P]
  current_basis = ic.SRS

  var num_rounds = ic.numRounds

  var L {.noInit.}: array[8, EC_P]

  var R {.noInit.}: array[8, EC_P]

  var a_stri = a.toStridedView()
  var b_stri = b.toStridedView()
  var current_basis_stri = current_basis.toStridedView()

  for i in 0..<int(num_rounds):

    var (a_L, a_R) = a_stri.splitMiddle()
    var (b_L, b_R) = b_stri.splitMiddle()

    var (G_L, G_R) = current_basis_stri.splitMiddle()

    var z_L {.noInit.}: EC_P_Fr
    z_L.computeInnerProducts(a_R.toOpenArray(), b_L.toOpenArray())

    var z_R {.noInit.}: EC_P_Fr
    z_R.computeInnerProducts(a_L.toOpenArray(), b_R.toOpenArray())
    var one : EC_P_Fr
    one.setOne()

    var C_L_1 {.noInit.}: EC_P
    C_L_1.pedersen_commit_varbasis(G_L.toOpenArray(), a_R.toOpenArray())

    var fp1 : array[2, EC_P]
    fp1[0] = C_L_1
    fp1[1] = q

    var fr1 : array[2, EC_P_Fr]
    fr1[0] = one
    fr1[1] = z_L

    var C_L {.noInit.}: EC_P
    C_L.pedersen_commit_varbasis(fp1,fr1)

    var C_R_1 {.noInit.}: EC_P
    C_R_1.pedersen_commit_varbasis(G_R.toOpenArray(), a_L.toOpenArray())

    var C_R {.noInit.}: EC_P


    var fp2 : array[2, EC_P]
    fp2[0]=C_R_1
    fp2[1]=q

    var fr2: array[2, EC_P_Fr]
    fr2[0]=one
    fr2[1]=z_R

    C_R.pedersen_commit_varbasis(fp2, fr2)

    L[i] = C_L
    R[i] = C_R

    transcript.pointAppend(asBytes"L", C_L)
    transcript.pointAppend(asBytes"R", C_R)

    var x_big: matchingOrderBigInt(Banderwagon)
    x_big.generateChallengeScalar(transcript, asBytes"x")

    var x: EC_P_Fr
    x.fromBig(x_big)

    var xInv: EC_P_Fr
    xInv.inv(x)

    a.foldScalars(a_L.toOpenArray(), a_R.toOpenArray(), x)

    b.foldScalars(b_L.toOpenArray(), b_R.toOpenArray(), xInv)

    current_basis.foldPoints(G_L.toOpenArray(), G_R.toOpenArray(), xInv)

  doAssert not(a.len == 1), "Length of `a` should be 1 at the end of the reduction"

  res.L_vector = L
  res.R_vector = R
  res.A_scalar = a[0]
  return true

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









  




  



