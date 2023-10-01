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
    ./barycentric_form,
    ../../../constantine/platforms/primitives,
    ../../math/config/[type_ff, curves],
    ../../math/elliptic/ec_twistededwards_projective,
    ../../../constantine/hashes,
    ../../../constantine/math/arithmetic,
    ../../../constantine/math/elliptic/ec_scalar_mul,
    ../../../constantine/math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
    ../../../constantine/platforms/[bithacks,views],
    ../../../constantine/math/io/[io_fields],
    ../../../constantine/math/constants/zoo_endomorphisms,
    ../../../constantine/curves_primitives,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

# ############################################################
#
#               Random Element Generator
#
# ############################################################
const seed* = asBytes"eth_verkle_oct_2021"

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]


type
    IPASettings* = object
     SRS : openArray[EC_P]
     Q_val : EC_P
     PrecomputedWeights: PrecomputedWeights
     numRounds: uint32


func generate_random_elements* [FF](points: var  openArray[FF] , num_points: uint64)  =

    var incrementer: uint64 = 0

    while uint64(len(points)) !=  num_points:

        var digest : sha256
        digest.init()
        digest.update(seed)

        var b {.noInit.} : array[8, byte]
        digest.update(b)

        var hash {.noInit.} : array[32, byte]

        digest.finish(hash)

        var x {.noInit.}:  FF

        x.deserialize(hash)
        doAssert(cttCodecEcc_Success)
        incrementer=incrementer+1

        var x_as_Bytes {.noInit.} : array[32, byte]
        x_as_Bytes.serialize(x)
        doAssert(cttCodecEcc_Success)

        var point_found {.noInit.} : EC_P
        point_found.deserialize(x_as_Bytes)

        doAssert(cttCodecEcc_Success)
        points[incrementer] = point_found


# ############################################################
#
#                       Inner Products
#
# ############################################################

func computeInnerProducts* [FF] (res: var FF, a,b : openArray[FF]): bool {.discardable.} =
    
    let check1 = true
    if (not (len(a) == len(b))):
        check1 = false
    res.setZero()
    for i in 0..len(a):
        var tmp {.noInit.} : FF 
        tmp.prod(a[i], b[i])
        res += tmp

    return check1

# ############################################################
#
#                    Folding functions
#
# ############################################################

func foldScalars* [FF] (res: var openArray[FF], a,b : openArray[FF], x: FF)=
    
    doAssert a.len == b.len , "Lengths should be equal!"

    for i in 0..a.len:
        var bx {.noInit.}: FF
        bx.prod(x, b[i])
        res[i].sum(bx, a[i])


func foldPoints* [FF] (res: var openArray[FF], a,b : openArray[FF], x: FF)=
    
    doAssert a.len == b.len , "Should have equal lengths!"

    for i in 0..a.len:
        var bx {.noInit.}: FF

        b[i].scalarMul(x.toBig())
        bx = b[i]
        res[i].sum(bx, a[i])


func splitScalars* (t: var StridedView) : tuple[a1,a2: StridedView] {.inline.}=

    doAssert (t.len and 1), "Length must be even!"  

    let mid = t.len shr 1

    var result {.noInit.}: StridedView
    result.a1.len = mid
    result.a1.stride = t.stride
    result.a1.offset = t.offset
    result.a1.data = t.data

    result.a2.len = mid
    result.a2.stride = t.stride
    result.a2.offset = t.offset + mid
    result.a2.data = t.data

func splitPoints* (t: var StridedView) : tuple[l,r: StridedView] {.inline.}=

    doAssert (t.len and 1), "Length must be even!"

    let mid = t.len shr 1

    var result {.noInit.}: StridedView
    result.a1.len = mid
    result.a1.stride = t.stride
    result.a1.offset = t.offset
    result.a1.data = t.data

    result.a2.len = mid
    result.a2.stride = t.stride
    result.a2.offset = t.offset + mid
    result.a2.data = t.data  


func computeNumRounds* [float64] (res: var float64, vectorSize: SomeUnsignedInt)= 

    doAssert (vectorSize == 0), "Zero is not a valid input!"

    let isP2 = isPowerOf2_vartime(vectorSize) and isPowerOf2_vartime(vectorSize - 1)

    doAssert (isP2 == 1), "not a power of 2, hence not a valid inputs"

    res = float64(log2_vartime(vectorSize))

# ############################################################
#
#   Reference Multiscalar Multiplication of ECP_TwEdwardsPrj
#
# ############################################################

#A reference from https://github.com/mratsim/constantine/blob/master/constantine/math/elliptic/ec_multi_scalar_mul.nim#L96-L124
# Helper function in computing the Pedersen Commitments of scalars with group elements


func multiScalarMulImpl_reference_vartime[F, G; bits: static int](
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

  let miniMSMs = allocHeapArray(EC, numWindows)
  let buckets = allocHeapArray(EC, numBuckets)

  # Algorithm
  # ---------
  for w in 0 ..< numWindows:
    # Place our points in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setInf()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n points in 2ᶜ-1 buckets, first point per bucket is just copied
    for j in 0 ..< N:
      let b = cast[int](coefs[j].getWindowAt(w*c, c))
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
      accumBuckets.sum_vartime(accumBuckets, buckets[k]) # Stores S₈ then    S₈+S₇ then       S₈+S₇+S₆ then ...
      miniMSM.sum_vartime(miniMSM, accumBuckets)         # Stores S₈ then [2]S₈+S₇ then [3]S₈+[2]S₇+S₆ then ...

    miniMSMs[w] = miniMSM

  # 3. Final reduction.                                  Cost: (b/c - 1)x(c+1) => b/c windows, first is copied, c doublings + 1 addition per window
  r = miniMSMs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.double()
    r.sum_vartime(r, miniMSMs[w])

  # Cleanup
  # -------
  buckets.freeHeap()
  miniMSMs.freeHeap()

func multiScalarMul_reference_vartime*[EC_P](r: var EC_P, coefs: openArray[BigInt], points: openArray[EC_P]) {.tags:[VarTime, HeapAlloc].} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len

  let N = points.len
  let coefs = coefs.asUnchecked()
  let points = points.asUnchecked()
  let c = bestBucketBitSize(N, BigInt.bits, useSignedBuckets = false, useManualTuning = false)

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

func pedersen_commit_single*[EC_P] (res: var EC_P, groupPoints:EC_P, polynomial: EC_P_Fr)=
    doAssert groupPoints.len == polynomial.len, "Group Elements and Polynomials should be having the same length!"
    res.multiScalarMul_reference_vartime(groupPoints, polynomial.toBig())





