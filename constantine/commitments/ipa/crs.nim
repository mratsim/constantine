# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
 tables,
 ../../../constantine/platforms/primitives,
 ../../math/config/[type_ff, curves],
 ../../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_affine],
 ../../math/arithmetic,
 ../../math/polynomials/polynomials,
 ../../../constantine/commitments/ipa/common_utils,
 ../../math/constants/banderwagon_generators

const seed* = asBytes"eth_verkle_oct_2021"

{.used.}

# ############################################################
#
#              Common Reference String Generator
#
# ############################################################

type 
 CRS = object
  num : uint64
  groupEl:  seq[ECP_TwEdwards_Prj[Fr[Banderwagon]]]
  queryEl: ECP_TwEdwards_Prj[Fr[Banderwagon]]

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]

func prime_subgroup_generator* () : ECP_TwEdwards_Prj[Fp[Banderwagon]]=
  var generator_prj : ECP_TwEdwards_Prj[Fp[Banderwagon]]
  generator_prj.fromAffine(Banderwagon_generator)

  return generator_prj

func check_for_duplicate_field_elems* (points: var seq[EC_P] ): bool = 
    var seen = initTable[EC_P, bool]()
    #initializes a hashMap of ECP_TwistedEdwards_Prj[Fp[Banderwagon]] points 
    #from prime_subgroup_generator, for faster search and elimination
    for item in points.items():
        if seen.hasKey(item):
            return true
        else:
            seen[item]=true
    return false
        

func newCRS* [CRSobj: var CRS] (num : var uint64) : CRS = 
    var groupEl {.noInit.} : seq[EC_P]
    var iteratorr {.noInit.} : EC_P
    for iteratorr in groupEl.items():
        groupEl.add(generate_random_elements(num))
    let queryEl :  prime_subgroup_generator()

    if check_for_duplicate_field_elems(groupEl) == false:
        CRSobj  = {num, groupEl, queryEl}

    return CRSobj


# func check_crs_consistency() = 

#     var points {.noInit.} : seq[ECP]
#     points.add(generate_random_elements(32))

#     var bytes {.noInit.} : array[32, byte]
