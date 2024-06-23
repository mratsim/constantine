# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./eth_verkle_constants,
  ../platforms/primitives,
  ../math/config/[type_ff, curves],
  ../math/elliptic/[ec_twistededwards_affine, ec_twistededwards_projective, ec_twistededwards_batch_ops],
  ../hashes,
  ../math/arithmetic,
  ../platforms/[bithacks, views],
  ../curves_primitives,
  ../math/io/[io_bigints, io_fields],
  ../serialization/[codecs_banderwagon, codecs_status_codes, endians]

# TODO: This file is deprecated, all functionality is being replaced
# by commitments/eth_verkle_ipa

# ############################################################
#
#               Random Element Generator
#
# ############################################################


func generate_random_points*(r: var openArray[ECP_TwEdwards_Aff[Fp[Banderwagon]]]) =
  ## generate_random_points generates random points on the curve with the hardcoded VerkleSeed
  let points = allocHeapArrayAligned(ECP_TwEdwards_Aff[Fp[Banderwagon]], r.len, alignment = 64)

  var points_found: seq[ECP_TwEdwards_Aff[Fp[Banderwagon]]]
  var incrementer: uint64 = 0
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

    var x_p {.noInit.}: ECP_TwEdwards_Aff[Fp[Banderwagon]]
    let stat2 = x_p.deserialize(x_arr)
    if stat2 == cttCodecEcc_Success:
      points_found.add(x_p)
      points[idx] = points_found[idx]
      idx = idx + 1

    if points_found.len == r.len:
      break

  for i in 0 ..< r.len:
    r[i] = points[i]
  freeHeapAligned(points)

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

func foldPoints*(res: var openArray[ECP_TwEdwards_Aff[Fp[Banderwagon]]], a,b : View[ECP_TwEdwards_Aff[Fp[Banderwagon]]], x: Fr[Banderwagon])=
  ## Computes res[i] = a[i] + b[i] * x
  doAssert a.len == b.len , "Should have equal lengths!"

  # TODO extra Nim alloc to refactor away
  var t = newSeq[ECP_TwEdwards_Prj[Fp[Banderwagon]]](res.len)

  for i in 0 ..< a.len:
    var bx {.noInit.}: EC_P
    bx.fromAffine(b[i])
    bx.scalarMul_vartime(x)
    t[i].madd_vartime(bx, a[i])

  res.asUnchecked().batchAffine(t.asUnchecked(), res.len)


func computeNumRounds*(res: var uint32, vectorSize: SomeUnsignedInt)=
  ## This method takes the log2(vectorSize), a separate checker is added to prevent 0 sized vectors
  ## An additional checker is added because we also do not allow for vectors whose size is a power of 2.
  debug: doAssert (vectorSize == uint64(0)).bool() == false, "Zero is not a valid input!"

  let isP2 = isPowerOf2_vartime(vectorSize)

  debug: doAssert isP2 == true, "not a power of 2, hence not a valid inputs"

  res = uint32(log2_vartime(vectorSize))
