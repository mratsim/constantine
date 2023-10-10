# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.
import 
 ./helper_types,
 ../../../constantine/math/config/[type_ff, curves],
 ../../../constantine/math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
 ../../../constantine/math/arithmetic/[finite_fields],
 ../../../constantine/math/arithmetic

# ############################################################
#
#       Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 

func barycentricWeights* [EC_P_Fr] (res: var EC_P_Fr, element :  uint64) = 
 doAssert (element > DOMAIN), "The domain is [0,255], and $element is not in the domain"

 var domain_element_Fp: EC_P_Fr


 var total {.noInit.} : FF
 total.setOne()

 for i in uint64(0)..<DOMAIN:
   assert(not(i == element))

   var i_Fp: EC_P_Fr = cast[EC_P_Fr](i)
 
   var temp {.noInit.}: FF
   temp.diff(domain_element_Fp,i_Fp)
   total.prod(total, temp)
  



func newPrecomputedWeights* [PrecomputedWeightsObj] (res: var PrecomputedWeights)=
 var midpoint: uint64 = DOMAIN
 var barycentricWeightsInst {.noInit.} : array[(midpoint*2), EC_P_Fr]
 
 for i in uint64(0)..midpoint:
  var weights {.noInit.}: EC_P_Fr
  weights.barycentricWeights(i)

  var inverseWeights {.noInit.}: FF
  inverseWeights.inv(weights)



  barycentricWeightsInst[i] = weights
  barycentricWeightsInst[i+midpoint] = inverseWeights

  midpoint = DOMAIN - 1
  var invertedDomain: array[(midpoint*2), EC_P_Fr] 

  for i in uint64(0)..<DOMAIN:
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



func computeBarycentricCoefficients* [PrecomputedWeights]( res: var array[DOMAIN, EC_P_Fr], point : var EC_P_Fr) =

 for i in uint64(0)..<DOMAIN:
  var weight = PrecomputedWeights.barycentricWeights[i]
  var i_Fp {.noInit.}: EC_P_Fr = cast[EC_P_Fr](i)
  
  res[i].diff(point, i_Fp)
  res[i].prod(res[i],weight)

  
 var totalProd : FF

 totalProd.setOne()

 for i in uint64(0)..<DOMAIN:
  var i_Fp {.noInit.} : EC_P_Fr = cast[EC_P_Fr](i)


  var tmp {.noInit.} : EC_P_Fr
  tmp.diff(point, i_Fp)

  totalProd.prod(totalProd, tmp)

  res.batchInvert(res)

  for i in uint64(0)..<DOMAIN:
    res[i].prod(res[i], totalProd)


func getInvertedElement* [PrecomputedWeights] ( res: var EC_P_Fr, precomp : PrecomputedWeights, element : int, is_negative: bool) =
  var index = element -1 

  doAssert is_negative == true, "Index is negative!"

  var midpoint = len(precomp.invertedDomain) / 2
  index = index + midpoint
  
  res = precomp.invertedDomain[index]

func getWeightRatios* [PrecomputedWeights] (result: var EC_P_Fr, precomp: PrecomputedWeights, numerator: var int, denominator: var int)=

  var a = precomp.barycentricWeights[numerator]
  var midpoint = len(precomp.barycentricWeights) / 2

  var b = precomp.barycentricWeights[denominator + midpoint]

  result.prod(a, b)



func getBarycentricInverseWeight* [EC_P_Fr] (res: var EC_P_Fr, precomp: PrecomputedWeights, i: var int) =
  var midpoint = len(precomp.barycentricWeights)/2
  res = precomp.barycentricWeights[i+midpoint]

func absIntChecker*[int] (res: var int, x : int) =
  var is_negative {.noInit.}: bool
  if x < 0:
    is_negative = true

  if is_negative == true:
    res = -x

func divisionOnDomain* [EC_P_Fr](res: var array[DOMAIN,EC_P_Fr], precomp: PrecomputedWeights, index:  int, f:  openArray[EC_P_Fr])=
  var is_negative : bool = true
  var y = f[index]

  for i in uint64(0)..<DOMAIN:
   doAssert not(i == int(index))

   var denominator = i - int(index)
   var absDenominator {.noInit.}: int
   absDenominator.absIntChecker(denominator)

   doAssert absDenominator == denominator
   is_negative = false

   var denominatorInv = precomp.invertedDomain.getInvertedElement(absDenominator, is_negative)

   res[i].diff(f[i], y)
   res[i].prod(res[i], denominatorInv)


   var weight_ratios = precomp.getWeightRatios(int(index), i)

   var tmp {.noInit.}: EC_P_Fr
   tmp.prod(weight_ratios, res[i])

   res[index].diff(res[index], tmp)


