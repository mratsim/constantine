# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## IPAConfiguration contains all of the necessary information to create Pedersen + IPA proofs
## such as the SRS
import
  ./[eth_verkle_constants, barycentric_form],
  ../platforms/primitives,
  ../math/config/[type_ff, curves],
  ../math/elliptic/ec_twistededwards_projective,
  ../hashes,
  ../math/arithmetic,
  ../math/elliptic/ec_scalar_mul,
  ../math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
  ../platforms/[bithacks],
  ../../research/kzg/strided_views,
  ../curves_primitives,
  ../math/io/[io_bigints, io_fields],
  ../serialization/[codecs_banderwagon,codecs_status_codes, endians]

# ############################################################
#
#               Random Element Generator
#
# ############################################################


func generate_random_points* [EC_P](points: var openArray[EC_P], num_points: uint64)  =
  ## generate_random_points generates random points on the curve with the hardcoded VerkleSeed
  var points_found : seq[EC_P]
  var incrementer : uint64 = 0
  var idx: int = 0
  while true:
    var ctx {.noInit.}: sha256
    ctx.init()
    ctx.update(VerkleSeed)
    ctx.update(incrementer.toBytes(bigEndian))
    var hash : array[32, byte]
    ctx.finish(hash)
    ctx.clear()

    var x {.noInit.}:  Fp[Banderwagon]
    var t {.noInit.}: matchingBigInt(Banderwagon)

    t.unmarshal(hash, bigEndian)
    x.fromBig(t)

    incrementer = incrementer + 1

    var x_arr {.noInit.}: array[32, byte]
    x_arr.marshal(x, bigEndian)

    var x_p {.noInit.} : EC_P
    let stat2 = x_p.deserialize(x_arr)
    if stat2 == cttCodecEcc_Success:
      points_found.add(x_p)
      points[idx] = points_found[idx]
      idx = idx + 1

    if uint64(points_found.len) ==  num_points:
      break
# ############################################################
#
#                       Inner Products
#
# ############################################################

func computeInnerProducts* [Fr] (res: var Fr, a,b : openArray[Fr])=
  debug: doAssert (a.len == b.len).bool() == true, "Scalar lengths don't match!"
  res.setZero()
  for i in 0 ..< b.len:
    var tmp : Fr
    tmp.prod(a[i], b[i])
    res += tmp

func computeInnerProducts* [Fr] (res: var Fr, a,b : View[Fr])=
  debug: doAssert (a.len == b.len).bool() == true, "Scalar lengths don't match!"
  res.setZero()
  for i in 0 ..< b.len:
    var tmp : Fr
    tmp.prod(a[i], b[i])
    res.sum(res,tmp)

# ############################################################
#
#                    Folding functions
#
# ############################################################

func foldScalars*(res: var openArray[Fr[Banderwagon]], a,b : View[Fr[Banderwagon]], x: Fr[Banderwagon])=
  ## Computes res[i] = a[i] + b[i] * x
  doAssert a.len == b.len , "Lengths should be equal!"

  for i in 0 ..< a.len:
    var bx {.noInit.}: Fr[Banderwagon]
    bx.prod(b[i], x)
    res[i].sum(a[i], bx)

func foldPoints*(res: var openArray[EC_P], a,b : View[EC_P], x: Fr[Banderwagon])=
  ## Computes res[i] = a[i] + b[i] * x
  doAssert a.len == b.len , "Should have equal lengths!"

  for i in 0 ..< a.len:
    var bx {.noInit.}: EC_P
    bx = b[i]
    bx.scalarMul_vartime(x)
    res[i].sum(a[i],bx)


func computeNumRounds*(res: var uint32, vectorSize: SomeUnsignedInt)=
  ## This method takes the log2(vectorSize), a separate checker is added to prevent 0 sized vectors
  ## An additional checker is added because we also do not allow for vectors whose size is a power of 2.
  debug: doAssert (vectorSize == uint64(0)).bool() == false, "Zero is not a valid input!"

  let isP2 = isPowerOf2_vartime(vectorSize)

  debug: doAssert isP2 == true, "not a power of 2, hence not a valid inputs"

  res = uint32(log2_vartime(vectorSize))

# ############################################################
#
#                   Pedersen Commitment
#
# ############################################################

func pedersen_commit_varbasis*[EC_P] (res: var EC_P, groupPoints: openArray[EC_P], g: int,  polynomial: openArray[Fr], n: int)=
  # This Pedersen Commitment function shall be used in specifically the Split scalars
  # and Split points that are used in the IPA polynomial

  # Further reference refer to this https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html
  debug: doAssert groupPoints.len == polynomial.len, "Group Elements and Polynomials should be having the same length!"
  var poly_big = newSeq[matchingOrderBigInt(Banderwagon)](n)
  for i in 0 ..< n:
    poly_big[i] = polynomial[i].toBig()

  var groupPoints_aff = newSeq[EC_P_Aff](g)
  for i in 0 ..< g:
    groupPoints_aff[i].affine(groupPoints[i])

  res.multiScalarMul_reference_vartime(poly_big, groupPoints_aff)

func evalOutsideDomain* [Fr] (res: var Fr, precomp: PrecomputedWeights, f: openArray[Fr], point: Fr)=
# Evaluating the point z outside of VerkleDomain, here the VerkleDomain is 0-256, whereas the FieldSize is
# everywhere outside of it which is upto a 253 bit number, or 2²⁵³.
  var pointMinusDomain: array[VerkleDomain, Fr]
  var pointMinusDomain_inv: array[VerkleDomain, Fr]
  for i in 0 ..< VerkleDomain:
    var i_fr {.noInit.}: Fr
    i_fr.fromInt(i)

    pointMinusDomain[i].diff(point, i_fr)
    pointMinusDomain_inv[i].inv(pointMinusDomain[i])

  var summand: Fr
  summand.setZero()

  for x_i in 0 ..< pointMinusDomain_inv.len:
    var weight: Fr
    weight.getBarycentricInverseWeight(precomp, x_i)
    var term: Fr
    term.prod(weight, f[x_i])
    term *= pointMinusDomain_inv[x_i]

    summand.sum(summand,term)

  res.setOne()

  for i in 0 ..< VerkleDomain:
    var i_fr: Fr
    i_fr.fromInt(i)

    var tmp: Fr
    tmp.diff(point, i_fr)
    res *= tmp

  res *= summand
