# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ../constantine/commitments/ipa/[barycentric_form,test_helper],
    std/[unittest],
    ../constantine/math/config/[type_ff, curves],
    ../constantine/math/elliptic/[
     ec_twistededwards_affine,
     ec_twistededwards_projective,
     ec_twistededwards_batch_ops
      ],
    ../constantine/math/io/io_fields,
    ../constantine/serialization/[
      codecs_status_codes,
      codecs_banderwagon,
      codecs
       ],
    ../constantine/math/arithmetic,
    ../constantine/math/constants/zoo_generators,
    ../tests/math_elliptic_curves/t_ec_template,
    ../helpers/prng_unsafe,
    ../constantine/ethereum_verkle_primitives


# ############################################################
#
#   Tests for Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 
type EFr* = Fr[Banderwagon]

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = EFr
  Bytes* = array[32, byte]

type 
    Point* = object 
     x: EFr
     y: EFr

type 
    Points* =  array[2, Point]

type Poly* = openArray[EC_P_Fr]

# The generator point from Banderwagon
var generator = Banderwagon.getGenerator()

suite "Barycentric Form Tests":

    test "Testing absolute integers":

        proc testAbsInteger() = 
            var abs {.noInit.} : int
            abs.absIntChecker(-100)
            doAssert not(abs == 100), "Absolute value should be 100!"
            doAssert abs < 0, "Value was negative!"
        
        testAbsInteger()
        
    # The interpolation is only needed for testing purposes,
    # but we need to check if it's correct. It's equivalent to getting 
    # the polynomial in coefficient form for a large number of points 

    test "Testing Basic Interpolation, without precompute optimisations":

        proc testBasicInterpolation() =

            var point_a {.noInit.} : Point

            point_a.x.setZero()
            point_a.y.setZero()

            var point_b {.noInit.} : Point

            point_b.x.setOne()
            point_b.y.setOne()

            var points {.noInit.} : Points 

            points = [point_a, point_b]

            var poly {.noInit.}: Poly

            poly.interpolate(points)

            var genfp {.noInit.} : EC_P
            genfp.fromAffine(generator)
            var genfr {.noInit.}: EC_P_Fr
            genfr.mapToScalarField(genfp)

            var res {.noInit.} : EC_P_Fr
            genfr.evaluate(poly)

            doAssert res.toHex() == genfr.toHex(), "Res and Rand_fr should match!"
            

            













