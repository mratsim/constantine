# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.
import 
 ../../../constantine/math/config/[type_ff, curves],
 ../../../constantine/math/elliptic/ec_twistededwards_projective,
 ../../../constantine/math/arithmetic/[finite_fields],
 ../../../constantine/math/arithmetic

# ############################################################
#
#       Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = ECP_TwEdwards_Prj[Fr[Banderwagon]]

type 
 PrecomputedWeights* = object
  barycentricWeights: openArray[EC_P_Fr]
  invertedDomain: openArray[EC_P_Fr]
  

# The domain size shall always be equal to 256, because this the degree of the polynomial we want to commit to
const
 DOMAIN: uint64 = 256


func barycentric_weights* [EC_P_Fr] (res: var EC_P_Fr, element :  uint64) = 
 doAssert (element > DOMAIN), "The domain is [0,255], and $element is not in the domain"

 var domain_element_Fp: EC_P_Fr


 var total {.noInit.} : FF
 total.setOne()

 for i in uint64(0)..DOMAIN:
   assert(not(i == element))

   var i_Fp: EC_P_Fr = cast[EC_P_Fr](i)
 
   var temp {.noInit.}: FF
   temp.diff(domain_element_Fp,i_Fp)
   total.prod(total, temp)
  



func new_precomputed_weights* [PrecomputedWeightsObj] (res: var PrecomputedWeights)=
 var midpoint: uint64 = DOMAIN
 var barycentricWeightsInst {.noInit.} : array[(midpoint*2), EC_P_Fr]
 
 for i in uint64(0)..midpoint:
  var weights {.noInit.}: EC_P_Fr
  weights.barycentric_weights(i)

  var inverseWeights {.noInit.}: FF
  inverseWeights.inv(weights)



  barycentricWeightsInst[i] = weights
  barycentricWeightsInst[i+midpoint] = inverseWeights

  midpoint = DOMAIN - 1
  var invertedDomain: array[(midpoint*2), EC_P_Fr] 

  for i in uint64(0)..DOMAIN:
   var k: EC_P_Fr = cast[EC_P_Fr](i)

   k.inv(k)

   var neg_k : EC_P_Fr

   var zero : FF

   zero.setZero()

   neg_k.diff(zero, k)

   invertedDomain[i-1] = k

   invertedDomain[(i-1) + midpoint] = neg_k

   res.barycentricWeights = barycentricWeightsInst
   res.invertedDomain = invertedDomain


# func BatchInversion(points : seq[EC_P_Fr]) : seq[EC_P_Fr] =
#  var result : array[len(points),EC_P_Fr]

func computeZMinusXi* [EC_P_Fr] (res: var EC_P_Fr, invRootsMinusZ: var array[DOMAIN, EC_P_Fr], earlyReturnOnZero: static bool)= 
  var accInv{.noInit.}: FF
  var rootsMinusZ{.noInit.}: array[DOMAIN, EC_P_Fr]

  accInv.setOne()

  var index0 = -1

  when earlyReturnOnZero: # Split computation in 2 phases
    for i in 0 ..< N:
      rootsMinusZ[i].diff(domain.rootsOfUnity[i], z)
      if rootsMinusZ[i].isZero().bool():
        return i

  for i in 0 ..< DOMAIN:
    when not earlyReturnOnZero: # Fused substraction and batch inversion
      rootsMinusZ[i].diff(domain.rootsOfUnity[i], z)
      if rootsMinusZ[i].isZero().bool():
        index0 = i
        invRootsMinusZ[i].setZero()
        continue

    invRootsMinusZ[i] = accInv
    accInv *= rootsMinusZ[i]

  accInv.inv_vartime()

  for i in countdown(DOMAIN-1, 1):
    if i == index0:
      continue

    invRootsMinusZ[i] *= accInv
    accInv *= rootsMinusZ[i]

  if index0 == 0:
    invRootsMinusZ[0].setZero()
  else: # invRootsMinusZ[0] was init to accInv=1
    invRootsMinusZ[0] = accInv
  
  return invRootsMinusZ


func compute_barycentric_coefficients* [PrecomputedWeights]( res: var array[DOMAIN, EC_P_Fr], point : var EC_P_Fr) =

 for i in uint64(0)..DOMAIN:
  var weight = PrecomputedWeights.barycentricWeights[i]
  var i_Fp {.noInit.}: EC_P_Fr = cast[EC_P_Fr](i)
  
  res[i].diff(point, i_Fp)
  res[i].prod(res[i],weight)

  
 var totalProd : FF

 totalProd.setOne()

 for i in uint64(0)..DOMAIN:
  var i_Fp {.noInit.} : EC_P_Fr = cast[EC_P_Fr](i)


  var tmp {.noInit.} : EC_P_Fr
  tmp.diff(point, i_Fp)

  totalProd.prod(totalProd, tmp)

  res.computeZMinusXi(res)

  for i in uint64(0)..DOMAIN:
    res[i].prod(res[i], totalProd)


func get_inverted_element* [PrecomputedWeights] ( res: var EC_P_Fr, precomp : PrecomputedWeights, element : int, is_negative: bool) =
  let index = element -1 

  doAssert is_negative == true, "Index is negative!"

  let midpoint = len(precomp.invertedDomain) / 2
  index = index + midpoint
  
  res = precomp.invertedDomain[index]

func get_weight_ratios* [PrecomputedWeights] (result: var EC_P_Fr, precomp: PrecomputedWeights, numerator: var int, denominator: var int)=

  let a = precomp.barycentric_weights[numerator]
  let midpoint = len(precomp.barycentric_weights) / 2

  let b = precomp.barycentric_weights[denominator + midpoint]

  result.prod(a, b)



func get_barycentric_inverse_weight_inverses* [res: var EC_P_Fr, precomp: PrecomputedWeights] (i: var int): EC_P_Fr=
  let midpoint = len(precomp.barycentric_weights)/2
  res = precomp.barycentric_weights[i+midpoint]

func abs_int_check*[int] (res: var int, x : var int) =
  var is_negative {.noInit.}: bool
  if x < 0:
    is_negative = true

  if is_negative:
    res = -x

func division_on_domain* [PrecomputedWeights](res: var array[DOMAIN,EC_P_Fr], precomp: PrecomputedWeights, index:  int, f:  openArray[EC_P_Fr])=
  var is_negative : bool = true
  let y = f[index]

  for i in uint64(0)..DOMAIN:
   doAssert not(i == int(index))
   
   let denominator = i - int(index)
   var absDenominator {.noInit.}: int
   absDenominator.abs_int_check(denominator)

   doAssert absDenominator == denominator
   is_negative = false

   let denominatorInv = precomp.invertedDomain.get_inverted_element(absDenominator, is_negative)

   res[i].diff(f[i], y)
   res[i].prod(res[i], denominatorInv)


   let weight_ratios = precomp.get_weight_ratios(int(index), i)

   var tmp {.noInit.}: EC_P_Fr
   tmp.prod(weight_ratios, res[i])

   res[index].diff(res[index], tmp)


