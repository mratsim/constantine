# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  tables,
  sequtils,
  ./[transcript_gen, common_utils, ipa_prover, barycentric_form, eth_verkle_constants, ipa_verifier],
  ../platforms/primitives,
  ../hashes,
  ../serialization/[
    codecs_banderwagon,
    codecs_status_codes,
  ],
  ../math/config/[type_ff, curves],
  ../math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
  ../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
  ../math/arithmetic,
  ../platforms/[views],
  ../math/io/[io_bigints,io_fields],
  ../curves_primitives


# ############################################################
#
#                   Multiproof System
#
# ############################################################


func domainToFrElem*(res: var Fr, inp: matchingOrderBigInt(Banderwagon))=
  var x {.noInit.} : Fr[Banderwagon]
  x.fromBig(inp)
  res = x

# Computes the powers of an Fr[Banderwagon][Banderwagon] element
func computePowersOfElem*(res: var openArray[Fr], x: Fr, degree: SomeSignedInt)= 
  res[0].setOne()
  for i in 1 ..< degree:
    res[i].prod(res[i-1], x)


# ############################################################
#
#                   Multiproof Creation
#
# ############################################################
    

func createMultiProof* [MultiProof] (res: var MultiProof, transcript: var CryptoHash, ipaSetting: IPASettings, Cs: openArray[EC_P], Fs: array[VerkleDomain, array[VerkleDomain, Fr[Banderwagon]]], Zs: openArray[int]) : bool =
  # createMultiProof creates a multi-proof for several polynomials in the evaluation form
  # The list of triplets are as follows: (C, Fs, Z) represents each polynomial commitment
  # and their evaluation in the domain, and the evaluating point respectively
  var success {.noInit.} : bool
  transcript.domain_separator(asBytes"multiproof")

  for f in Fs:
    debug: doAssert f.len == VerkleDomain, "Polynomial length does not match with the VerkleDomain length!"
    
  debug: doAssert Cs.len == Fs.len, "Number of commitments is NOT same as number of Functions"

  debug: doAssert Cs.len == Zs.len, "Number of commitments is NOT same as the number of Points"

  var num_queries {.noInit.}: int
  num_queries = Cs.len

  for i in 0 ..< num_queries:
    transcript.pointAppend(asBytes"C", Cs[i])
    var z {.noInit.}: Fr[Banderwagon]
    z.fromInt(Zs[i])
    transcript.scalarAppend(asBytes"z",z.toBig())

    # deducing the `y` value

    var f = Fs[i]
    var y = f[Zs[i]]
    transcript.scalarAppend(asBytes"y", y.toBig())

  var r {.noInit.} : matchingOrderBigInt(Banderwagon)
  r.generateChallengeScalar(transcript,asBytes"r")

  var r_fr {.noInit.}: Fr[Banderwagon]
  r_fr.fromBig(r)

  var powersOfr {.noInit.} = newSeq[Fr[Banderwagon]](int(num_queries))
  powersOfr.computePowersOfElem(r_fr, int(num_queries))

  # In order to compute g(x), we first compute the polynomials in lagrange form grouped by evaluation points
  # then we compute g(x), this is eventually limit the numbers of divisionOnDomain calls up to the domain size 

  var groupedFs: array[VerkleDomain, array[VerkleDomain, Fr[Banderwagon]]]
  for i in 0 ..< VerkleDomain:
    for j in 0 ..< VerkleDomain:
      groupedFs[i][j].setZero()

  for i in 0 ..< num_queries:
    var z = Zs[i]
    var r {.noInit.}: Fr[Banderwagon]
    r = powersOfr[i]

    for j in 0 ..< VerkleDomain:
      var scaledEvals {.noInit.}: Fr[Banderwagon]
      scaledEvals.prod(r, Fs[i][j])
      groupedFs[z][j] += scaledEvals
  
  var gx {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< VerkleDomain:
    gx[i].setZero()

  for i in 0 ..< VerkleDomain:
    let check = groupedFs[i][0].isZero()
    if check.bool() == true:
      continue

    var quotient {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
    var passer = uint8(i)
    quotient.divisionOnDomain(ipaSetting.precompWeights, passer, groupedFs[i])
    
    for j in  0 ..< VerkleDomain:
      gx[j] += quotient[j]

  var D {.noInit.}: EC_P
  D.pedersen_commit_varbasis(ipaSetting.SRS,ipaSetting.SRS.len, gx, gx.len)

  transcript.pointAppend(asBytes"D", D)

  var t {.noInit.}: matchingOrderBigInt(Banderwagon)
  t.generateChallengeScalar(transcript,asBytes"t")

  var t_fr {.noInit.}: Fr[Banderwagon]
  t_fr.fromBig(t)

  # Computing the denominator inverses only for referenced evaluation points.
  var denInv {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]

  var idxx = 0
  for i in 0 ..< VerkleDomain:
    let check = groupedFs[i][0].isZero()
    if check.bool() == true:
      continue

    var z_fr {.noInit.}: Fr[Banderwagon]
    z_fr.fromInt(i)
    var deno {.noInit.}: Fr[Banderwagon]
    deno.diff(t_fr, z_fr)
    
    denInv[idxx] = deno
    idxx = idxx + 1


  var denInv_prime {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  denInv_prime.batchInvert(denInv)

  #Compute h(X) = g1(X)
  var hx {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  var denInvIdx = 0

  for i in 0 ..< VerkleDomain:
    let check = groupedFs[i][0].isZero()
    if check.bool() == true:
      continue

    for k in 0 ..< VerkleDomain:
      var tmp {.noInit.}: Fr[Banderwagon]
      tmp.prod(groupedFs[i][k], denInv_prime[denInvIdx])
      hx[k] += tmp

    denInvIdx = denInvIdx + 1

  var hMinusg {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]

  for i in 0 ..< VerkleDomain:
    hMinusg[i].diff(hx[i],gx[i])

  var E {.noInit.}: EC_P

  E.pedersen_commit_varbasis(ipaSetting.SRS, ipaSetting.SRS.len, hx, hx.len)
  transcript.pointAppend(asBytes"E",E)

  var EMinusD {.noInit.}: EC_P
  EMinusD.diff(E,D)

  var ipaProof {.noInit.}: IPAProof

  var checks: bool
  checks = ipaProof.createIPAProof(transcript, ipaSetting, EMinusD, hMinusg, t_fr)

  doAssert checks == true, "Could not compute IPA Proof!"

  res.IPAprv = ipaProof
  res.D = D
  success = true

  return success

# ############################################################
#
#                 Multiproof Verification
#
# ############################################################
    

func verifyMultiproof*(multiProof: var MultiProof, transcript : var CryptoHash, ipaSettings: IPASettings, Cs: openArray[EC_P], Ys: openArray[Fr[Banderwagon]], Zs: openArray[int]) : bool =
  # Multiproof verifier verifies the multiproof for several polynomials in the evaluation form
  # The list of triplets (C,Y,Z) represents each polynomial commitment, evaluation
  # result, and evaluation point in the domain 
  var res {.noInit.} : bool
  transcript.domain_separator(asBytes"multiproof")

  debug: doAssert Cs.len == Ys.len, "Number of commitments and the Number of output points don't match!"

  debug: doAssert Cs.len == Zs.len, "Number of commitments and the Number of input points don't match!"

  var num_queries = Cs.len

  for i in 0 ..< num_queries:
    transcript.pointAppend(asBytes"C", Cs[i])
    var z {.noInit.} : Fr[Banderwagon]
    z.fromInt(Zs[i])

    transcript.scalarAppend(asBytes"z", z.toBig())
    transcript.scalarAppend(asBytes"y", Ys[i].toBig())

  var r {.noInit.}: matchingOrderBigInt(Banderwagon)
  r.generateChallengeScalar(transcript,asBytes"r")

  var r_fr {.noInit.}: Fr[Banderwagon]
  r_fr.fromBig(r)

  var powersOfr {.noInit.} = newSeq[Fr[Banderwagon]](int(num_queries))
  powersOfr.computePowersOfElem(r_fr, int(num_queries))

  transcript.pointAppend(asBytes"D", multiProof.D)

  var t {.noInit.}: matchingOrderBigInt(Banderwagon)
  t.generateChallengeScalar(transcript, asBytes"t")

  var t_fr {.noInit.}: Fr[Banderwagon]
  t_fr.fromBig(t)

  # Computing the polynomials in the Lagrange form grouped by evaluation point, 
  # and the needed helper scalars
  var groupedEvals {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< VerkleDomain:
    groupedEvals[i].setZero()

  for i in 0 ..< num_queries:
    var z = Zs[i]
    var r {.noInit.} : Fr[Banderwagon]
    r = powersOfr[i]
    var scaledEvals {.noInit.}: Fr[Banderwagon]
    scaledEvals.prod(r, Ys[i])

    groupedEvals[z] += scaledEvals

  # Calculating the helper scalar denominator, which is 1 / t - z_i
  var helperScalarDeno {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< VerkleDomain:
    helperScalarDeno[i].setZero()

  for i in 0 ..< VerkleDomain:
    var z {.noInit.}: Fr[Banderwagon]
    z.fromInt(i)
    helperScalarDeno[i].diff(t_fr, z)

  var helperScalarDeno_prime {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  helperScalarDeno_prime.batchInvert(helperScalarDeno)

  # Compute g_2(t) = SUMMATION (y_i * r^i) / (t - z_i) = SUMMATION (y_i * r) * helperScalarDeno
  var g2t {.noInit.}: Fr[Banderwagon]

  for i in 0 ..< VerkleDomain:
    let stat = groupedEvals[i].isZero()
    if stat.bool() == true:
      continue

    var tmp {.noInit.}: Fr[Banderwagon]
    tmp.prod(groupedEvals[i], helperScalarDeno_prime[i])
    g2t += tmp

  
  # Compute E = SUMMATION C_i * (r^i /  t - z_i) = SUMMATION C_i * MSM_SCALARS
  var msmScalars {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< VerkleDomain:
    msmScalars[i].setZero()

  var Csnp {.noInit.}: array[VerkleDomain, EC_P]
  for i in 0 ..< VerkleDomain:
    Csnp[i].setInf()

  for i in 0 ..< Cs.len:
    Csnp[i] = Cs[i]
    msmScalars[i].prod(powersOfr[i], helperScalarDeno_prime[Zs[i]])
  
  var E {.noInit.}: EC_P

  var Csnp_aff {.noInit.}: array[VerkleDomain, EC_P_Aff]
  for i in 0 ..< Cs.len:
    Csnp_aff[i].affine(Csnp[i])

  var msmScalars_big {.noInit.}: array[VerkleDomain, matchingOrderBigInt(Banderwagon)]

  for i in 0 ..< VerkleDomain:
    msmScalars_big[i] = msmScalars[i].toBig()
  
  E.multiScalarMul_reference_vartime(msmScalars_big, Csnp_aff)

  transcript.pointAppend(asBytes"E", E)

  var EMinusD {.noInit.} : EC_P
  EMinusD.diff(E, multiProof.D)

  var got {.noInit.}: EC_P
  res = got.checkIPAProof(ipaSettings, transcript, EMinusD, multiProof.IPAprv, t_fr, g2t)
  if res == false:
    return res

  return res

# ############################################################
#
#                 Multiproof Serializer
#
# ############################################################

func serializeVerkleMultiproof* (dst: var VerkleMultiproofSerialized, src: var MultiProof) : bool =
  ##
  ## Multiproofs in Verkle have a format of 
  ## 
  ## 1) The queried Base Field where the Vector Commitment `opening` is created
  ## Consider this as the equivalent to the `Merkle Path` in usual Merkle Trees.
  ## 
  ## 2) The entire IPAProof which is exactly a 576 byte array, go through `serializeIPAProof` for the breakdown
  ## 
  ## The format of serialization is as:
  ## 
  ## Query Point (32 - byte array) .... IPAProof (544 - byte array) = 32 + 544 = 576 elements in the byte array
  ## 
  var res = false
  var ipa_bytes {.noInit.} : array[544, byte]
  var d_bytes {.noInit.} : array[32, byte]

  let stat = ipa_bytes.serializeVerkleIPAProof(src.IPAprv)
  doAssert stat == true, "IPA Serialization failed"

  let stat2 = d_bytes.serialize(src.D)
  doAssert stat2 == cttCodecEcc_Success, "Query point serialization failed"

  var idx : int = 0

  for i in 0 ..< 32:
    dst[idx] = d_bytes[i]
    idx = idx + 1

  discard d_bytes

  for i in 0 ..< 544:
    dst[idx] = ipa_bytes[i]
    idx = idx + 1

  discard ipa_bytes

  res = true
  return res

# ############################################################
#
#                 Multiproof Deserializer
#
# ############################################################
  
func deserializeVerkleMultiproof* (dst: var MultiProof, src: var VerkleMultiproofSerialized) :  bool =
  ##
  ## Multiproofs in Verkle have a format of 
  ## 
  ## 1) The queried Base Field where the Vector Commitment `opening` is created
  ## Consider this as the equivalent to the `Merkle Path` in usual Merkle Trees.
  ## 
  ## 2) The entire IPAProof which is exactly a 576 byte array, go through `serializeIPAProof` for the breakdown
  ## 
  ## The format of serialization is as:
  ## 
  ## Query Point (32 - byte array) .... IPAProof (544 - byte array) = 32 + 544 = 576 elements in the byte array
  ## 
  var res = false
  var ipa_bytes {.noInit.} : array[544, byte]
  var d_bytes {.noInit.} : array[32, byte]

  var idx : int = 0

  for i in 0 ..< 32:
    d_bytes[i] = src[idx]
    idx = idx + 1

  for i in 0 ..< 544:
    ipa_bytes[i] = src[idx]
    idx = idx + 1

  var ipa_prv {.noInit.} : MultiProof.IPAprv
  let stat1 = ipa_prv.deserializeVerkleIPAProof(ipa_bytes)
  doAssert stat1 == true, "IPA Deserialization Failure!"

  dst.IPAprv = ipa_prv
  discard ipa_prv

  var d_fp {.noInit.} : MultiProof.D
  let stat2 = d_fp.deserialize(d_bytes)
  doAssert stat2 == cttCodecEcc_Success, "Query Point Deserialization Failure!"

  dst.D = d_fp
  discard d_fp

  res = true
  return res
