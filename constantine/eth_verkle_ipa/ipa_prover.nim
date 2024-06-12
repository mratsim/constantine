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
  ./[transcript_gen, common_utils, eth_verkle_constants],
  ../platforms/primitives,
  ../hashes,
  ../serialization/[
    codecs_banderwagon,
    codecs_status_codes,
  ],
  ../commitments/pedersen_commitments,
  ../math/config/[type_ff, curves],
  ../math/elliptic/[ec_twistededwards_affine, ec_twistededwards_projective],
  ../math/polynomials/polynomials,
  ../math/arithmetic,
  ../math/io/io_fields,
  ../platforms/views,
  ../curves_primitives

# ############################################################
#
# Inner Product Argument using Pedersen Commitments
#
# ############################################################

# This Pedersen Commitment function shall be used in specifically the Split scalars
# and Split points that are used in the IPA polynomial

# Further reference refer to this https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

func genIPAConfig*(res: var IPASettings) =
  # Initiates a new IPASettings
  # IPASettings has all the necessary information related to create an IPA proof
  # such as crs, precomputed weights for Barycentric formula

  # The number of rounds for the prover and verifier must be in the IPA argument,
  # it should be log2 of the size of the input vectors for the IPA, since the vector size is halved on each round.

  # genIPAConfig( ) generates the crs, Q and the precomputed weights for barycentric formula. The crs is generated
  # as random points of the EthVerkleDomain where the relative discrete log is unknown between each generator.
  res.numRounds.computeNumRounds(uint64(EthVerkleDomain))
  res.crs.generate_random_points()
  res.domain.setupLinearEvaluationDomain()

func coverIPARounds*(
      res: var IPAProof,
      transcript: var CryptoHash,
      ic: IPASettings,
      a: openArray[Fr[Banderwagon]],
      b: openArray[Fr[Banderwagon]],
      cb_c: openArray[ECP_TwEdwards_Aff[Fp[Banderwagon]]],
      q: EC_P,
      idx: var int,
      rounds: int): bool =

  let a_view = a.toStridedView()
  let b_view = b.toStridedView()
  let cur_view = cb_c.toStridedView()

  let (a_L, a_R) = a_view.splitMiddle()
  let (b_L, b_R) = b_view.splitMiddle()
  let (G_L, G_R) = cur_view.splitMiddle()

  var z_L {.noInit.}: Fr[Banderwagon]
  z_L.computeInnerProducts(a_R, b_L)

  var z_R {.noInit.}: Fr[Banderwagon]
  z_R.computeInnerProducts(a_L, b_R)

  var C_L {.noInit.} = q
  C_L.scalarMul_vartime(z_L)

  var C_L_1 {.noInit.}: EC_P
  C_L_1.x.setZero()
  C_L_1.y.setZero()
  C_L_1.z.setOne()
  C_L_1.pedersen_commit(a_R, G_L)
  C_L += C_L_1

  var C_R {.noInit.} = q
  C_R.scalarMul_vartime(z_R)

  var C_R_1 {.noInit.}: EC_P
  C_R_1.x.setZero()
  C_R_1.y.setZero()
  C_R_1.z.setOne()
  C_R_1.pedersen_commit(a_L, G_R)
  C_R += C_R_1

  res.L_vector[idx] = C_L
  res.R_vector[idx] = C_R
  idx = idx + 1

  transcript.pointAppend(asBytes"L", C_L)
  transcript.pointAppend(asBytes"R", C_R)

  var x_big: matchingOrderBigInt(Banderwagon)
  x_big.generateChallengeScalar(transcript, asBytes"x")

  var x {.noInit.}: Fr[Banderwagon]
  x.fromBig(x_big)

  var xInv {.noInit.}: Fr[Banderwagon]
  xInv.inv(x)

  var ai, bi = newSeq[Fr[Banderwagon]](a_L.len)
  var gi = newSeq[ECP_TwEdwards_Aff[Fp[Banderwagon]]](a_L.len)

  ai.foldScalars(a_L, a_R, x)
  bi.foldScalars(b_L, b_R, xInv)
  gi.foldPoints(G_L, G_R, xInv)

  res.A_scalar = a_L[0]

  if idx == 7:
    return true

  coverIPARounds(res, transcript, ic, ai, bi, gi, q, idx, rounds)


func createIPAProof*[IPAProof](
      res: var IPAProof,
      transcript: var CryptoHash,
      ic: IPASettings,
      commitment: EC_P,
      a: var openArray[Fr[Banderwagon]],
      evalPoint: Fr[Banderwagon]) : bool =
  ## createIPAProof creates an IPA proof for a committed polynomial in evaluation form.
  ## `a` vectors are the evaluation points in the domain, and `evalPoint` represents the evaluation point.

  # TODO: for some result IPAProof must be zero-init beforehand
  #       hence we need to investigate why initialization may be incomplete.

  transcript.domain_separator(asBytes"ipa")
  var b: array[EthVerkleDomain, Fr[Banderwagon]]
  ic.domain.getLagrangeBasisPolysAt(b, evalPoint)

  var innerProd {.noInit.}: Fr[Banderwagon]
  innerProd.computeInnerProducts(a, b)

  transcript.pointAppend(asBytes"C", commitment)
  transcript.scalarAppend(asBytes"input point", evalPoint.toBig())
  transcript.scalarAppend(asBytes"output point", innerProd.toBig())

  var w {.noInit.}: matchingOrderBigInt(Banderwagon)
  w.generateChallengeScalar(transcript, asBytes"w")

  var q {.noInit.}: ECP_TwEdwards_Prj[Fp[Banderwagon]]
  q.fromAffine(Banderwagon.getGenerator())
  q.scalarMul_vartime(w)

  var idx = 0
  var num_rounds = 8
  # 0-indexed

  discard coverIPARounds(res, transcript, ic, a, b, ic.crs, q, idx, num_rounds)

  return true

# ############################################################
#
# IPA proof serializer
#
# ############################################################

func serializeVerkleIPAProof* (dst: var VerkleIPAProofSerialized, src: IPAProof): bool =
  ## IPA Proofs in Verkle consists of a Left array of 8 Base Field points, a Right array of 8 Base Field points, and a Scalar Field element
  ## During serialization the format goes as follows:
  ##
  ## L[0] (32 - byte array) L[1] (32 - byte array) .... L[7] (32 - byte array) ..... R[0] (32 - byte array) ... R[7] (32 - byte array) A (32 - byte array)
  ##
  ## Which means the size of the byte array should be :
  ##
  ## 32 * 8 (for Left half) + 32 * 8 (for Right half) + 32 * 1 (for Scalar) = 32 * 17 = 544 elements in the byte array.
  ##
  ## ----------------------------------------------------------
  ##
  ## Note that checks like Subgroup check for Banderwagon Points for Base Field elements in L and R,
  ## And checks for a valid scalar checking the Banderwagon scalar Curve Order is MANDATORY. They are all checked in the further low level functions
  ##
  var res = false
  var L_bytes {.noInit.} : array[8, array[32, byte]]
  var R_bytes {.noInit.} : array[8, array[32, byte]]

  let stat1 = L_bytes.serializeBatch(src.L_vector)
  doAssert stat1 == cttCodecEcc_Success, "Batch serialization Failure!"

  let stat2 = R_bytes.serializeBatch(src.R_vector)
  doAssert stat2 == cttCodecEcc_Success, "Batch Serialization Failure!"

  var A_bytes {.noInit.} : array[32, byte]
  let stat3 = A_bytes.serialize_scalar(src.A_scalar.toBig(), littleEndian)
  doAssert stat3 == cttCodecScalar_Success, "Scalar Serialization Failure!"

  var idx: int = 0

  for i in 0 ..< 8:
    for j in 0 ..< 32:
      dst[idx] = L_bytes[i][j]
      idx = idx + 1

  discard L_bytes

  for i in 0 ..< 8:
    for j in 0 ..< 32:
      dst[idx] = R_bytes[i][j]
      idx = idx + 1

  discard R_bytes

  for i in 0 ..< 32:
    dst[idx] = A_bytes[i]
    idx = idx + 1

  discard A_bytes

  res = true
  return res

# ############################################################
#
# IPA proof deserializer
#
# ############################################################

func deserializeVerkleIPAProof* (dst: var IPAProof, src: var VerkleIPAProofSerialized ): bool =
  ## IPA Proofs in Verkle consists of a Left array of 8 Base Field points, a Right array of 8 Base Field points, and a Scalar Field element
  ## During deserialization the format goes as follows:
  ##
  ## L[0] (32 - byte array) L[1] (32 - byte array) .... L[7] (32 - byte array) ..... R[0] (32 - byte array) ... R[7] (32 - byte array) A (32 - byte array)
  ##
  ## Which means the size of the byte array should be :
  ##
  ## 32 * 8 (for Left half) + 32 * 8 (for Right half) + 32 * 1 (for Scalar) = 32 * 17 = 544 elements in the byte array.
  ## ----------------------------------------------------------
  ##
  ## Note that check for Lexicographically Largest criteria for the Y - coordinate of the Twisted Edward Banderwagon point is MANDATORY
  ## And, is pre-checked within this function from the `deserialize` function.
  ##
  var res = false

  var L_bytes {.noInit.} : array[8, array[32, byte]]
  var R_bytes {.noInit.} : array[8, array[32, byte]]
  var A_bytes {.noInit.} : array[32, byte]

  var L_side {.noInit.} : array[8, EC_P]
  var R_side {.noInit.} : array[8, EC_P]

  var A_inter {.noInit.} : matchingOrderBigInt(Banderwagon)
  var A_fr {.noInit.} : Fr[Banderwagon]

  var idx : int = 0

  for i in 0 ..< 8:
    for j in 0 ..< 32:
      L_bytes[i][j] = src[idx]
      idx = idx + 1

  for i in 0 ..< 8:
    for j in 0 ..< 32:
      R_bytes[i][j] = src[idx]
      idx = idx + 1

  for i in 0 ..< 32:
    A_bytes[i] = src[idx]
    idx = idx + 1

  var i : int = 0
  for item in L_bytes.items():
    discard L_side[i].deserialize(item)
    i = i + 1

  discard L_bytes

  doAssert i == 8, "Should be 8!"

  i  = 0
  for item in R_bytes.items():
    discard R_side[i].deserialize(item)
    i = i + 1

  discard R_bytes

  doAssert i == 8, "Should be 8!"

  let stat2 = A_inter.deserialize_scalar(A_bytes, littleEndian)
  doAssert stat2 == cttCodecScalar_Success, "Scalar Deserialization failure!"

  discard A_bytes

  dst.L_vector = L_side
  dst.R_vector = R_side

  A_fr.fromBig(A_inter)

  dst.A_scalar = A_fr

  res = true
  return res

# ############################################################
#
# IPA proof equality checker
#
# ############################################################

func `==`* (p1: IPAProof, p2: IPAProof) : bool =
  var res {.noInit.}: bool
  const num_rounds = 8
  res = true
  if p1.L_vector.len != p2.R_vector.len:
    res = false

  if p1.R_vector.len != p2.R_vector.len:
    res = false

  if p1.L_vector.len != p1.R_vector.len:
    res = false

  for i in 0 ..< num_rounds:
    var exp_li = p1.L_vector[i]
    var exp_ri = p1.R_vector[i]

    var got_li = p2.L_vector[i]
    var got_ri = p2.R_vector[i]

    if not(exp_li == got_li).bool():
      res = false

    if not(exp_ri == got_ri).bool():
      res = false

  if not(p1.A_scalar == p2.A_scalar).bool():
    res = false

  else:
    res = true
  return res
