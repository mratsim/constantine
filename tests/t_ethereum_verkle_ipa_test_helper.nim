# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ../constantine/eth_verkle_ipa/[multiproof, barycentric_form, eth_verkle_constants],
    ../constantine/math/config/[type_ff, curves],
    ../constantine/math/elliptic/[
     ec_twistededwards_affine,
     ec_twistededwards_projective
      ],
    ../constantine/serialization/[
      codecs_status_codes,
      codecs_banderwagon,
      codecs
       ],
    ../constantine/math/arithmetic

# ############################################################
#
#       All the helper functions required for testing
#
# ############################################################

func ipaEvaluate* [Fr] (res: var Fr, poly: openArray[Fr], point: Fr,  n: static int) = 
    var powers {.noInit.}: array[n,Fr]
    powers.computePowersOfElem(point, poly.len)

    res.setZero()

    for i in 0..<poly.len:
        var tmp: EC_P_Fr
        tmp.prod(powers[i], poly[i])
        res.sum(res,tmp)

    res.setZero()

    for i in 0..<poly.len:
        var tmp {.noInit.}: EC_P_Fr
        tmp.prod(powers[i], poly[i])
        res.sum(res,tmp)

func truncate* [Fr] (res: var openArray[Fr], s: openArray[Fr], to: int, n: static int)=
    for i in 0..<to:
        res[i] = s[i]

func interpolate* [Fr] (res: var openArray[Fr], points: openArray[Coord], n: static int) =
    
    var one : EC_P_Fr
    one.setOne()

    var zero  : EC_P_Fr
    zero.setZero()

    var max_degree_plus_one = points.len

    doAssert (max_degree_plus_one >= 2).bool() == true, "Should be interpolating for degree >= 1!"

    for k in 0..<points.len:
        var point: Coord
        point = points[k]

        var x_k : EC_P_Fr 
        x_k = point.x
        var y_k  : EC_P_Fr 
        y_k = point.y

        var contribution : array[n,EC_P_Fr]
        var denominator : EC_P_Fr
        denominator.setOne()

        var max_contribution_degree : int= 0

        for j in 0..<points.len:
            var point : Coord 
            point = points[j]
            var x_j : EC_P_Fr 
            x_j = point.x

            if j != k:
                var differ = x_k
                differ.diff(differ, x_j)

                denominator.prod(denominator,differ)

                if max_contribution_degree == 0:

                    max_contribution_degree = 1
                    contribution[0].diff(contribution[0],x_j)
                    contribution[1].sum(contribution[1],one)

                else:

                    var mul_by_minus_x_j : array[n,EC_P_Fr]
                    for el in 0..<contribution.len:
                        var tmp : EC_P_Fr = contribution[el]
                        tmp.prod(tmp,x_j)
                        tmp.diff(zero,tmp)
                        mul_by_minus_x_j[el] = tmp

                    for i in 1..<contribution.len:
                        contribution[i] = contribution[i-1]
                    
                    contribution[0] = zero
                    # contribution.truncate(contribution, max_degree_plus_one, n)

                    doAssert max_degree_plus_one == mul_by_minus_x_j.len == true, "Malformed mul_by_minus_x_j!"

                    for i in 0..<contribution.len:
                        var other = mul_by_minus_x_j[i]
                        contribution[i].sum(contribution[i],other) 
            
        denominator.inv(denominator)
        doAssert not(denominator.isZero().bool()) == true, "Denominator should not be zero!"

        for i in 0..<contribution.len:
            var tmp : EC_P_Fr 
            tmp = contribution[i]
            tmp.prod(tmp,denominator)
            tmp.prod(tmp,y_k)
            res[i].sum(res[i], tmp)

        
#Initiating evaluation points z in the FiniteField (253)
func setEval* [Fr] (res: var Fr, x : Fr)=

    var tmp_a {.noInit.} : Fr

    var one {.noInit.}: Fr
    one.setOne()

    tmp_a.diff(x, one)

    var tmp_b : Fr
    tmp_b.sum(x, one)

    var tmp_c : Fr = one

    for i in 0..<253:
        tmp_c.prod(tmp_c,x) 

    res.prod(tmp_a, tmp_b)
    res.prod(res,tmp_c)

#Evaluating the point z outside of VerkleDomain, here the VerkleDomain is 0-256, whereas the FieldSize is
#everywhere outside of it which is upto a 253 bit number, or 2²⁵³.
func evalOutsideDomain* [Fr] (res: var Fr, precomp: PrecomputedWeights, f: openArray[Fr], point: Fr)=

    var pointMinusDomain: array[VerkleDomain, Fr]
    for i in 0..<VerkleDomain:

        var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
        i_bg.setUint(uint64(i))
        var i_fr {.noInit.} : Fr
        i_fr.fromBig(i_bg)

        pointMinusDomain[i].diff(point, i_fr)
        pointMinusDomain[i].inv(pointMinusDomain[i])

    var summand: Fr
    summand.setZero()

    for x_i in 0..<pointMinusDomain.len:
        var weight: Fr
        weight.getBarycentricInverseWeight(precomp,x_i)
        var term: Fr
        term.prod(weight, f[x_i])
        term.prod(term, pointMinusDomain[x_i])

        summand.sum(summand,term)

    res.setOne()

    for i in 0..<VerkleDomain:

        var i_bg: matchingOrderBigInt(Banderwagon)
        i_bg.setUint(uint64(i))
        var i_fr : Fr
        i_fr.fromBig(i_bg)

        var tmp : Fr
        tmp.diff(point, i_fr)
        res.prod(res, tmp)

    res.prod(res,summand)

func testPoly256* [Fr] (res: var openArray[Fr], polynomialUint: openArray[uint64])=

    var n = polynomialUint.len
    doAssert (polynomialUint.len <= 256) == true, "Cannot exceed 256 coeffs!"

    for i in 0..<n:
        var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
        i_bg.setUint(uint64(polynomialUint[i]))
        res[i].fromBig(i_bg)
    
    var pad = 256 - n
    for i in n..<pad:
        res[i].setZero()

func isPointEqHex*(point: EC_P, expected: string): bool {.discardable.} =

    var point_bytes {.noInit.} : Bytes
    if point_bytes.serialize(point) == cttCodecEcc_Success:
        doAssert (point_bytes.toHex() == expected).bool() == true, "Point does not equal to the expected hex value!"

func isScalarEqHex*(scalar: matchingOrderBigInt(Banderwagon), expected: string) : bool {.discardable.} =

    var scalar_bytes {.noInit.} : Bytes
    if scalar_bytes.serialize_scalar(scalar) == cttCodecScalar_Success:
        doAssert (scalar_bytes.toHex() == expected).bool() == true, "Scalar does not equal to the expected hex value!"

func getDegreeOfPoly*(res: var int, p: openArray[EC_P_Fr]) = 
    for d in countdown(p.len - 1, 0):
        if not(p[d].isZero().bool()):
            res = d
    
        else:
            res = -1





    
    












