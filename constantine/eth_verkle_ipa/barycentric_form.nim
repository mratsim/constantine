# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.
import 
 math,
 ./eth_verkle_constants,
 ../math/config/[type_ff, curves],
 ../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
 ../math/arithmetic/[finite_fields],
 ../math/arithmetic

# ############################################################
#
#       Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 

func newPrecomputedWeights* [PrecomputedWeights] (res: var PrecomputedWeights)=
 
 var midpoint: uint64 = 256
 for i in uint64(0)..<midpoint:
  var weights {.noInit.}: EC_P_Fr
  weights.computeBarycentricWeights(i) 

  var inverseWeights {.noInit.}: EC_P_Fr
  inverseWeights.inv(weights)

  res.barycentricWeights[i] = weights
  res.barycentricWeights[i+midpoint] = inverseWeights

  midpoint = uint64(VerkleDomain) - 1

  for i in 1..<VerkleDomain:
   var k {.noInit.}: EC_P_Fr
   var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
   i_bg.setUint(uint64(i))
   k.fromBig(i_bg)

   k.inv(k)

   var neg_k : EC_P_Fr
   var zero : EC_P_Fr
   zero.setZero()
   neg_k.diff(zero, k)
   res.invertedDomain[i-1] = k
   res.invertedDomain[(i-1) + int(midpoint)] = neg_k


func computeBarycentricWeights* [EC_P_Fr] (res: var EC_P_Fr, element : uint64) = 
 if element <= uint64(VerkleDomain):

  var domain_element_Fr: EC_P_Fr
  var bigndom : matchingOrderBigInt(Banderwagon)
  bigndom.setUint(uint64(element))
  domain_element_Fr.fromBig(bigndom)

  res.setOne()

  for i in uint64(0)..<uint64(VerkleDomain):
    if i==element:
      continue

    var i_Fr: EC_P_Fr 

    var bigi:  matchingOrderBigInt(Banderwagon)
    bigi.setUint(uint64(i))
    i_Fr.fromBig(bigi)
  
    var temp: EC_P_Fr
    temp.diff(domain_element_Fr,i_Fr)
    res.prod(res, temp)


func computeBarycentricCoefficients* [EC_P_Fr]( res_inv: var openArray[EC_P_Fr], precomp: PrecomputedWeights, point : EC_P_Fr) =

  var res {.noInit.}: array[VerkleDomain, EC_P_Fr]
  for i in 0..<VerkleDomain:
    var weight: EC_P_Fr
    weight = precomp.barycentricWeights[i]
    var i_bg: matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(i))
    var i_fr: EC_P_Fr
    i_fr.fromBig(i_bg)

    res[i].diff(point, i_fr)
    res[i].prod(res[i], weight)
  
  var totalProd: EC_P_Fr
  totalProd.setOne()

  for i in 0..<VerkleDomain:
    var i_bg: matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(i))
    var i_fr: EC_P_Fr
    i_fr.fromBig(i_bg)

    var tmp: EC_P_Fr
    tmp.diff(point, i_fr)

    totalProd.prod(totalProd, tmp)

  res_inv.batchInvert(res)

  for i in 0..<VerkleDomain:
    res_inv[i].prod(res_inv[i], totalprod)


func getInvertedElement* [EC_P_Fr] ( res: var EC_P_Fr, precomp : PrecomputedWeights, element : int, is_negative: bool) =
  var index: int
  index = element - 1 

  if is_negative:
    var midpoint = int((len(precomp.invertedDomain) / 2))-1
    index = index + midpoint
  
  res = precomp.invertedDomain[index]

func getWeightRatios* [EC_P_Fr] (result: var EC_P_Fr, precomp: PrecomputedWeights, numerator: var int, denominator: var int)=

  var a = precomp.barycentricWeights[numerator]
  var midpoint = int((len(precomp.barycentricWeights) / 2))-1

  var b = precomp.barycentricWeights[denominator + midpoint]

  result.prod(a, b)


func getBarycentricInverseWeight* [EC_P_Fr] (res: var EC_P_Fr, precomp: PrecomputedWeights, i: int) =
  var midpoint = int((len(precomp.barycentricWeights) / 2))-1
  res = precomp.barycentricWeights[i+midpoint]

func absIntChecker*[int] (res: var int, x : int) =
  var is_negative {.noInit.}: bool
  if x < 0:
    is_negative = true

  if is_negative == true:
    res = -x
  else:
    res = x



func divisionOnDomain* [EC_P_Fr](res: var array[VerkleDomain,EC_P_Fr], precomp: PrecomputedWeights, index:  var int, f:  openArray[EC_P_Fr])=
  var is_negative : bool = true
  var y = f[index]

  for i in 0..<VerkleDomain:
   if not(i == index).bool() == true:    
    var denominator = i - int(index)
    var absDenominator {.noInit.}: int
    absDenominator.absIntChecker(denominator)

    if (absDenominator > 0).bool == true:
      is_negative = false

    var denominatorInv {.noInit.} : EC_P_Fr
    denominatorInv.getInvertedElement(precomp, absDenominator, is_negative)

    res[i].diff(f[i], y)
    res[i].prod(res[i], denominatorInv)

    var weight_ratios {.noInit.}: EC_P_Fr
    var dummy {.noInit.} : int
    dummy = i
    weight_ratios.getWeightRatios(precomp, index, dummy)

    #  var weight_ratios = precomp.getWeightRatios(int(index), i)

    var tmp {.noInit.}: EC_P_Fr
    tmp.prod(weight_ratios, res[i])

    res[index].diff(res[index], tmp)