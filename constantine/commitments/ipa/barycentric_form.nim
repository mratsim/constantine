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
 ../../../constantine/math/arithmetic/[finite_fields, bigints,bigints_montgomery],
 ../../../constantine/math/arithmetic

# ############################################################
#
#       Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 
type 
 PrecomputedWeights* = object
  barycentricWeights: seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]]
  invertedDomain: seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]]
  
type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
# The domain size shall always be equal to 256, because this the degree of the polynomial we want to commit to
const
 DOMAIN: uint64 = 256


proc barycentric_weights (element : var uint64) : ECP_TwEdwards_Prj[Fp[Banderwagon]] = 
 if element > DOMAIN:
  echo"The domain is [0,255], and $element is not in the domain"

 var domain_element_Fp: ECP_TwEdwards_Prj[Fp[Banderwagon]]


 var total : ECP_TwEdwards_Prj[Fp[Banderwagon]]

 total.x.setOne()
 total.y.setOne()
 total.z.setOne()

 for i in uint64(0)..DOMAIN:
  if i == element:
    continue

  var i_Fp: ECP_TwEdwards_Prj[Fp[Banderwagon]] = cast[ECP_TwEdwards_Prj[Fp[Banderwagon]]](i)
  # var conv_i_Fp: uint64 = cast[uint64](i_Fp)
  var temp : ECP_TwEdwards_Prj[Fp[Banderwagon]]
  temp.diff(domain_element_Fp,i_Fp)

  total.x.prod(total.x,temp.x)
  total.y.prod(total.y,temp.y)
  total.z.prod(total.z,temp.z)
  
 return total



func new_precomputed_weights* [PrecomputedWeightsObj: var PrecomputedWeights] () : PrecomputedWeights =
 var midpoint: uint64 = DOMAIN
 var barycentricWeightsInst {.noInit.} : seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]] = newSeq[ECP_TwEdwards_Prj[Fp[Banderwagon]]](midpoint * 2)
 
 for i in uint64(0)..midpoint:
  var weights : ECP_TwEdwards_Prj[Fp[Banderwagon]] = barycentric_weights(i)

  var inverseWeights : ECP_TwEdwards_Prj[Fp[Banderwagon]]

  inverseWeights.x.inv(weights.x)
  inverseWeights.y.inv(weights.y)
  inverseWeights.z.inv(weights.z)


  barycentricWeightsInst[i] = weights
  barycentricWeightsInst[i+midpoint] = inverseWeights

  midpoint = DOMAIN - 1
  var invertedDomain: seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]] = newSeq[ECP_TwEdwards_Prj[Fp[Banderwagon]]](midpoint * 2)

  for i in uint64(0)..DOMAIN:
   var k: ECP_TwEdwards_Prj[Fp[Banderwagon]] = cast[ECP_TwEdwards_Prj[Fp[Banderwagon]]](i)

   k.x.inv(k.x)
   k.y.inv(k.y)
   k.z.inv(k.z)

   var neg_k : ECP_TwEdwards_Prj[Fp[Banderwagon]]

   var zero : ECP_TwEdwards_Prj[Fp[Banderwagon]]

   zero.x.setZero()
   zero.y.setZero()
   zero.z.setZero()

   neg_k.diff(zero, k)

   invertedDomain[i-1] = k


   invertedDomain[(i-1) + midpoint] = neg_k

   PrecomputedWeightsObj = {barycentricWeightsInst, invertedDomain}

   return PrecomputedWeightsObj

# func BatchInversion(points : seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]]) : seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]] =
#  var result : array[len(points),ECP_TwEdwards_Prj[Fp[Banderwagon]]]

func computeZMinusXi* (invRootsMinusZ: var array[DOMAIN, EC_P], earlyReturnOnZero: static bool) : EC_P = 
  var accInv{.noInit.}: EC_P
  var rootsMinusZ{.noInit.}: array[DOMAIN, EC_P]

  accInv.x.setOne()
  accInv.y.setOne()
  accInv.z.setOne()

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


func compute_barycentric_coefficients* [PrecomputedWeightsObj]( point : var ECP_TwEdwards_Prj[Fp[Banderwagon]]): seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]] =
 var lagrangeEval : array[DOMAIN, ECP_TwEdwards_Prj[Fp[Banderwagon]]]

 for i in uint64(0)..DOMAIN:
  var weight = PrecomputedWeightsObj.barycentricWeights[i]
  var i_Fp: ECP_TwEdwards_Prj[Fp[Banderwagon]] = cast[ECP_TwEdwards_Prj[Fp[Banderwagon]]](i)
  
  lagrangeEval[i].diff(point, i_Fp)
  lagrangeEval[i].prod(lagrangeEval[i],weight)

  
 var totalProd : ECP_TwEdwards_Prj[Fp[Banderwagon]]

 totalProd.x.setOne()
 totalProd.y.setOne()
 totalProd.z.setOne()

 for i in uint64(0)..DOMAIN:
  var i_Fp {.noInit.} : ECP_TwEdwards_Prj[Fp[Banderwagon]] = cast[EC_P](i)


  var tmp {.noInit.} : EC_P
  tmp.diff(point, i_Fp)
  totalProd.x.prod(totalProd.x, tmp.x)
  totalProd.y.prod(totalProd.y, tmp.y)
  totalProd.z.prod(totalProd.z, tmp.z)

  lagrangeEval = computeZMinusXi(lagrangeEval)

  for i in uint64(0)..DOMAIN:
    lagrangeEval[i].prod(lagrangeEval[i], totalProd)

  return lagrangeEval

func get_inverted_element* [precomp : var PrecomputedWeights] (element : var int, is_negative: var bool): EC_P =
  let index = element -1 

  if is_negative:
    let midpoint = len(precomp.invertedDomain) / 2
    index = index + midpoint
  
  return precomp.invertedDomain[index]

func get_weight_ratios* [precomp: var PrecomputedWeights] (numerator: var int, denominator: var int): EC_P=

  let a = precomp.barycentric_weights[numerator]
  let midpoint = len(precomp.barycentric_weights) / 2

  let b = precomp.barycentric_weights[denominator + midpoint]

  var result {.noInit.}: EC_P
  result.prod(a, b)
  return result

func get_barycentric_inverse_weight_inverses* [precomp: var PrecomputedWeights] (i: var int): EC_P=
  let midpoint = len(precomp.barycentric_weights)/2
  return precomp.barycentric_weights[i+midpoint]

func abs_int_check* (x : var int) : int=
  var is_negative {.noInit.}: bool
  if x < 0:
    is_negative = true

  if is_negative:
    return -x

func division_on_domain* [precomp: var PrecomputedWeights](index: var uint8, f: var seq[EC_P]): seq[EC_P]=

  var quotient {.noInit.} : array[DOMAIN, EC_P]
  var is_negative : bool = true
  let y = f[index]

  for i in uint64(0)..DOMAIN:
    if i != int(index):
      let denominator = i - int(index)
      let absDenominator = abs_int_check(denominator)

      if absDenominator == denominator:
        is_negative = false
      
      let denominatorInv = precomp.get_inverted_element(absDenominator, is_negative)

      quotient[i].diff(f[i], y)
      quotient[i].prod(quotient[i], denominatorInv)

      let weight_ratios = precomp.get_weight_ratios(int(index), i)

      var tmp {.noInit.}: EC_P
      tmp.prod(weight_ratios, quotient[i])
      quotient[index].diff(quotient[index], tmp)
  
  return quotient








   
