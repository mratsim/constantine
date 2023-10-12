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

func barycentricWeights* [EC_P_Fr] (res: var EC_P_Fr, element :  BigInt) = 
 doAssert (uint(element) > uint(DOMAIN)), "The domain is [0,255], and $element is not in the domain"

 var domain_element_Fr: EC_P_Fr
 domain_element_Fr.fromBig(element)

 res.setOne()

 for i in uint(0)..<uint(DOMAIN):
   assert(not(i == uint(element)))

   var i_Fr: EC_P_Fr = cast[EC_P_Fr](i)

   var bigi{.noInit.} : BigInt[i]
   i_Fr.fromBig(bigi)
 
   var temp {.noInit.}: EC_P_Fr
   temp.diff(domain_element_Fr,i_Fr)
   res.prod(res, temp)
  

func newPrecomputedWeights* [PrecomputedWeights] (res: var PrecomputedWeights, midpoint: static int)=
 var barycentricWeightsInst: array[256*2, EC_P_Fr]
 
 for i in 0..midpoint:
  var weights {.noInit.}: EC_P_Fr
  weights.barycentricWeights(BigInt[i])

  var inverseWeights {.noInit.}: EC_P_Fr
  inverseWeights.inv(weights)

  barycentricWeightsInst[i] = weights
  barycentricWeightsInst[i+midpoint] = inverseWeights

  midpoint = DOMAIN - 1
  var invertedDomainInst: array[(midpoint*2), EC_P_Fr] 

  for i in uint64(0)..<DOMAIN:
   var k: EC_P_Fr = cast[EC_P_Fr](i)

   k.inv(k)

   var neg_k : EC_P_Fr

   var zero : EC_P_Fr
   zero.setZero()

   neg_k.diff(zero, k)

   invertedDomainInst[i-1] = k

   invertedDomainInst[(i-1) + midpoint] = neg_k

   res.barycentricWeights = barycentricWeightsInst
   res.invertedDomain = invertedDomainInst


# func BatchInversion(points : seq[EC_P_Fr]) : seq[EC_P_Fr] =
#  var result : array[len(points),EC_P_Fr]



func computeBarycentricCoefficients* [PrecomputedWeights]( res: var array[DOMAIN, EC_P_Fr], point : var EC_P_Fr) =

 for i in uint64(0)..<DOMAIN:
  var weight = PrecomputedWeights.barycentricWeights[i]
  var i_Fr {.noInit.}: EC_P_Fr = cast[EC_P_Fr](i)
  
  res[i].diff(point, i_Fr)
  res[i].prod(res[i],weight)

  
 var totalProd : EC_P_Fr

 totalProd.setOne()

 for i in uint64(0)..<DOMAIN:
  var i_Fr {.noInit.} : EC_P_Fr = cast[EC_P_Fr](i)


  var tmp {.noInit.} : EC_P_Fr
  tmp.diff(point, i_Fr)

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


