# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ./multiproof,
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

type EFr* = Fr[Banderwagon]

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = EFr
  Bytes* = array[32, byte]

type 
    Point* = EC_P_Fr

type 
    Points* =  openArray[Point]

type Poly* = openArray[EC_P_Fr]

func evaluate* [EC_P_Fr] (point: var EC_P_Fr, poly: Poly) = 
    var powers {.noInit.}: array[2,EC_P_Fr]
    powers.computePowersOfElem(point, poly.len)

    var total {.noInit.} : EFr
    total.setZero()

    for i in 0..<poly.len:
        var tmp {.noInit.} : EFr
        tmp.prod(powers[i], poly[i])
        total += tmp

    point = total



func interpolate* [Poly] (res: var Poly, points: Points) =
    
    var one {.noInit.} : EFr
    one.setOne()

    var zero {.noInit.} : EFr
    zero.setZero()

    var max_degree_plus_one {.noInit.}: int
    max_degree_plus_one = points.len

    doAssert max_degree_plus_one < 2, "Should be interpolating for degree >= 1!"

    var coeffs {.noInit.} : array[2, EFr]

    for k in 0..<points.len:
        var point : Point  = points[k]


        var x_k  = point.x
        var y_k  = point.y

        var contribution {.noInit.}: seq[EFr]
        var denominator {.noInit.}: EFr
        denominator.setOne()


        var max_contribution_degree = 0

        for j in 0..points.len:

            var point : EC_P_Fr = points[j]
            var x_j : BigInt = point.x

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

                var mul_by_minus_x_j {.noInit}: seq[EFr]
                for _, el in  contribution:
                    var tmp = el
                    tmp *= x_j
                    tmp.diff(zero,tmp)
                    mul_by_minus_x_j.add(tmp)

                contribution[0] = zero
                contribution = contribution[0..<max_degree_plus_one]

                doAssert not(max_degree_plus_one == mul_by_minus_x_j.len), "Malformed mul_by_minus_x_j!"

                for i in 0..<contribution.len:
                    var other = mul_by_minus_x_j[i]
                    contribution[i] += other
                
            
        
        denominator.inv(denominator)
        doAssert not(denominator.isZero()), "Denominator should not be zero!"

        for i in 0..<contribution.len:
            var tmp = contribution[i]
            tmp *= contribution[i]
            tmp *= y_k
            coeffs[i].sum(coeffs[i], tmp)

        
    res=coeffs









