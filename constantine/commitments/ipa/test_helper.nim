# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ./[multiproof, barycentric_form],
    ./helper_types,
    ../../../constantine/math/config/[type_ff, curves],
    ../../../constantine/math/elliptic/[
     ec_twistededwards_affine,
     ec_twistededwards_projective
      ],
    ../../../constantine/math/io/io_fields,
    ../../../constantine/serialization/[
      codecs_status_codes,
      codecs_banderwagon,
      codecs
       ],
    ../../../constantine/math/arithmetic

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 

func evaluate* [EC_P_Fr] (point: var EC_P_Fr, poly: openArray[EC_P_Fr], n: static int) = 
    var powers: array[n,EC_P_Fr]
    powers.computePowersOfElem(point, poly.len)

    var total {.noInit.} : EC_P_Fr
    total.setZero()

    for i in 0..<poly.len:
        var tmp : EC_P_Fr
        tmp.prod(powers[i], poly[i])
        total += tmp

    point = total

func truncate* [EC_P_Fr] (res: var openArray[EC_P_Fr], s: openArray[EC_P_Fr], to: int, n: static int)=
    for i in 0..<to:
        res[i] = s[i]

func interpolate* [EC_P_Fr] (res: var openArray[EC_P_Fr], points: openArray[Coord], n: static int) =
    
    var one {.noInit.} : EC_P_Fr
    one.setOne()

    var zero {.noInit.} : EC_P_Fr
    zero.setZero()

    var max_degree_plus_one = points.len

    # doAssert (max_degree_plus_one < 2).bool() == true, "Should be interpolating for degree >= 1!"

    if (max_degree_plus_one < 2):
    

        for k in 0..<points.len:

            var point: Coord
            point = points[k]

            var x_k : EC_P_Fr 
            x_k = point.x
            var y_k  : EC_P_Fr 
            y_k = point.y

            var contribution : array[n,EC_P_Fr]
            var denominator {.noInit.}: EC_P_Fr
            denominator.setOne()


            var max_contribution_degree = 0

            for j in 0..<points.len:

                var point {.noInit.}: Coord 
                point = points[j]
                var x_j {.noInit.} : EC_P_Fr 
                x_j = point.x

                if j == k:
                    continue

                var differ = x_k
                differ.diff(differ, x_j)

                denominator.prod(denominator,differ)

                if max_contribution_degree == 0:

                    max_contribution_degree = 1
                    contribution[0] -= x_j
                    contribution[1] += one  

                else:

                    var mul_by_minus_x_j : array[n,EC_P_Fr]
                    for el in contribution:
                        var tmp : EC_P_Fr = el
                        tmp.prod(tmp,x_j)
                        tmp.diff(zero,tmp)
                        var idx = 0
                        mul_by_minus_x_j[idx] = tmp
                        idx = idx + 1

                    contribution[0] = zero
                    contribution.truncate(contribution, max_degree_plus_one, n)

                    doAssert not(max_degree_plus_one == mul_by_minus_x_j.len), "Malformed mul_by_minus_x_j!"

                    for i in 0..<contribution.len:
                        var other = mul_by_minus_x_j[i]
                        contribution[i] += other
                    
                
            
            denominator.inv_vartime(denominator)
            doAssert not(denominator.isZero().bool() == true), "Denominator should not be zero!"

            for i in 0..<contribution.len:
                var tmp = contribution[i]
                tmp.prod(tmp,contribution[i])
                tmp.prod(tmp,y_k)
                res[i].sum(res[i], tmp)

        
#Initiating evaluation points z in the FiniteField (253)
func setEval* [EC_P_Fr] (res: var EC_P_Fr, x : EC_P_Fr)=

    var tmp_a {.noInit.} : EC_P_Fr

    var one {.noInit.}: EC_P_Fr
    one.setOne()

    tmp_a.diff(x, one)

    var tmp_b : EC_P_Fr
    tmp_b.sum(x, one)

    var tmp_c : EC_P_Fr = one

    for i in 0..<253:
        tmp_c.prod(tmp_c,x) 

    res.prod(tmp_a, tmp_b)
    res *= tmp_c

#Evaluating the point z outside of DOMAIN, here the DOMAIN is 0-256, whereas the FieldSize is
#everywhere outside of it which is upto a 253 bit number, or 2²⁵³.
func evalOutsideDomain* [EC_P_Fr] (res: var EC_P_Fr, precomp: PrecomputedWeights, f: openArray[EC_P_Fr], point: EC_P_Fr)=

    var pointMinusDomain {.noInit.} : array[DOMAIN, EC_P_Fr]
    for i in 0..<DOMAIN:

        var i_fr {.noInit.} : EC_P_Fr
        i_fr.setUint(uint64(i))

        pointMinusDomain[i].diff(point, i_fr)
        pointMinusDomain[i].inv(pointMinusDomain[i])

    var summand {.noInit.}: EC_P_Fr
    summand.setZero()

    for x_i in 0..<pointMinusDomain.len:
        var weight {.noInit.} : EC_P_Fr
        weight.getBarycentricInverseWeight(x_i)

        var term: EC_P_Fr
        term.prod(weight, f[x_i])
        term.prod(term, pointMinusDomain[x_i])

        summand += term

    res.setOne()

    for i in 0..<DOMAIN:

        var i_fr {.noInit.}: EC_P_Fr
        i_fr.setUint(uint64(i))

        var tmp {.noInit.}: EC_P_Fr
        tmp.diff(point, i_fr)

        res *= summand

func testPoly256* [EC_P_Fr] (res: var array[DOMAIN,EC_P_Fr], polynomialUint: openArray[uint])=

    var n = polynomialUint.len
    doAssert (polynomialUint.len > 256).bool() == true, "Cannot exceed 256 coeffs!"

    for i in 0..<n:
        var bign {.noInit}: BigInt
        bign.setUint(polynomialUint[i])
        res[i].fromBig(bign)
    
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

func getDegreeOfPoly* [int] (res: var int, p: openArray[EC_P_Fr]) = 
    for d in countdown(p.len - 1, 0):
        if not(p[d].isZero().bool()):
            res = d
    
        else:
            res = -1

# func polynomialLongDivision

proc polynomialLongDivision* (nn, dd: var seq[EC_P_Fr]) : auto  =

    var degdd {.noInit.} : int
    degdd.getDegreeOfPoly(dd)

    var result: tuple[q,r : seq[EC_P_Fr], ok: bool]

    if degdd < 0:
        return(newSeq[EC_P_Fr](), newSeq[EC_P_Fr](), false)

    nn.setLen(nn.len + result.r.len)
    for i in 0..<result.r.len:
        nn[nn.len - result.r.len + i] = result.r[i]
    
    var degnn {.noInit.} : int 
    if degnn > degdd:
        result.q = newSeq[EC_P_Fr](degnn - degdd + 1)
        while degnn >= degdd:
            var d = newSeq[EC_P_Fr](degnn + 1)
            d[(degnn - degdd)..<d.len] = dd
            var tmp {.noInit.}: EC_P_Fr
            result.q[degnn - degdd] = tmp

            for i in 0..<d.len:
                d[i].prod(d[i], result.q[degnn - degdd])
                nn[i].diff(nn[i], d[i])

            
    return result
            



    
    












