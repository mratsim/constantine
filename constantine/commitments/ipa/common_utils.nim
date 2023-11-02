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
    ./[barycentric_form,helper_types],
    ../../../constantine/platforms/primitives,
    ../../math/config/[type_ff, curves],
    ../../math/elliptic/ec_twistededwards_projective,
    ../../../constantine/hashes,
    ../../../constantine/math/arithmetic,
    ../../../constantine/math/elliptic/ec_scalar_mul,
    ../../../constantine/math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
    ../../../constantine/platforms/[bithacks,views],
    ../../../constantine/math/io/[io_fields, io_ec, io_bigints],
    ../../../constantine/curves_primitives,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes, endians]

# ############################################################
#
#               Random Element Generator
#
# ############################################################



func generate_random_points* [EC_P](points: var  openArray[EC_P] , num_points: uint64)  =

    var incrementer: uint64 = 0
    var idx: int = 0
    while uint64(len(points)) !=  num_points:

        var digest : sha256
        digest.init()
        digest.update(seed)

        digest.update(incrementer.toBytes(bigEndian))

        var hash {.noInit.} : array[32, byte]

        digest.finish(hash)

        var x {.noInit.}:  EC_P

        let stat1 =  x.deserialize(hash) 
        doAssert stat1 == cttCodecEcc_Success, "Deserialization Failure!"
        incrementer=incrementer+1

        var x_as_Bytes {.noInit.} : array[32, byte]
        let stat2 = x_as_Bytes.serialize(x)
        doAssert stat2  == cttCodecEcc_Success, "Serialization Failure!"

        var point_found {.noInit.} : EC_P
        let stat3 = point_found.deserialize(x_as_Bytes)

        doAssert stat3 == cttCodecEcc_Success, "Deserialization Failure!"
        points[idx] = point_found
        idx=idx+1


# ############################################################
#
#                       Inner Products
#
# ############################################################

func computeInnerProducts* [EC_P_Fr] (res: var EC_P_Fr, a,b : openArray[EC_P_Fr])=
  if a.len == b.len:
    res.setZero()
    for i in 0..<b.len:
        var tmp : EC_P_Fr 
        tmp.prod(a[i], b[i])
        res.sum(res,tmp)

func computeInnerProducts* [EC_P_Fr] (res: var EC_P_Fr, a,b: StridedView[EC_P_Fr])=
  if a.len == b.len:
    res.setZero()
  for i in 0..<b.len:
      var tmp : EC_P_Fr 
      tmp.prod(a[i], b[i])
      res.sum(res,tmp)
  
# ############################################################
#
#                    Folding functions
#
# ############################################################

func foldScalars* [EC_P_Fr] (res: var openArray[EC_P_Fr], a,b : openArray[EC_P_Fr], x: EC_P_Fr)=
    
    doAssert a.len == b.len , "Lengths should be equal!"

    for i in 0..<a.len:
        var bx {.noInit.}: EC_P_Fr
        bx.prod(x, b[i])
        res[i].sum(bx, a[i])


func foldPoints* [EC_P] (res: var openArray[EC_P], a,b : var openArray[EC_P], x: EC_P_Fr)=
    
    doAssert a.len == b.len , "Should have equal lengths!"

    for i in 0..<a.len:
        var bx {.noInit.}: EC_P

        b[i].scalarMul(x.toBig())
        bx = b[i]
        res[i].sum(bx, a[i])


func computeNumRounds* [uint64] (res: var uint64, vectorSize: SomeUnsignedInt)= 

    doAssert (vectorSize == uint64(0)).bool() == false, "Zero is not a valid input!"

    var isP2 : bool = isPowerOf2_vartime(vectorSize)

    doAssert isP2 == true, "not a power of 2, hence not a valid inputs"

    res = uint64(float64(log2_vartime(vectorSize)))

# ############################################################
#
#   Reference Multiscalar Multiplication of ECP_TwEdwardsPrj
#
# ############################################################

#A reference from https://github.com/mratsim/constantine/blob/master/constantine/math/elliptic/ec_multi_scalar_mul.nim#L96-L124
# Helper function in computing the Pedersen Commitments of scalars with group elements


func multiScalarMulImpl_reference_vartime[EC_P; bits: static int](
       r: var EC_P,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[EC_P],
       N: int, c: static int) {.tags:[VarTime, HeapAlloc].} =
  ## Inner implementation of MSM, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4

  # Prologue
  # --------
  const numBuckets = 1 shl c - 1 # bucket 0 is unused
  const numWindows = bits.ceilDiv_vartime(c)
  type EC = typeof(r)

  var miniMSMs = allocHeapArray(EC, numWindows)
  var buckets = allocHeapArray(EC, numBuckets)

  # Algorithm
  # ---------
  for w in 0 ..< numWindows:
    # Place our points in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setInf()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n points in 2ᶜ-1 buckets, first point per bucket is just copied
    for j in 0 ..< N:
      var b = cast[int](coefs[j].getWindowAt(w*c, c))
      if b == 0: # bucket 0 is unused, no need to add [0]Pⱼ
        continue
      else:
        buckets[b-1] += points[j]

    # 2. Bucket reduction.                               Cost: 2x(2ᶜ-2) => 2 additions per 2ᶜ-1 bucket, last bucket is just copied
    # We have ordered subset sums in each bucket, we now need to compute the mini-MSM
    #   [1]S₁ + [2]S₂ + [3]S₃ + ... + [2ᶜ-1]S₂c₋₁
    var accumBuckets{.noInit.}, miniMSM{.noInit.}: EC
    accumBuckets = buckets[numBuckets-1]
    miniMSM = buckets[numBuckets-1]

    # Example with c = 3, 2³ = 8
    for k in countdown(numBuckets-2, 0):
      accumBuckets.sum(accumBuckets, buckets[k]) # Stores S₈ then    S₈+S₇ then       S₈+S₇+S₆ then ...
      miniMSM.sum(miniMSM, accumBuckets)         # Stores S₈ then [2]S₈+S₇ then [3]S₈+[2]S₇+S₆ then ...

    miniMSMs[w] = miniMSM

  # 3. Final reduction.                                  Cost: (b/c - 1)x(c+1) => b/c windows, first is copied, c doublings + 1 addition per window
  r = miniMSMs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.double()
    r.sum(r, miniMSMs[w])

  # Cleanup
  # -------
  buckets.freeHeap()
  miniMSMs.freeHeap()

func multiScalarMul_reference_vartime_Prj*[EC_P](r: var EC_P, points: openArray[EC_P], coefs: openArray[BigInt]) {.tags:[VarTime, HeapAlloc].} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len

  var N = points.len
  var coefs = coefs.asUnchecked()
  var points = points.asUnchecked()
  var c = bestBucketBitSize(N, BigInt.bits, useSignedBuckets = false, useManualTuning = false)

  case c
  of  2: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  2)
  of  3: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  3)
  of  4: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  4)
  of  5: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  5)
  of  6: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  6)
  of  7: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  7)
  of  8: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  8)
  of  9: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  9)
  of 10: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 10)
  of 11: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 11)
  of 12: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 12)
  of 13: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 13)
  of 14: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 14)
  of 15: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 15)

  of 16..20: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 16)
  else:
    unreachable()

# ############################################################
#
#           Pedersen Commitment for a Single Polynomial
#
# ############################################################

# This Pedersen Commitment function shall be used in specifically the Split scalars 
# and Split points that are used in the IPA polynomial

# Further reference refer to this https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

func pedersen_commit_varbasis*[EC_P] (res: var EC_P, groupPoints: openArray[EC_P], polynomial: openArray[EC_P_Fr], n: int)=
  doAssert groupPoints.len == polynomial.len, "Group Elements and Polynomials should be having the same length!"
  var poly_big = newSeq[matchingOrderBigInt(Banderwagon)](n)
  for i in 0..<n:
    poly_big[i] = polynomial[i].toBig()
  res.multiScalarMul_reference_vartime_Prj(groupPoints, poly_big)
