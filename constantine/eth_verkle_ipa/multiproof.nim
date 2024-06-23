# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  tables,
  ./[ipa_prover, eth_verkle_constants, ipa_verifier],
  ../platforms/primitives,
  ../hashes,
  ../serialization/[
    codecs_banderwagon,
    codecs_status_codes,
  ],
  ../math/config/[type_ff, curves],
  ../math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
  ../math/elliptic/ec_twistededwards_projective,
  ../math/arithmetic,
  ../math/polynomials/polynomials,
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


func createMultiProof* [MultiProof] (res: var MultiProof, transcript: var CryptoHash, ipaSetting: IPASettings, Cs: openArray[EC_P], Fs: array[EthVerkleDomain, array[EthVerkleDomain, Fr[Banderwagon]]], Zs: openArray[int]) : bool =
  # createMultiProof creates a multi-proof for several polynomials in the evaluation form
  # The list of triplets are as follows: (C, Fs, Z) represents each polynomial commitment
  # and their evaluation in the domain, and the evaluating point respectively
  transcript.domain_separator("multiproof")

  for f in Fs:
    debug: doAssert f.len == EthVerkleDomain, "Polynomial length does not match with the EthVerkleDomain length!"

  debug: doAssert Cs.len == Fs.len, "Number of commitments is NOT same as number of Functions"

  debug: doAssert Cs.len == Zs.len, "Number of commitments is NOT same as the number of Points"

  var num_queries {.noInit.}: int
  num_queries = Cs.len

  for i in 0 ..< num_queries:
    transcript.absorb("C", Cs[i])
    var z {.noInit.}: Fr[Banderwagon]
    z.fromInt(Zs[i])
    transcript.absorb("z",z)

    # deducing the `y` value
    transcript.absorb("y", Fs[i][Zs[i]])

  var r {.noInit.} : Fr[Banderwagon]
  transcript.squeezeChallenge("r", r)

  var powersOfr {.noInit.} = newSeq[Fr[Banderwagon]](int(num_queries))
  powersOfr.computePowersOfElem(r, int(num_queries))

  # In order to compute g(x), we first compute the polynomials in lagrange form grouped by evaluation points
  # then we compute g(x), this is eventually limit the numbers of divisionOnDomain calls up to the domain size

  # Large array, need heap allocation. TODO: don't use Nim allocs.
  var groupedFs = new array[EthVerkleDomain, PolynomialEval[EthVerkleDomain, Fr[Banderwagon]]]
  for i in 0 ..< EthVerkleDomain:
    for j in 0 ..< EthVerkleDomain:
      groupedFs[i].evals[j].setZero()

  for i in 0 ..< num_queries:
    var z = Zs[i]
    var r {.noInit.}: Fr[Banderwagon]
    r = powersOfr[i]

    for j in 0 ..< EthVerkleDomain:
      var scaledEvals {.noInit.}: Fr[Banderwagon]
      scaledEvals.prod(r, Fs[i][j])
      groupedFs[z].evals[j] += scaledEvals

  var gx {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< EthVerkleDomain:
    gx[i].setZero()

  for i in 0'u32 ..< EthVerkleDomain:
    let check = groupedFs[i].evals[0].isZero()
    if check.bool() == true:
      continue

    var quotient {.noInit.}: PolynomialEval[EthVerkleDomain, Fr[Banderwagon]]
    ipaSetting.domain.getQuotientPolyInDomain(quotient, groupedFs[i], i)

    for j in  0 ..< EthVerkleDomain:
      gx[j] += quotient.evals[j]

  var D {.noInit.}: EC_P
  D.multiScalarMul_reference_vartime(gx, ipaSetting.crs)

  transcript.absorb("D", D)

  var t {.noInit.}: Fr[Banderwagon]
  transcript.squeezeChallenge("t", t)

  # Computing the denominator inverses only for referenced evaluation points.
  var denInv {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]

  var idxx = 0
  for i in 0 ..< EthVerkleDomain:
    let check = groupedFs[i].evals[0].isZero()
    if check.bool() == true:
      continue

    var z_fr {.noInit.}: Fr[Banderwagon]
    z_fr.fromInt(i)
    var deno {.noInit.}: Fr[Banderwagon]
    deno.diff(t, z_fr)

    denInv[idxx] = deno
    idxx = idxx + 1


  var denInv_prime {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  denInv_prime.batchInv_vartime(denInv)

  # Compute h(X) = g1(X)
  var hx {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  var denInvIdx = 0

  for i in 0 ..< EthVerkleDomain:
    if groupedFs[i].evals[0].isZero().bool():
      continue

    for k in 0 ..< EthVerkleDomain:
      var tmp {.noInit.}: Fr[Banderwagon]
      tmp.prod(groupedFs[i].evals[k], denInv_prime[denInvIdx])
      hx[k] += tmp

    denInvIdx += 1

  var hMinusg {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]

  for i in 0 ..< EthVerkleDomain:
    hMinusg[i].diff(hx[i],gx[i])

  var E {.noInit.}: EC_P

  E.multiScalarMul_reference_vartime(hx, ipaSetting.crs)
  transcript.absorb("E",E)

  var EMinusD {.noInit.}: EC_P
  EMinusD.diff(E,D)

  # TODO: for some result IPAProofDeprecated must be zero-init beforehand
  #       hence we need to investigate why initialization may be incomplete.
  var ipaProof: IPAProofDeprecated

  debugEcho "E-D: ", EMinusD.toHex()
  debugEcho "t: ", t.toHex()
  debugEcho "g[0] : ", gx[0].toHex()
  debugEcho "g1[0]: ", hx[0].toHex()
  debugEcho "g2[0]: ", hMinusg[0].toHex()
  debugEcho "g2[8]: ", hMinusg[8].toHex()
  debugEcho "g2[255]: ", hMinusg[255].toHex()
  debugEcho "------"
  block:
    var tr2 = transcript
    var t2: Fr[Banderwagon]
    tr2.squeezeChallenge("state", t2)
    debugEcho "transcript state: ", t2.toHex()
  debugEcho "------\n"

  let checks = ipaProof.createIPAProof(transcript, ipaSetting, EMinusD, hMinusg, t)
  if not checks:
    return false

  res.IPAprv = ipaProof
  res.D.affine(D)
  return true

# ############################################################
#
#                 Multiproof Verification
#
# ############################################################

func verifyMultiproof*[MultiProof](multiProof: var MultiProof, transcript : var CryptoHash, ipaSettings: IPASettings, Cs: openArray[EC_P], Ys: openArray[Fr[Banderwagon]], Zs: openArray[int]) : bool =
  # Multiproof verifier verifies the multiproof for several polynomials in the evaluation form
  # The list of triplets (C,Y,Z) represents each polynomial commitment, evaluation
  # result, and evaluation point in the domain
  transcript.domain_separator("multiproof")

  debug: doAssert Cs.len == Ys.len, "Number of commitments and the Number of output points don't match!"
  debug: doAssert Cs.len == Zs.len, "Number of commitments and the Number of input points don't match!"

  var num_queries = Cs.len

  for i in 0 ..< num_queries:
    transcript.absorb("C", Cs[i])
    var z {.noInit.} : Fr[Banderwagon]
    z.fromInt(Zs[i])

    transcript.absorb("z", z)
    transcript.absorb("y", Ys[i])

  var r {.noInit.}: Fr[Banderwagon]
  transcript.squeezeChallenge("r", r)

  var powersOfr {.noInit.} = newSeq[Fr[Banderwagon]](int(num_queries))
  powersOfr.computePowersOfElem(r, int(num_queries))

  transcript.absorb("D", multiProof.D)

  var t {.noInit.}: Fr[Banderwagon]
  transcript.squeezeChallenge("t", t)

  # Computing the polynomials in the Lagrange form grouped by evaluation point,
  # and the needed helper scalars
  var groupedEvals {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< EthVerkleDomain:
    groupedEvals[i].setZero()

  for i in 0 ..< num_queries:
    var z = Zs[i]
    var scaledEvals {.noInit.}: Fr[Banderwagon]
    scaledEvals.prod(powersOfr[i], Ys[i])

    groupedEvals[z] += scaledEvals

  # Calculating the helper scalar denominator, which is 1 / t - z_i
  var helperScalarDeno {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< EthVerkleDomain:
    helperScalarDeno[i].setZero()

  for i in 0 ..< EthVerkleDomain:
    var z {.noInit.}: Fr[Banderwagon]
    z.fromInt(i)
    helperScalarDeno[i].diff(t, z)

  var helperScalarDeno_prime {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  helperScalarDeno_prime.batchInv_vartime(helperScalarDeno)

  # Compute g_2(t) = SUMMATION (y_i * r^i) / (t - z_i) = SUMMATION (y_i * r) * helperScalarDeno
  var g2t {.noInit.}: Fr[Banderwagon]

  for i in 0 ..< EthVerkleDomain:
    if groupedEvals[i].isZero().bool() == true:
      continue

    var tmp {.noInit.}: Fr[Banderwagon]
    tmp.prod(groupedEvals[i], helperScalarDeno_prime[i])
    g2t += tmp


  # Compute E = SUMMATION C_i * (r^i /  t - z_i) = SUMMATION C_i * MSM_SCALARS
  var msmScalars {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< EthVerkleDomain:
    msmScalars[i].setZero()

  var Csnp {.noInit.}: array[EthVerkleDomain, EC_P]
  for i in 0 ..< EthVerkleDomain:
    Csnp[i].setInf()

  for i in 0 ..< Cs.len:
    Csnp[i] = Cs[i]
    msmScalars[i].prod(powersOfr[i], helperScalarDeno_prime[Zs[i]])

  var E {.noInit.}: EC_P

  var Csnp_aff {.noInit.}: array[EthVerkleDomain, EC_P_Aff]
  for i in 0 ..< Cs.len:
    Csnp_aff[i].affine(Csnp[i])

  E.multiScalarMul_reference_vartime(msmScalars, Csnp_aff)

  transcript.absorb("E", E)

  var EMinusD {.noInit.} : EC_P
  EMinusD.msub(E, multiProof.D)

  var EMinusDaff {.noInit.}: EC_P_Aff
  EMinusDaff.affine(EMinusD)

  var got {.noInit.}: EC_P
  return ipaSettings.checkIPAProof(transcript, got, EMinusDaff, multiProof.IPAprv, t, g2t)

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
  ## 2) The entire IPAProofDeprecated which is exactly a 576 byte array, go through `serializeIPAProof` for the breakdown
  ##
  ## The format of serialization is as:
  ##
  ## Query Point (32 - byte array) .... IPAProofDeprecated (544 - byte array) = 32 + 544 = 576 elements in the byte array
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
  ## 2) The entire IPAProofDeprecated which is exactly a 576 byte array, go through `serializeIPAProof` for the breakdown
  ##
  ## The format of serialization is as:
  ##
  ## Query Point (32 - byte array) .... IPAProofDeprecated (544 - byte array) = 32 + 544 = 576 elements in the byte array
  ##
  var res = false
  var ipa_bytes {.noInit.} : array[544, byte]
  var d_bytes {.noInit.} : array[32, byte]

  var idx : int = 0

  for i in 0 ..< 32:
    d_bytes[i] = src[idx]
    idx += 1

  for i in 0 ..< 544:
    ipa_bytes[i] = src[idx]
    idx += 1

  var ipa_prv {.noInit.} : MultiProof.IPAprv
  let stat1 = ipa_prv.deserializeVerkleIPAProof(ipa_bytes)
  doAssert stat1 == true, "IPA Deserialization Failure!"

  dst.IPAprv = ipa_prv

  var d_fp {.noInit.} : MultiProof.D
  let stat2 = d_fp.deserialize(d_bytes)
  doAssert stat2 == cttCodecEcc_Success, "Query Point Deserialization Failure!"

  dst.D = d_fp

  return res
