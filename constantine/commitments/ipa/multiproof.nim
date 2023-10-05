# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./[transcript_gen, common_utils, ipa_prover, barycentric_form],
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


# ############################################################
#
#                   Mutliproof System
#
# ############################################################

# The multiproof is a multi-proving system for several polynomials in the evaluation form

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = ECP_TwEdwards_Prj[Fr[Banderwagon]]

type 
    MultiProof* = object
     IPAprv: IPAProof
     D: EC_P

const DOMAIN = 256

# Converts the const DOMAIN 256 to ECP_TwEdwards_Prj[Fr[Banderwagon]]
func domainToFrElem* [EC_P_Fr] (res: var EC_P_Fr, inp: uint8)=
    var x {.noInit.} : EC_P_Fr
    x.setUint(uint64(inp))
    res = x

# Computes the powers of an ECP_TwEdwards_Prj[Fr[Banderwagon]] element
func computePowersOfElem [FF] (res: var openArray[FF], x: FF, degree: SomeUnsignedInt)= 
    res[0].setOne()

    for i in 0..degree:
        res[i].prod(res[i-1], x)
    
# createMultiProof creates a multi-proof for several polynomials in the evaluation form
# The list of triplets are as follows : (C, Fs, Z) represents each polynomial commitment
# and their evalutation in the domain, and the evaluating point respectively
func createMultiProof* [MultiProof] (res: var MultiProof, transcript: Transcript, ipaSetting: IPASettings, Cs: openArray[EC_P], Fs: openArray[openArray[EC_P_Fr]], Zs: openArray[uint8])=
    transcript.domain_separator(asBytes"multiproof")

    for f in Fs:
        debug: doAssert f.len == DOMAIN, "Polynomial length does not match with the DOMAIN length!"
    
    debug: doAssert Cs.len == Fs.len, "Number of commitments is NOT same as number of Functions"

    debug: doAssert Cs.len == Zs.len, "Number of commitments is NOT same as number of Points"

    var num_queries {.noInit.} : SomeUnsignedInt
    num_queries = Cs.len 

    #TODO: add BatchNormalize() for Banderwagon EC_P

    for i in 0..num_queries:
        transcript.pointAppend(Cs[i],asBytes"C")
        var z {.noInit.} : EC_P_Fr
        z.domainToFrElem(Zs[i])
        transcript.scalarAppend(z, asBytes"z")

        # deducing the `y` value

        let f = Fs[i]
        let y = f[Zs[i]]

        transcript.scalarAppend(y, asBytes"y")

    var r {.noInit.} : EC_P_Fr
    r = transcript.generateChallengeScalar(asBytes"r")

    var powersOfr {.noInit.}: openArray[EC_P_Fr]
    powersOfr.computePowersOfElem(r, num_queries)

    # Inorder to compute g(x), we first compute the polynomials in lagrange form grouped by evaluation points
    # then we compute g(x), this is eventually limit the numbers of divisionOnDomain calls up to the domain size 

    var groupedFs {.noInit.}: array[DOMAIN, openArray[EC_P_Fr]]

    for i in 0..num_queries:
        let z = Zs[i]
        
        if groupedFs[z].len == 0:
            groupedFs[z]: array[DOMAIN, EC_P_Fr]
        
        var r {.noInit.}: EC_P_Fr
        r = powersOfr[i]

        for j in 0..DOMAIN:
            var scaledEvals {.noInit.}: EC_P_Fr
            scaledEvals.prod(r, Fs[i][j])
            groupedFs[z][j].add(groupedFs[z][j], scaledEvals)
        
    
    var gx {.noInit.}: array[DOMAIN, EC_P_Fr]

    for idx, f in groupedFs:

        if f.len == 0:
            continue

        var quotient {.noInit.} : openArray[EC_P_Fr]
        quotient = ipaSetting.PrecomputedWeights.divisionOnDomain(uint8(idx), f)

        for j in  0..DOMAIN:
            gx[j] += quotient[j]
        
    var D {.noInit.}: EC_P
    D.pedersen_commit_single(gx)

    transcript.pointAppend(D, asBytes"D")

    var t {.noInit.}: EC_P_Fr
    t = transcript.generateChallengeScalar(asBytes"t")

    # Computing the denominator inverses only for referenced evaluation points.
    var denInv {.noInit.}: array[DOMAIN, EC_P_Fr]
    denInv.setZero()

    for z,f in groupedFs:
        if f.len == 0:
            continue

        z.domainToFrElem(uint8(z))
        var deno {.noInit.}: EC_P_Fr

        deno.diff(t,z)
        #TODO: fr element append() ?
        
    denInv.computeZMinusXi(denInv)

    #Compute h(X) = g1(X)
    var hx {.noInit.}: array[DOMAIN, EC_P_Fr]
    let denInvIdx = 0

    for _,f in groupedFs:
        if f.len == 0:
            continue

        for k in 0..DOMAIN:
            var tmp {.noInit.}: EC_P_Fr
            tmp.prod(f[k], denInv[denInvIdx])
            hx[k].add(hx[k], tmp)

        denInvIdx = denInvIdx + 1

    var hMinusg {.noInit.}: array[DOMAIN, EC_P_Fr]

    for i in 0..DOMAIN:
        hMinusg.diff(hx[i],gx[i])

    var E {.noInit.}: EC_P
    #TODO: replace pedersen_commit_single with a multiple polynomials commit function
    E.pedersen_commit_single(hx)
    transcript.pointAppend(E, asBytes"E")

    var EMinusD {.noInit.}: EC_P

    EMinusD.diff(E,D)

    var ipaProof {.noInit.} : IPAProof
    var checks {.noInit.}: bool

    checks = ipaProof.createIPAProof(transcript, ipaSetting, EMinusD, hMinusg, t)

    debug: doAssert checks == 1, "Could not compute IPA Proof!"

    res.IPAprv = ipaProof
    res.D = D

# Mutliproof verifier verifies the multiproof for several polynomials in the evaluation form
# The list of triplets (C,Y, Z) represents each polynomial commitment, evaluation
# result, and evaluation point in the domain 
func verifyMultiproof* [bool] (res: var bool, transcript : Transcript, ipaSettings: IPASettings, proof: MultiProof, Cs: openArray[EC_P], Ys: openArray[EC_P_Fr], Zs: openArray[uint8])=
    transcript.domain_separator(asBytes"multiproof")

    debug: doAssert Cs.len == Ys.len, "Number of commitments and the Number of output points don't match!"

    debug: doAssert Cs.len == Zs.len, "Number of commitments and the Number of input points don't match!"

    let num_queries = Cs.len

    var checker {.noInit.}: bool
    checker = num_queries == 0

    debug: doAssert num_queries == 0, "Number of queries is zero!"

    for i in 0..num_queries:
        transcript.pointAppend(Cs[i], asBytes"C")

        var z {.noInit.} : EC_P_Fr
        z.domainToFrElem(Zs[i])

        transcript.scalarAppend(z, asBytes"z")
        transcript.scalarAppend(Ys[i], asBytes"y")

    var r {.noInit.}: EC_P_Fr
    r = transcript.generateChallengeScalar(asBytes"r")

    var powersOfr {.noInit.}: openArray[EC_P_Fr]
    powersOfr.computePowersOfElem(r, num_queries)

    transcript.pointAppend(proof.D, asBytes"D")

    var t {.noInit.}: EC_P_Fr
    t = transcript.generateChallengeScalar(asBytes"t")

    # Computing the polynomials in the Lagrange form grouped by evaluation point, 
    # and the needed helper scalars
    var groupedEvals {.noInit.}: array[DOMAIN, EC_P_Fr]

    for i in 0..num_queries:

        var z {.noInit.}: uint8
        z = Zs[i]

        var r {.noInit.} : openArray[EC_P_Fr]
        r = powersOfr[i]

        var scaledEvals {.noInit.}: EC_P_Fr
        scaledEvals.prod(r, Ys[i])

        groupedEvals[z] += scaledEvals

        #Calculating the helper scalar denominatoer, which is 1 / t - z_i
        var helperScalarDeno {.noInit.} : array[DOMAIN, EC_P_Fr]

        for i in 0..DOMAIN:
            var z {.noInit.}: EC_P_Fr
            z.domainToFrElem(uint8(i))

            helperScalarDeno[i].diff(t, z)

        helperScalarDeno.computeZMinusXi(helperScalarDeno)

        # Compute g_2(t) = SUMMATION (y_i * r^i) / (t - z_i) = SUMMATION (y_i * r) * helperScalarDeno
        var g2t {.noInit.} : EC_P_Fr
        g2t.setZero()

        for i in 0..DOMAIN:
            if groupedEvals[i].isZero():
                continue

            var tmp {.noInit.}: EC_P_Fr
            tmp.prod(groupedEvals[i], helperScalarDeno[i])
            g2t += tmp

        
        # Compute E = SUMMATION C_i * (r^i /  t - z_i) = SUMMATION C_i * MSM_SCALARS
        var msmScalars {.noInit.}: array[Cs.len, EC_P_Fr]

        var Csnp {.noInit.}: array[Cs.len, EC_P]

        for i in 0..Cs.len:
            Csnp[i] = Cs[i]

            msmScalars[i].prod(powersOfr[i], helperScalarDeno[Zs[i]])
        
        var E {.noInit.}: EC_P

        var checks2 {.noInit.}: bool
        checks2 = E.multiScalarMul_reference_vartime_Prj(Csnp, msmScalars.toBig())

        debug: doAssert checks2 == 1, "Could not compute E!"

        transcript.pointAppend(E, asBytes"E")

        var EMinusD {.noInit.} : EC_P
        EMinusD.diff(E, proof.D)

        res.checkIPAProof(transcript, ipaSetting, EMinusD, proof.IPAprv, t, g2t)


func mutliProofEquality* [bool] (res: var bool, mp: MultiProof, other: MultiProof)=
    if not(mp.IPAprv == other.IPAprv):
        res = false
    
    res = mp.D == other.Ds

            

