# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.
import 
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
 ## newPrecomputedWeights generates the precomputed weights for the barycentric formula
 ## Let's say we have 2 arrays of the same length and we join them together
 ## This is how we shall be storing A'(x_i) and 1/A'(x_i), this midpoint is used to compute
 ## the offset to wherever we need to access the 1/A'(x_i) value.

 var midpoint: uint64 = 256
 for i in uint64(0) ..< midpoint:
  var weights {.noInit.}: Fr[Banderwagon]
  weights.computeBarycentricWeights(i) 

  ## Here we are storing the VerkleDomain no. of weights, but additionally we are also 
  ## storing their inverses, hence the array length for barycentric weights as well as 
  ## inverted domain should roughly be twice the size of the VerkleDomain.
  var inverseWeights {.noInit.}: Fr[Banderwagon]
  inverseWeights.inv(weights)

  res.barycentricWeights[i] = weights
  res.barycentricWeights[i + midpoint] = inverseWeights

  ## Computing 1/k and -1/k for k in [0,255],
  ## We have one less element because we cannot do 1/0
  ## That is, division by 0.
  midpoint = uint64(VerkleDomain) - 1

  for i in 1 ..< VerkleDomain:
   var k {.noInit.}: Fr[Banderwagon]
   var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
   i_bg.setUint(uint64(i))
   k.fromBig(i_bg)

   k.inv(k)

   var neg_k : Fr[Banderwagon]
   var zero : Fr[Banderwagon]
   zero.setZero()
   neg_k.diff(zero, k)
   res.invertedDomain[i-1] = k
   res.invertedDomain[(i-1) + int(midpoint)] = neg_k


func computeBarycentricWeights*(res: var Fr[Banderwagon], element : uint64)= 
 ## Computing A'(x_j) where x_j must be an element in the domain
 ## This is computed as the product of x_j - x_i where x_i is an element in the domain
 ## also, where x_i != x_j
 if element <= uint64(VerkleDomain):

  var domain_element_Fr: Fr[Banderwagon]
  var bigndom : matchingOrderBigInt(Banderwagon)
  bigndom.setUint(uint64(element))
  domain_element_Fr.fromBig(bigndom)

  res.setOne()

  for i in uint64(0) ..< uint64(VerkleDomain):
    if i == element:
      continue

    var i_Fr: Fr[Banderwagon] 

    var bigi:  matchingOrderBigInt(Banderwagon)
    bigi.setUint(uint64(i))
    i_Fr.fromBig(bigi)
  
    var temp: Fr[Banderwagon]
    temp.diff(domain_element_Fr,i_Fr)
    res.prod(res, temp)


func computeBarycentricCoefficients*( res_inv: var openArray[Fr[Banderwagon]], precomp: PrecomputedWeights, point : Fr[Banderwagon]) =
  ## computeBarycentricCoefficients computes the coefficients for a point `z` such that
  ## when we have a polynomial `p` in Lagrange basis, the inner product of `p` and barycentric coefficients is 
  ## equal to p(z). Here `z` is a point outside of the domain. We can also term this as Lagrange Coefficients L_i.
  var res {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  for i in 0 ..< VerkleDomain:
    var weight: Fr[Banderwagon]
    weight = precomp.barycentricWeights[i]
    var i_bg: matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(i))
    var i_fr: Fr[Banderwagon]
    i_fr.fromBig(i_bg)

    res[i].diff(point, i_fr)
    res[i].prod(res[i], weight)
  
  var totalProd: Fr[Banderwagon]
  totalProd.setOne()

  for i in 0 ..< VerkleDomain:
    var i_bg: matchingOrderBigInt(Banderwagon)
    i_bg.setUint(uint64(i))
    var i_fr: Fr[Banderwagon]
    i_fr.fromBig(i_bg)

    var tmp: Fr[Banderwagon]
    tmp.diff(point, i_fr)

    totalProd.prod(totalProd, tmp)

  res_inv.batchInvert(res)

  for i in 0 ..< VerkleDomain:
    res_inv[i].prod(res_inv[i], totalprod)


func getInvertedElement*(res: var Fr[Banderwagon], precomp : PrecomputedWeights, element : int, is_negative: bool) =
  var index: int
  index = element - 1 

  if is_negative:
    var midpoint = int((len(precomp.invertedDomain) / 2)) - 1
    index = index + midpoint
  
  res = precomp.invertedDomain[index]

func getWeightRatios*(result: var Fr[Banderwagon], precomp: PrecomputedWeights, numerator: var int, denominator: var int)=

  var a = precomp.barycentricWeights[numerator]
  var midpoint = int((len(precomp.barycentricWeights) / 2)) - 1

  var b = precomp.barycentricWeights[denominator + midpoint]

  result.prod(a, b)


func getBarycentricInverseWeight*(res: var Fr[Banderwagon], precomp: PrecomputedWeights, i: int) =
  var midpoint = int((len(precomp.barycentricWeights) / 2)) - 1
  res = precomp.barycentricWeights[i+midpoint]

func absIntChecker*[int] (res: var int, x : int) =
  var is_negative {.noInit.}: bool
  if x < 0:
    is_negative = true

  if is_negative == true:
    res = - x
  else:
    res = x


func divisionOnDomain*(res: var array[VerkleDomain,Fr[Banderwagon]], precomp: PrecomputedWeights, index:  var int, f:  openArray[Fr[Banderwagon]])=
  ## Computes f(x) - f(x_i) / x - x_i using the barycentric weights, where x_i is an element in the
  var is_negative : bool = true
  var y = f[index]

  for i in 0 ..< VerkleDomain:
   if not(i == index).bool() == true:    
    var denominator = i - int(index)
    var absDenominator {.noInit.}: int
    absDenominator.absIntChecker(denominator)

    if (absDenominator > 0).bool == true:
      is_negative = false

    var denominatorInv {.noInit.} : Fr[Banderwagon]
    denominatorInv.getInvertedElement(precomp, absDenominator, is_negative)

    res[i].diff(f[i], y)
    res[i].prod(res[i], denominatorInv)

    var weight_ratios {.noInit.}: Fr[Banderwagon]
    var dummy {.noInit.} : int
    dummy = i
    weight_ratios.getWeightRatios(precomp, index, dummy)

    #  var weight_ratios = precomp.getWeightRatios(int(index), i)

    var tmp {.noInit.}: Fr[Banderwagon]
    tmp.prod(weight_ratios, res[i])

    res[index].diff(res[index], tmp)
