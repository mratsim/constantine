# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ./[multiproof],
    ./helper_types,
    ../../../constantine/math/config/[type_ff, curves],
    ../../../constantine/math/elliptic/[
     ec_twistededwards_affine,
     ec_twistededwards_projective,
     ec_twistededwards_batch_ops
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
    var powers {.noInit.}: array[2,EC_P_Fr]
    powers.computePowersOfElem(point, poly.len)

    var total {.noInit.} : EC_P_Fr
    total.setZero()

    for i in 0..<poly.len:
        var tmp {.noInit.} : EC_P_Fr
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

    var max_degree_plus_one {.noInit.}: int
    max_degree_plus_one = points.len

    doAssert (max_degree_plus_one < 2).bool() == false, "Should be interpolating for degree >= 1!"

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
                    tmp *= x_j
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
            tmp *= contribution[i]
            tmp *= y_k
            res[i].sum(res[i], tmp)

        



# func *setEval [EC_P_Fr] (res: var EC_P_Fr, x : EC_P_Fr)=

#     var tmp_a {.noInit.} : EC_P_Fr

#     var one {.noInit.}: EC_P_Fr
#     one.setOne()

#     tmp_a.diff(x, one)
#     tmp_b.sum(x, one)
        










