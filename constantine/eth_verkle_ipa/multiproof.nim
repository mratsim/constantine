# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  tables,
  ./[transcript_gen, common_utils, ipa_prover, barycentric_form, eth_verkle_constants, ipa_verifier],
  ../platforms/primitives,
  ../hashes,
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


func domainToFrElem* (res: var Fr, inp: uint8)=
  # The multiproof is a multi-proving system for several polynomials in the evaluation form
  # Converts the const VERKLE_DOMAIN 256 to Fr[Banderwagon]
  var x {.noInit.} : Fr
  var x_big {.noInit.}: matchingOrderBigInt(Banderwagon)
  x_big.fromUint(inp)
  x.fromBig(x_big)
  res = x

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
    

func createMultiProof* [MultiProof] (res: var MultiProof, transcript: var sha256, ipaSetting: IPASettings, Cs: openArray[EC_P], Fs: array[VERKLE_DOMAIN, array[VERKLE_DOMAIN, Fr[Banderwagon]]], Zs: openArray[uint8], precomp: PrecomputedWeights, basis: array[VERKLE_DOMAIN, EC_P]) : bool =
  # createMultiProof creates a multi-proof for several polynomials in the evaluation form
  # The list of triplets are as follows: (C, Fs, Z) represents each polynomial commitment
  # and their evaluation in the domain, and the evaluating point respectively
  var success {.noInit.} : bool
  transcript.domain_separator(asBytes"multiproof")

  for f in Fs:
    debug: debug: doAssert f.len == VERKLE_DOMAIN, "Polynomial length does not match with the VERKLE_DOMAIN length!"
    
  debug: debug: doAssert Cs.len == Fs.len, "Number of commitments is NOT same as number of Functions"

  debug: debug: doAssert Cs.len == Zs.len, "Number of commitments is NOT same as the number of Points"

  var num_queries {.noInit.} : int
  num_queries = Cs.len

  var Cs_prime {.noInit.} : array[VERKLE_DOMAIN, EC_P]
  for i in 0 ..< VERKLE_DOMAIN:
    Cs_prime[i] = Cs[i]

  for i in 0 ..< num_queries:
    transcript.pointAppend(asBytes"C", Cs_prime[i])
    var z {.noInit.} : Fr[Banderwagon]
    z.domainToFrElem(Zs[i])
    transcript.scalarAppend(asBytes"z",z.toBig())

    # deducing the `y` value

    var f = Fs[i]

    var y = f[int(Zs[i])]

    transcript.scalarAppend(asBytes"y", y.toBig())

  var r {.noInit.} : matchingOrderBigInt(Banderwagon)
  r.generateChallengeScalar(transcript,asBytes"r")

  var r_fr {.noInit.}: Fr[Banderwagon]
  r_fr.fromBig(r)

  var powersOfr {.noInit.}: array[VERKLE_DOMAIN,Fr[Banderwagon]]
  powersOfr.computePowersOfElem(r_fr, int(num_queries))

  # In order to compute g(x), we first compute the polynomials in lagrange form grouped by evaluation points
  # then we compute g(x), this is eventually limit the numbers of divisionOnDomain calls up to the domain size 

  var groupedFs: array[VERKLE_DOMAIN, array[VERKLE_DOMAIN, Fr[Banderwagon]]]
  # Initialize the array with zeros
  for i in 0 ..< VERKLE_DOMAIN:
    for j in 0 ..< VERKLE_DOMAIN:
      groupedFs[i][j].setZero()


  for i in 0 ..< num_queries:
    var z = Zs[i]
    
    debug: doAssert not(groupedFs[z].len == 0), "Length should not be 0!"

    var r {.noInit.}: Fr[Banderwagon]
    r = powersOfr[i]

    for j in 0 ..< VERKLE_DOMAIN:
      var scaledEvals {.noInit.}: Fr[Banderwagon]
      scaledEvals.prod(r, Fs[i][j])
      groupedFs[z][j].sum(groupedFs[z][j], scaledEvals)
    

  var gx : array[VERKLE_DOMAIN, Fr[Banderwagon]]

  for idx in 0 ..< VERKLE_DOMAIN:
    if groupedFs[idx].len == 0:
      continue

    var quotient: array[VERKLE_DOMAIN,Fr[Banderwagon]]
    var passer : int
    passer = idx
    quotient.divisionOnDomain(precomp, passer, groupedFs[idx])

    for j in  0 ..< VERKLE_DOMAIN:
      gx[j] += quotient[j]
    
  var D: EC_P
  D.pedersen_commit_varbasis(basis,basis.len, gx, gx.len)

  transcript.pointAppend(asBytes"D", D)

  var t {.noInit.}: matchingOrderBigInt(Banderwagon)
  t.generateChallengeScalar(transcript,asBytes"t")

  var t_fr {.noInit.}: Fr[Banderwagon]
  t_fr.fromBig(t)

  # Computing the denominator inverses only for referenced evaluation points.
  var denInv {.noInit.}: array[VERKLE_DOMAIN, Fr[Banderwagon]]
  for i in 0 ..< VERKLE_DOMAIN:
    denInv[i].setZero()

  for z in 0 ..< VERKLE_DOMAIN:
    if groupedFs[z].len == 0:
      continue

    var z_fr {.noInit.} : Fr[Banderwagon]
    z_fr.domainToFrElem(uint8(z))
    var deno {.noInit.}: Fr[Banderwagon]

    deno.diff(t_fr,z_fr)
    var idxx = 0
    denInv[idxx] = deno
    idxx = idxx + 1


  var denInv_prime {.noInit.} : array[VERKLE_DOMAIN, Fr[Banderwagon]]
  denInv_prime.batchInvert(denInv)

  #Compute h(X) = g1(X)
  var hx {.noInit.}: array[VERKLE_DOMAIN, Fr[Banderwagon]]
  var denInvIdx = 0

  for i in 0 ..< VERKLE_DOMAIN:
    if groupedFs[i].len == 0:
      continue

    for k in 0 ..< VERKLE_DOMAIN:
      var tmp {.noInit.}: Fr[Banderwagon]
      tmp.prod(groupedFs[i][k], denInv[denInvIdx])
      hx[k].sum(hx[k], tmp)

    denInvIdx = denInvIdx + 1

  var hMinusg {.noInit.}: array[VERKLE_DOMAIN, Fr[Banderwagon]]

  for i in 0 ..< VERKLE_DOMAIN:
    hMinusg[i].diff(hx[i],gx[i])

  var E: EC_P

  E.pedersen_commit_varbasis(basis,basis.len, hx, hx.len)
  transcript.pointAppend(asBytes"E",E)

  var EMinusD: EC_P

  EMinusD.diff(E,D)

  var ipaProof: IPAProof

  var checks: bool
  checks = ipaProof.createIPAProof(transcript, ipaSetting, EMinusD, hMinusg, t_fr)

  debug: doAssert checks == true, "Could not compute IPA Proof!"

  res.IPAprv = ipaProof
  res.D = D
  success = true

  return success

# ############################################################
#
#                 Multiproof Verification
#
# ############################################################
    

func verifyMultiproof*(multiProof: var MultiProof, transcript : var sha256, ipaSettings: IPASettings, Cs: openArray[EC_P], Ys: openArray[Fr[Banderwagon]], Zs: openArray[uint8]) : bool =
  # Multiproof verifier verifies the multiproof for several polynomials in the evaluation form
  # The list of triplets (C,Y,Z) represents each polynomial commitment, evaluation
  # result, and evaluation point in the domain 
  var res {.noInit.} : bool
  transcript.domain_separator(asBytes"multiproof")

  debug: debug: doAssert Cs.len == Ys.len, "Number of commitments and the Number of output points don't match!"

  debug: debug: doAssert Cs.len == Zs.len, "Number of commitments and the Number of input points don't match!"

  var num_queries = Cs.len

  var checker {.noInit.}: bool
  checker = num_queries == 0

  debug: debug: doAssert num_queries == 0, "Number of queries is zero!"

  for i in 0 ..< num_queries:
    transcript.pointAppend(asBytes"C", Cs[i])

    var z {.noInit.} : Fr[Banderwagon]
    z.domainToFrElem(Zs[i])

    transcript.scalarAppend(asBytes"z", z.toBig())
    transcript.scalarAppend(asBytes"y", Ys[i].toBig())

  var r {.noInit.}: matchingOrderBigInt(Banderwagon)
  r.generateChallengeScalar(transcript,asBytes"r")

  var r_fr {.noInit.}: Fr[Banderwagon]
  r_fr.fromBig(r)

  var powersOfr {.noInit.}: array[VERKLE_DOMAIN, Fr[Banderwagon]]
  powersOfr.computePowersOfElem(r_fr, int(num_queries))

  transcript.pointAppend(asBytes"D", multiProof.D)

  var t {.noInit.}: matchingOrderBigInt(Banderwagon)
  t.generateChallengeScalar(transcript, asBytes"t")

  var t_fr {.noInit.}: Fr[Banderwagon]
  t_fr.fromBig(r)

  # Computing the polynomials in the Lagrange form grouped by evaluation point, 
  # and the needed helper scalars
  var groupedEvals {.noInit.}: array[VERKLE_DOMAIN, Fr[Banderwagon]]

  for i in 0 ..< num_queries:

    var z {.noInit.}: uint8
    z = Zs[i]

    var r {.noInit.} : Fr[Banderwagon]
    r = powersOfr[i]

    var scaledEvals {.noInit.}: Fr[Banderwagon]
    scaledEvals.prod(r, Ys[i])

    groupedEvals[z].sum(groupedEvals[z], scaledEvals)

    #Calculating the helper scalar denominator, which is 1 / t - z_i
    var helperScalarDeno {.noInit.} : array[VERKLE_DOMAIN, Fr[Banderwagon]]

    for i in 0 ..< VERKLE_DOMAIN:
      var z {.noInit.}: Fr[Banderwagon]
      z.domainToFrElem(uint8(i))

      helperScalarDeno[i].diff(t_fr, z)

    var helperScalarDeno_prime: array[VERKLE_DOMAIN, Fr[Banderwagon]]
    helperScalarDeno_prime.batchInvert(helperScalarDeno)

    # Compute g_2(t) = SUMMATION (y_i * r^i) / (t - z_i) = SUMMATION (y_i * r) * helperScalarDeno
    var g2t {.noInit.} : Fr[Banderwagon]
    g2t.setZero()

    for i in 0 ..< VERKLE_DOMAIN:
      var stat = groupedEvals[i].isZero()
      if stat.bool() == true:
        continue

      var tmp {.noInit.}: Fr[Banderwagon]
      tmp.prod(groupedEvals[i], helperScalarDeno_prime[i])
      g2t += tmp

    
    # Compute E = SUMMATION C_i * (r^i /  t - z_i) = SUMMATION C_i * MSM_SCALARS
    var msmScalars {.noInit.}: array[VERKLE_DOMAIN, Fr[Banderwagon]]

    var Csnp {.noInit.}: array[VERKLE_DOMAIN, EC_P]

    for i in 0 ..< VERKLE_DOMAIN:
      Csnp[i] = Cs[i]
      msmScalars[i].prod(powersOfr[i], helperScalarDeno_prime[Zs[i]])
    
    var E {.noInit.}: EC_P

    var Csnp_aff : array[VERKLE_DOMAIN, EC_P_Aff]
    for i in 0 ..< VERKLE_DOMAIN:
      Csnp_aff[i].affine(Csnp[i])

    var msmScalars_big: array[VERKLE_DOMAIN, matchingOrderBigInt(Banderwagon)]

    for i in 0 ..< VERKLE_DOMAIN:
      msmScalars_big[i] = msmScalars[i].toBig()
    
    E.multiScalarMul_reference_vartime(msmScalars_big, Csnp_aff)

    transcript.pointAppend(asBytes"E", E)

    var EMinusD {.noInit.} : EC_P
    EMinusD.diff(E, multiProof.D)

    res = ipaSettings.checkIPAProof(transcript, EMinusD, multiProof.IPAprv, t_fr, g2t)
    return res
