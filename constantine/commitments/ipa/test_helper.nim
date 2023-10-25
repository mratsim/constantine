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

func evaluate* [EC_P_Fr] (res: var EC_P_Fr, poly: openArray[EC_P_Fr], point: EC_P_Fr,  n: static int) = 
    var powers {.noInit.}: array[n,EC_P_Fr]
    powers.computePowersOfElem(point, poly.len)

    res.setZero()

    for i in 0..<poly.len:
        var tmp: EC_P_Fr
        tmp.prod(powers[i], poly[i])
        res.sum(res,tmp)

func evaluateSeq* [EC_P_Fr] (res: var EC_P_Fr, poly: openArray[EC_P_Fr], point: EC_P_Fr) = 
    var powers : seq[EC_P_Fr]
    powers.computePowersOfElem(point, poly.len)

    res.setZero()

    for i in 0..<poly.len:
        var tmp {.noInit.}: EC_P_Fr
        tmp.prod(powers[i], poly[i])
        res.sum(res,tmp)

func truncate* [EC_P_Fr] (res: var openArray[EC_P_Fr], s: openArray[EC_P_Fr], to: int, n: static int)=
    for i in 0..<to:
        res[i] = s[i]

func interpolate* [EC_P_Fr] (res: var openArray[EC_P_Fr], points: openArray[Coord], n: static int) =
    
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
    res.prod(res,tmp_c)

#Evaluating the point z outside of DOMAIN, here the DOMAIN is 0-256, whereas the FieldSize is
#everywhere outside of it which is upto a 253 bit number, or 2²⁵³.
func evalOutsideDomain* [EC_P_Fr] (res: var EC_P_Fr, precomp: PrecomputedWeights, f: openArray[EC_P_Fr], point: EC_P_Fr)=

    var pointMinusDomain {.noInit.} : array[DOMAIN, EC_P_Fr]
    for i in 0..<DOMAIN:

        var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
        i_bg.setUint(uint64(i))
        var i_fr {.noInit.} : EC_P_Fr
        i_fr.fromBig(i_bg)

        pointMinusDomain[i].diff(point, i_fr)
        pointMinusDomain[i].inv(pointMinusDomain[i])

    var summand: EC_P_Fr
    summand.setZero()

    for x_i in 0..<pointMinusDomain.len:
        var weight: EC_P_Fr
        var lenn : int = int(precomp.barycentricWeights.len/2)
        weight = precomp.barycentricWeights[x_i+lenn]
        var term {.noInit.}: EC_P_Fr
        term.prod(weight, f[x_i])
        term.prod(term, pointMinusDomain[x_i])

        summand.sum(summand,term)

    res.setOne()

    for i in 0..<DOMAIN:

        var i_bg: matchingOrderBigInt(Banderwagon)
        i_bg.setUint(uint64(i))
        var i_fr : EC_P_Fr
        i_fr.fromBig(i_bg)

        var tmp : EC_P_Fr
        tmp.diff(point, i_fr)
        res.prod(res, tmp)

    res.prod(res,summand)

func testPoly256* [EC_P_Fr] (res: var openArray[EC_P_Fr], polynomialUint: openArray[uint64])=

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

func getDegreeOfPoly* [int] (res: var int, p: openArray[EC_P_Fr]) = 
    for d in countdown(p.len - 1, 0):
        if not(p[d].isZero().bool()):
            res = d
    
        else:
            res = -1

# func polynomialLongDivision

func polynomialLongDivision* (result: var tuple[q,r : array[DOMAIN,EC_P_Fr], ok: bool], nn, dd: var openArray[EC_P_Fr], n1: static int, n2: static int) =

    var degdd {.noInit.} : int
    degdd.getDegreeOfPoly(dd)

    doAssert degdd >= 0 == true
    var nnlen = n1
    var nn: array[nnlen + result.r.len, EC_P_Fr]
    for i in 0..<result.r.len:
        nn[nnlen - result.r.len + i] = result.r[i]
    
    var degnn {.noInit.} : int 
    if degnn >= degdd:
        result.q: array[(degnn - degdd + 1),EC_P_Fr]
        while degnn >= degdd:
            var d: array[(degnn + 1),EC_P_Fr]
            d[(degnn - degdd)..<d.len] = dd
            var tmp {.noInit.}: EC_P_Fr
            result.q[degnn - degdd] = tmp

            for i in 0..<d.len:
                d[i].prod(d[i], result.q[degnn - degdd])
                nn[i].diff(nn[i], d[i])

    result.r = nn
    result.ok = true



## ############################################################
##
##              Banderwagon Batch Serialization
##
## ############################################################
#TODO needs restructuring
func serializeBatch*(
    dst: ptr UncheckedArray[array[32, byte]],
    points: ptr UncheckedArray[EC_Prj],
    N: static int,
  ) : CttCodecEccStatus =

  # collect all the z coordinates
  var zs: array[N, Fp[Banderwagon]]
  var zs_inv: array[N, Fp[Banderwagon]]
  for i in 0 ..< N:
    zs[i] = points[i].z

  discard zs_inv.batchInvert(zs)

  for i in 0 ..< N:
    var X: Fp[Banderwagon]
    var Y: Fp[Banderwagon]

    X.prod(points[i].x, zs_inv[i])
    Y.prod(points[i].y, zs_inv[i])

    let lexicographicallyLargest = Y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
    if not lexicographicallyLargest.bool():
      X.neg()

    dst[i].marshal(X, bigEndian)

  return cttCodecEcc_Success

func serializeBatch*[N: static int](
        dst: var array[N, array[32, byte]],
        points: array[N, EC_Prj]): CttCodecEccStatus =
  return serializeBatch(dst.asUnchecked(), points.asUnchecked(), N)


            



    
    












