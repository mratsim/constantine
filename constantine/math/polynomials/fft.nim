# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/ec_shortweierstrass,
  constantine/math/elliptic/ec_scalar_mul_vartime,
  constantine/platforms/[abstractions, allocs, views]

# Forward declarations for bit_reversal_permutation (defined later in file)
func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T])
func bit_reversal_permutation*[T](buf: var openArray[T])

# ############################################################
#
#               Fast Fourier Transform
#
# ############################################################

# Elliptic curve Fast Fourier Transform
# ----------------------------------------------------------------

type
  FFTStatus* = enum
    FFT_Success
    FFT_TooManyValues = "Input length greater than the field 2-adicity (number of roots of unity)"
    FFT_SizeNotPowerOfTwo = "Input must be of a power of 2 length"

  FrFFT_Descriptor*[F] = object
    ## Metadata for FFT on field elements
    order*: int
    rootsOfUnity*: ptr UncheckedArray[F]
      ## domain, starting and ending with 1, length is cardinality+1
      ## This allows FFT and inverse FFT to use the same buffer for roots.

  CosetFFT_Descriptor*[F] = object
    ## Metadata for Coset FFT operations with explicit shift amount.
    ## This clarifies the domain being used for FFT/Coset FFT operations.
    order*: int
    rootsOfUnity*: ptr UncheckedArray[F]
      ## domain, starting and ending with 1, length is cardinality+1
    shift*: F
      ## Coset shift factor. For standard FFT (no shift), this is 1.
      ## For coset operations, this is the generator of the coset.

  ECFFT_Descriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rootsOfUnity*: ptr UncheckedArray[getBigInt(EC.getName(), kScalarField)]
      ## domain, starting and ending with 1, length is cardinality+1
      ## This allows FFT and inverse FFT to use the same buffer for roots.

proc `=destroy`*[F](ctx: FrFFT_Descriptor[F]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

proc `=destroy`*[F](ctx: CosetFFT_Descriptor[F]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

proc `=destroy`*[EC](ctx: ECFFT_Descriptor[EC]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

func computeRootsOfUnity[EC](ctx: var ECFFT_Descriptor[EC], generatorRootOfUnity: auto) =
  static: doAssert typeof(generatorRootOfUnity) is Fr[EC.getName()]

  ctx.rootsOfUnity[0].setOne()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i].fromField(cur)
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool()

func new*(T: type ECFFT_Descriptor, order: int, generatorRootOfUnity: auto): T =
  result.order = order
  result.rootsOfUnity = allocHeapArrayAligned(T.EC.getScalarField().getBigInt(), order+1, alignment = 64)

  result.computeRootsOfUnity(generatorRootOfUnity)

func computeRootsOfUnity[F](ctx: var FrFFT_Descriptor[F], generatorRootOfUnity: F) =
  ctx.rootsOfUnity[0].setOne()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i] = cur
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool()

func new*(T: type FrFFT_Descriptor, order: int, generatorRootOfUnity: auto): T =
  result.order = order
  result.rootsOfUnity = allocHeapArrayAligned(T.F, order+1, alignment = 64)

  result.computeRootsOfUnity(generatorRootOfUnity)

func computeRootsOfUnity[F](ctx: var CosetFFT_Descriptor[F], generatorRootOfUnity: F) =
  ctx.rootsOfUnity[0].setOne()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i] = cur
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool()

func new*(T: type CosetFFT_Descriptor, order: int, generatorRootOfUnity: auto, shift: auto): T =
  result.order = order
  result.rootsOfUnity = allocHeapArrayAligned(T.F, order+1, alignment = 64)
  result.shift = shift

  result.computeRootsOfUnity(generatorRootOfUnity)

func simpleFT[F](
       output: var StridedView[F],
       vals: StridedView[F],
       rootsOfUnity: StridedView[F]) =

  let L = output.len
  var last {.noInit.}, v {.noInit.}: F

  for i in 0 ..< L:
    last.prod(vals[0], rootsOfUnity[0])
    for j in 1 ..< L:
      v.prod(vals[j], rootsOfUnity[(i*j) mod L])
      last += v
    output[i] = last

func fft_internal[F](
       output: var StridedView[F],
       vals: StridedView[F],
       rootsOfUnity: StridedView[F]) =
  if output.len <= 4:
    simpleFT(output, vals, rootsOfUnity)
    return

  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  fft_internal(outLeft, evenVals, halfROI)
  fft_internal(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: F

  for i in 0 ..< half:
    y_times_root   .prod(output[i+half], rootsOfUnity[i])
    output[i+half] .diff(output[i], y_times_root)
    output[i]      += y_times_root

func fft_nr*[F](
       desc: FrFFT_Descriptor[F] | CosetFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime].} =
  ## FFT from natural order to bit-reversed order.
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## NOTE: The shift in CosetFFT_Descriptor is NOT applied by this function.
  ##       To apply the shift, use `coset_fft_nr` instead.
  ##       This function treats CosetFFT_Descriptor as a regular FFT descriptor,
  ##       only using its roots of unity array.
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The FFT algorithm is NOT in-place safe. Using the same array for both
  ## input and output will produce incorrect results.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  ##
  ## This function accepts both FrFFT_Descriptor and CosetFFT_Descriptor.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)
  return FFT_Success

func fft_nn*[F](
       desc: FrFFT_Descriptor[F] | CosetFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc].} =
  ## FFT from natural order to natural order.
  ## Input: natural order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: FFT (natural to bit-reversed) + Bit-reverse permutation
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  ##
  ## Use this when you have natural order input and want natural order output.
  ## If you want bit-reversed output (more efficient), use fft_nr directly.
  let status = fft_nr(desc, output, vals)
  if status != FFT_Success:
    return status

  bit_reversal_permutation(output)
  return FFT_Success

func ifft_rn*[F](
       desc: FrFFT_Descriptor[F] | CosetFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime].} =
  ## IFFT from bit-reversed order to natural order.
  ## Input: bit-reversed order values in Fourier domain
  ## Output: natural order values
  ## Domain: roots of unity (no shift)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The IFFT algorithm is NOT in-place safe. Using the same array for both
  ## input and output will produce incorrect results.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1)
                  .reversed()
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: F
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()

  for i in 0 ..< output.len:
    output[i] *= invLen

  return FFT_Success

func ifft_nn*[F](
       desc: FrFFT_Descriptor[F] | CosetFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc].} =
  ## IFFT from natural order to natural order.
  ## Input: natural order values in Fourier domain
  ## Output: natural order values
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: Bit-reverse permutation + IFFT (bit-reversed to natural)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The IFFT algorithm is NOT in-place safe.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  ##
  ## Use this when you have natural order input and want natural order output.
  ## If you already have bit-reversed input, use ifft_rn directly.

  # Create temporary buffer and bit-reverse vals into it (natural → bit-reversed)
  var temp_buf = allocHeapArrayAligned(F, vals.len, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, vals.len-1), vals)

  # Call ifft_rn (bit-reversed → natural)
  let status = ifft_rn(desc, output, temp_buf.toOpenArray(0, vals.len-1))
  freeHeapAligned(temp_buf)
  return status

# ############################################################
#
#               Coset FFT (for Reed-Solomon erasure coding)
#
# ############################################################
#
# Coset FFT is used for polynomial division in evaluation form.
# By shifting the domain, we can divide by polynomials that vanish
# on points of the original domain without running into division by zero.
#
# Background on Reed-Solomon erasure coding:
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# - A polynomial p(x) of degree < k can be uniquely reconstructed from k+1 samples
# - Extended to degree < 2n using 2n samples (Reed-Solomon encoding)
# - The extension uses FFT to compute evaluations at 2n points
#
# The problem during reconstruction:
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# - When reconstructing from samples, we compute (E * Z)(x) / Z(x)
#   where E is the "extended" polynomial with zeros for missing samples
#   and Z is the vanishing polynomial for missing points
# - Direct division fails when evaluating at points where Z(x) = 0
# - Coset FFT shifts the domain so Z never evaluates to zero
#
# Algorithm (from spec):
# ~~~~~~~~~~~~~~~~~~~~~~
# Forward (coset_fft):
#   1. Multiply vals[i] by shift_factor^i for all i
#   2. Apply standard FFT
#
# Inverse (coset_ifft):
#   1. Apply standard IFFT
#   2. Multiply result[i] by shift_factor^(-i) for all i

func shift_vals*[F](
       output: var openarray[F],
       vals: openarray[F],
       shift_factor: F) =
  ## Multiply each entry in vals by succeeding powers of shift_factor
  ## i.e., output[0] = vals[0] * shift_factor^0
  ##       output[1] = vals[1] * shift_factor^1
  ##       ...
  ##       output[n] = vals[n] * shift_factor^n
  ##
  ## This is used in coset FFT to shift the evaluation domain.
  var shift_pow {.noInit.}: F
  shift_pow.setOne()
  for i in 0 ..< vals.len:
    output[i].prod(vals[i], shift_pow)
    shift_pow *= shift_factor

func unshift_vals*[F](
       output: var openarray[F],
       vals: openarray[F],
       inv_shift_factor: F) =
  ## Multiply each entry in vals by succeeding powers of inv_shift_factor
  ## i.e., output[i] = vals[i] * inv_shift_factor^i
  ##
  ## This is the inverse operation of shift_vals
  ## (uses the inverse of the shift factor)
  var inv_shift_pow {.noInit.}: F
  inv_shift_pow.setOne()
  for i in 0 ..< vals.len:
    output[i].prod(vals[i], inv_shift_pow)
    inv_shift_pow *= inv_shift_factor

func coset_fft_nr*[F](
       desc: CosetFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc].} =
  ## Compute FFT over a coset of the roots of unity (natural to bit-reversed order).
  ##
  ## This is used for polynomial operations where we need to avoid
  ## division by zero. By shifting the domain, polynomials that vanish
  ## at certain points won't cause issues during division.
  ##
  ## Algorithm:
  ##   1. Multiply vals[i] by shift_factor^i (shift into coset)
  ##   2. Apply standard FFT (natural to bit-reversed order)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The coset FFT algorithm is NOT in-place safe.
  ##
  ## Parameters:
  ##   - desc: CosetFFT descriptor with roots of unity and shift factor
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form
  ##
  ## Returns FFT_Success on success, error code otherwise
  if vals.len > desc.order:
    return FFT_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len
  let stride = desc.order div n

  var shifted_vals = allocHeapArrayAligned(F, n, alignment = 64)
  template shifted: untyped = shifted_vals.toOpenArray(0, n-1)
  shifted.shift_vals(vals, desc.shift)

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, stride)

  var voutput = output.toStridedView()
  fft_internal(voutput, shifted_vals.toStridedView(n), rootz)

  freeHeapAligned(shifted_vals)
  return FFT_Success

func coset_ifft_rn*[F](
       desc: CosetFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc].} =
  ## Compute inverse FFT over a coset of the roots of unity (bit-reversed to natural order).
  ##
  ## This is used after polynomial division in the coset domain
  ## to get back the polynomial coefficients.
  ##
  ## Algorithm:
  ##   1. Apply standard IFFT
  ##   2. Multiply result[i] by shift_factor^(-i) (unshift from coset)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The coset IFFT algorithm is NOT in-place safe.
  ##
  ## Parameters:
  ##   - desc: CosetFFT descriptor with roots of unity and shift factor
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form over coset
  ##
  ## Returns FFT_Success on success, error code otherwise
  if vals.len > desc.order:
    return FFT_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len
  let stride = desc.order div n

  var inv_shift_factor {.noInit.}: F
  inv_shift_factor.inv_vartime(desc.shift)

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1)
                  .reversed()
                  .slice(0, desc.order-1, stride)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: F
  invLen.fromUint(n.uint64)
  invLen.inv_vartime()

  for i in 0 ..< n:
    output[i] *= invLen

  output.unshift_vals(output, inv_shift_factor)

  return FFT_Success

func simpleFT[EC; bits: static int](
       output: var StridedView[EC],
       vals: StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) =
  # FFT is a recursive algorithm
  # This is the base-case using a O(n²) algorithm

  let L = output.len
  var last {.noInit.}, v {.noInit.}: EC

  var v0w0 {.noInit.} = vals[0]
  v0w0.scalarMul_vartime(rootsOfUnity[0])

  for i in 0 ..< L:
    last = v0w0
    for j in 1 ..< L:
      v.scalarMul_vartime(rootsOfUnity[(i*j) mod L], vals[j])
      last.sum_vartime(last, v)
    output[i] = last

func fft_internal[EC; bits: static int](
       output: var StridedView[EC],
       vals: StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
  if output.len <= 4:
    simpleFT(output, vals, rootsOfUnity)
    return

  # Recursive Divide-and-Conquer
  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  fft_internal(outLeft, evenVals, halfROI)
  fft_internal(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: EC

  for i in 0 ..< half:
    # FFT Butterfly
    y_times_root   .scalarMul_vartime(rootsOfUnity[i], output[i+half])
    output[i+half] .diff_vartime(output[i], y_times_root)
    output[i]      .sum_vartime(output[i], y_times_root)

func ec_fft_nr*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca].} =
  if vals.len > desc.order:
    return FFT_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)
  return FFT_Success

func ec_ifft_rn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca].} =
  ## Inverse FFT
  if vals.len > desc.order:
    return FFT_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1) # Extra 1 at the end so that when reversed the buffer starts with 1
                  .reversed()
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: Fr[EC.getName()]
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()

  for i in 0 ..< output.len:
    output[i].scalarMul_vartime(invLen.toBig())

  return FFT_Success

# ############################################################
#
#                   Bit reversal permutations
#
# ############################################################
# - Towards an Optimal Bit-Reversal Permutation Program
#   Larry Carter and Kang Su Gatlin, 1998
#   https://csaws.cs.technion.ac.il/~itai/Courses/Cache/bit.pdf
#
# - Practically efficient methods for performing bit-reversed
#   permutation in C++11 on the x86-64 architecture
#   Knauth, Adas, Whitfield, Wang, Ickler, Conrad, Serang, 2017
#   https://arxiv.org/pdf/1708.01873.pdf

func optimalLogTileSize(T: type): uint =
  ## Returns the optimal log of the tile size
  ## depending on the type and common L1 cache size
  # `lscpu` can return desired cache values.
  # We underestimate modern cache sizes so that performance is good even on older architectures.

  # 1. Derive ideal size depending on the type
  const cacheLine = 64'u     # Size of a cache line
  const l1Size = 32'u * 1024 # Size of L1 cache
  const elems_per_cacheline = max(1'u, cacheLine div T.sizeof().uint)

  var q = l1Size div T.sizeof().uint
  q = q div 2 # use only half of the cache, this limits cache eviction, especially with hyperthreading.
  q = q.nextPowerOfTwo_vartime().log2_vartime()
  q = q div 2 # 2²𐞥 should be smaller than the cache

  # If the cache line can accommodate spare elements
  # increment the tile size
  while 1'u shl q < elems_per_cacheline:
    q += 1

  return q

func deriveLogTileSize(T: type, logN: uint): uint =
  ## Returns the log of the tile size

  # 1. Compute the optimal tile size

  # type typ = T                          # Workaround "cannot evaluate at compile-time"
  # var q = static(optimalLogTileSize(T)) # crashes the compiler in Error: internal error: nightlies/nim-1.6.12/compiler/semtypes.nim(1921, 22)

  var q = optimalLogTileSize(T)

  # 2. We want to ensure logN - 2*q > 0
  while int(logN) - int(q+q) < 0:
    q -= 1

  return q


func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) =
  ## Out-of-place bit reversal permutation using the COBRA algorithm
  ## (Cache Optimal BitReverse Algorithm from Carter & Gatlin, 1998)
  ##
  ## This implements the "square strategy" which is cache-efficient and
  ## nearly optimal. It uses a temporary buffer that fits in L1 cache.
  ##
  ## Algorithm:
  ##   for b = 0 to 2^(lgN-2q) - 1
  ##     b' = r(b)
  ##     for a = 0 to 2^q - 1
  ##       a' = r(a)
  ##       for c = 0 to 2^q - 1
  ##         T[a'c] = A[abc]
  ##     for c = 0 to 2^q - 1
  ##       c' = r(c)
  ##       for a' = 0 to 2^q - 1
  ##         B[c'b'a'] = T[a'c]
  ##
  ## Parameters:
  ##   - dst: destination array (must have same length as src)
  ##   - src: source array in natural order
  ##
  ## The destination will contain the bit-reversed permutation of src.
  ##
  ## **IMPORTANT**: `dst` and `src` must NOT alias (be the same array).
  ## Use the in-place overload if you need to permute in-place.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.

  debug: doAssert src.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len

  let logN = log2_vartime(uint src.len)
  let logTileSize = deriveLogTileSize(T, logN)
  let logBLen = logN - 2*logTileSize
  let bLen = 1'u shl logBLen
  let tileSize = 1'u shl logTileSize

  let t = allocHeapArray(T, tileSize*tileSize)

  for b in 0'u ..< bLen:
    let bRev = reverseBits(b, logBLen)

    for a in 0'u ..< tileSize:
      let aRev = reverseBits(a, logTileSize)
      for c in 0'u ..< tileSize:
        # T[a'c] = A[abc]
        let tIdx = (aRev shl logTileSize) or c
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        t[tIdx] = src[idx]

    for c in 0'u ..< tileSize:
      let cRev = reverseBits(c, logTileSize)
      for aRev in 0'u ..< tileSize:
        # B[c'b'a'] = T[a'c]
        let tIdx = (aRev shl logTileSize) or c
        let idx = (cRev shl (logBLen+logTileSize)) or
                  (bRev shl logTileSize) or aRev
        dst[idx] = t[tIdx]

  freeHeap(t)

func bit_reversal_permutation*[T](buf: var openArray[T]) =
  ## In-place bit reversal permutation using a cache-blocking algorithm
  #
  # We adapt the following out-of-place algorithm to in-place.
  #
  # for b = 0 to 2ˆ(lgN-2q) - 1
  #   b' = r(b)
  #   for a = 0 to 2ˆq - 1
  #     a' = r(a)
  #     for c = 0 to 2ˆq - 1
  #       T[a'c] = A[abc]
  #
  #   for c = 0 to 2ˆq - 1
  #     c' = r(c)                <- Note: typo in paper, they say c'=r(a)
  #     for a' = 0 to 2ˆq - 1
  #       B[c'b'a'] = T[a'c]
  #
  # As we are in-place, A and B refer to the same buffer and
  # we don't want to destructively write to B.
  # Instead we swap B and T to save the overwritten slot.
  #
  # Due to bitreversal being an involution, we can redo the first loop
  # to place the overwritten data in its correct slot.
  #
  # Hence
  #
  # for b = 0 to 2ˆ(lgN-2q) - 1
  #   b' = r(b)
  #   for a = 0 to 2ˆq - 1
  #     a' = r(a)
  #     for c = 0 to 2ˆq - 1
  #       T[a'c] = A[abc]
  #
  #   for c = 0 to 2ˆq - 1
  #     c' = r(c)
  #     for a' = 0 to 2ˆq - 1
  #       if abc < c'b'a'
  #         swap(A[c'b'a'], T[a'c])
  #
  #   for a = 0 to 2ˆq - 1
  #     a' = r(a)
  #     for c = 0 to 2ˆq - 1
  #       c' = r(c)
  #       if abc < c'b'a'
  #         swap(A[abc], T[a'c])

  debug: doAssert buf.len.uint.isPowerOf2_vartime()

  let logN = log2_vartime(uint buf.len)
  let logTileSize = deriveLogTileSize(T, logN)
  let logBLen = logN - 2*logTileSize
  let bLen = 1'u shl logBlen
  let tileSize = 1'u shl logTileSize

  let t = allocHeapArray(T, tileSize*tileSize)

  for b in 0'u ..< bLen:
    let bRev = reverseBits(b, logBLen)

    for a in 0'u ..< tileSize:
      let aRev = reverseBits(a, logTileSize)
      for c in 0'u ..< tileSize:
        # T[a’c] = A[abc]
        let tIdx = (aRev shl logTileSize) or c
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        t[tIdx] = buf[idx]

    for c in 0'u ..< tileSize:
      let cRev = reverseBits(c, logTileSize)
      for aRev in 0'u ..< tileSize:
        let a = reverseBits(aRev, logTileSize)
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        let idxRev = (cRev shl (logBLen+logTileSize)) or
                     (bRev shl logTileSize) or aRev
        if idx < idxRev:
          let tIdx = (aRev shl logTileSize) or c
          swap(buf[idxRev], t[tIdx])

    for a in 0'u ..< tileSize:
      let aRev = reverseBits(a, logTileSize)
      for c in 0'u ..< tileSize:
        let cRev = reverseBits(c, logTileSize)
        let idx = (a shl (logBLen+logTileSize)) or
                  (b shl logTileSize) or c
        let idxRev = (cRev shl (logBLen+logTileSize)) or
                     (bRev shl logTileSize) or aRev
        if idx < idxRev:
          let tIdx = (aRev shl logTileSize) or c
          swap(buf[idx], t[tIdx])

  freeHeap(t)

# ############################################################
#
#                    Sanity checks
#
# ############################################################

when isMainModule:

  import
    std/[times, monotimes, strformat],
    helpers/prng_unsafe,
    constantine/named/zoo_generators,
    constantine/math/io/[io_fields, io_ec],
    constantine/platforms/static_for

  const ctt_eth_kzg_fr_pow2_roots_of_unity = [
    # primitive_root⁽ᵐᵒᵈᵘˡᵘˢ⁻¹⁾/⁽²^ⁱ⁾ for i in [0, 32)
    # The primitive root chosen is 7
    Fr[BLS12_381].fromHex"0x1",
    Fr[BLS12_381].fromHex"0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000",
    Fr[BLS12_381].fromHex"0x8d51ccce760304d0ec030002760300000001000000000000",
    Fr[BLS12_381].fromHex"0x345766f603fa66e78c0625cd70d77ce2b38b21c28713b7007228fd3397743f7a",
    Fr[BLS12_381].fromHex"0x20b1ce9140267af9dd1c0af834cec32c17beb312f20b6f7653ea61d87742bcce",
    Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e",
    Fr[BLS12_381].fromHex"0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53",
    Fr[BLS12_381].fromHex"0x6898111413588742b7c68b4d7fdd60d098d0caac87f5713c5130c2c1660125be",
    Fr[BLS12_381].fromHex"0x4f9b4098e2e9f12e6b368121ac0cf4ad0a0865a899e8deff4935bd2f817f694b",
    Fr[BLS12_381].fromHex"0x95166525526a65439feec240d80689fd697168a3a6000fe4541b8ff2ee0434e",
    Fr[BLS12_381].fromHex"0x325db5c3debf77a18f4de02c0f776af3ea437f9626fc085e3c28d666a5c2d854",
    Fr[BLS12_381].fromHex"0x6d031f1b5c49c83409f1ca610a08f16655ea6811be9c622d4a838b5d59cd79e5",
    Fr[BLS12_381].fromHex"0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306",
    Fr[BLS12_381].fromHex"0x485d512737b1da3d2ccddea2972e89ed146b58bc434906ac6fdd00bfc78c8967",
    Fr[BLS12_381].fromHex"0x56624634b500a166dc86b01c0d477fa6ae4622f6a9152435034d2ff22a5ad9e1",
    Fr[BLS12_381].fromHex"0x3291357ee558b50d483405417a0cbe39c8d5f51db3f32699fbd047e11279bb6e",
    Fr[BLS12_381].fromHex"0x2155379d12180caa88f39a78f1aeb57867a665ae1fcadc91d7118f85cd96b8ad",
    Fr[BLS12_381].fromHex"0x224262332d8acbf4473a2eef772c33d6cd7f2bd6d0711b7d08692405f3b70f10",
    Fr[BLS12_381].fromHex"0x2d3056a530794f01652f717ae1c34bb0bb97a3bf30ce40fd6f421a7d8ef674fb",
    Fr[BLS12_381].fromHex"0x520e587a724a6955df625e80d0adef90ad8e16e84419c750194e8c62ecb38d9d",
    Fr[BLS12_381].fromHex"0x3e1c54bcb947035a57a6e07cb98de4a2f69e02d265e09d9fece7e0e39898d4b",
    Fr[BLS12_381].fromHex"0x47c8b5817018af4fc70d0874b0691d4e46b3105f04db5844cd3979122d3ea03a",
    Fr[BLS12_381].fromHex"0xabe6a5e5abcaa32f2d38f10fbb8d1bbe08fec7c86389beec6e7a6ffb08e3363",
    Fr[BLS12_381].fromHex"0x73560252aa0655b25121af06a3b51e3cc631ffb2585a72db5616c57de0ec9eae",
    Fr[BLS12_381].fromHex"0x291cf6d68823e6876e0bcd91ee76273072cf6a8029b7d7bc92cf4deb77bd779c",
    Fr[BLS12_381].fromHex"0x19fe632fd3287390454dc1edc61a1a3c0ba12bb3da64ca5ce32ef844e11a51e",
    Fr[BLS12_381].fromHex"0xa0a77a3b1980c0d116168bffbedc11d02c8118402867ddc531a11a0d2d75182",
    Fr[BLS12_381].fromHex"0x23397a9300f8f98bece8ea224f31d25db94f1101b1d7a628e2d0a7869f0319ed",
    Fr[BLS12_381].fromHex"0x52dd465e2f09425699e276b571905a7d6558e9e3f6ac7b41d7b688830a4f2089",
    Fr[BLS12_381].fromHex"0xc83ea7744bf1bee8da40c1ef2bb459884d37b826214abc6474650359d8e211b",
    Fr[BLS12_381].fromHex"0x2c6d4e4511657e1e1339a815da8b398fed3a181fabb30adc694341f608c9dd56",
    Fr[BLS12_381].fromHex"0x4b5371495990693fad1715b02e5713b5f070bb00e28a193d63e7cb4906ffc93f"
  ]

  type EC_G1 = EC_ShortW_Prj[Fp[BLS12_381], G1]

  proc roundtrip() =
    let fftDesc = ECFFT_Descriptor[EC_G1].new(order = 1 shl 4, ctt_eth_kzg_fr_pow2_roots_of_unity[4])

    var data = newSeq[EC_G1](fftDesc.order)
    data[0].setGenerator()
    for i in 1 ..< fftDesc.order:
      data[i].mixedSum(data[i-1], BLS12_381.getGenerator("G1"))

    var coefs = newSeq[EC_G1](data.len)
    let fftOk = ec_fft_nr(fftDesc, coefs, data)
    doAssert fftOk == FFT_Success
    # display("coefs", 0, coefs)

    var res = newSeq[EC_G1](data.len)
    let ifftOk = ec_ifft_rn(fftDesc, res, coefs)
    doAssert ifftOk == FFT_Success
    # display("res", 0, res)

    for i in 0 ..< res.len:
      if bool(res[i] != data[i]):
        echo "Error: expected ", data[i].toHex(), " but got ", res[i].toHex()
        quit 1

    echo "FFT round-trip check SUCCESS"

  proc warmup() =
    # Warmup - make sure cpu is on max perf
    let start = cpuTime()
    var foo = 123
    for i in 0 ..< 300_000_000:
      foo += i*i mod 456
      foo = foo mod 789

    # Compiler shouldn't optimize away the results as cpuTime rely on sideeffects
    let stop = cpuTime()
    echo &"Warmup: {stop - start:>4.4f} s, result {foo} (displayed to avoid compiler optimizing warmup away)\n"


  proc bench() =
    echo "Starting benchmark ..."
    const NumIters = 3

    var rng: RngState
    rng.seed 0x1234
    # TODO: view types complain about mutable borrow
    # in `random_unsafe` due to pseudo view type LimbsViewMut
    # (which was views before Nim properly supported them)

    warmup()

    for scale in 4 ..< 10:
      # Setup

      let fftDesc = ECFFTDescriptor[EC_G1].new(order = 1 shl scale, ctt_eth_kzg_fr_pow2_roots_of_unity[scale])
      var data = newSeq[EC_G1](fftDesc.order)
      data[0].setGenerator()
      for i in 1 ..< fftDesc.order:
        data[i].mixedSum(data[i-1], BLS12_381.getGenerator("G1"))

      var coefsOut = newSeq[EC_G1](data.len)

      # Bench
      let start = getMonotime()
      for i in 0 ..< NumIters:
        let status = fftDesc.ec_fft_nr(coefsOut, data)
        doAssert status == FFT_Success
      let stop = getMonotime()

      let ns = inNanoseconds((stop-start) div NumIters)
      echo &"FFT scale {scale:>2}     {ns:>8} ns/op"


  proc bit_reversal() =
    let k = 28

    echo "Bit-reversal permutation 2^", k, " = ", 1 shl k, " int64"

    var a = newSeq[int64](1 shl k)
    for i in 0'i64 ..< a.len:
      a[i] = i

    var b = newSeq[int64](1 shl k)

    let startNaive = getMonotime()
    for i in 0'i64 ..< a.len:
      # It's better to make prefetching easy on the write side
      b[i] = a[int reverseBits(uint64 i, uint64 k)]
    let stopNaive = getMonotime()

    echo "Naive bit-reversal: ", inMilliseconds(stopNaive-startNaive), " ms"

    let startOpt = getMonotime()
    a.bit_reversal_permutation()
    let stopOpt = getMonotime()

    echo "Optimized in-place bit-reversal: ", inMilliseconds(stopOpt-startOpt), " ms"

    doAssert a == b
    echo "SUCCESS in-place bit reversal permutation"

    # Test out-of-place version
    var src = newSeq[int64](1 shl 20)
    for i in 0'i64 ..< src.len:
      src[i] = i

    var dst = newSeq[int64](src.len)
    let startOutOfPlace = getMonotime()
    bit_reversal_permutation(dst, src)
    let stopOutOfPlace = getMonotime()

    echo "Optimized out-of-place bit-reversal: ", inMilliseconds(stopOutOfPlace-startOutOfPlace), " ms"

    # Verify out-of-place result matches expected
    for i in 0'i64 ..< dst.len:
      let expected = src[int reverseBits(uint64 i, uint64 20)]
      doAssert dst[i] == expected, "Out-of-place mismatch at index " & $i

    echo "SUCCESS out-of-place bit reversal permutation"

    block:
      let optTile = 1 shl optimalLogTileSize(uint64)
      echo "optimal tile size for uint64: ", optTile, "x", optTile," (", sizeof(uint64) * optTile * optTile, " bytes)"

    block:
      let optTile = 1 shl optimalLogTileSize(EC_ShortW_Aff[Fp[BLS12_381], G1])
      echo "optimal tile size for EC_ShortW_Aff[Fp[BLS12_381], G1]: ", optTile, "x", optTile," (", sizeof(EC_ShortW_Aff[Fp[BLS12_381], G1]) * optTile * optTile, " bytes)"

  roundtrip()
  warmup()
  bench()
  bit_reversal()

  # Test FFT/IFFT roundtrip for all power-of-2 sizes from 2 to 32
  # This is critical for FK20 multi-proof verification where L=2 uses ω=-1
  proc roundtrip_all_sizes() =
    echo "\n=== FFT/IFFT Roundtrip Tests (Fr, all sizes) ==="
    for scale in 1 .. 5:  # sizes 2, 4, 8, 16, 32
      let order = 1 shl scale
      let root = ctt_eth_kzg_fr_pow2_roots_of_unity[scale]

      let fftDesc = FrFFT_Descriptor[Fr[BLS12_381]].new(order = order, root)

      # Create test data: consecutive values
      var data = newSeq[Fr[BLS12_381]](order)
      for i in 0 ..< order:
        data[i].fromUint(uint64(i + 1))

      # Forward FFT
      var freq = newSeq[Fr[BLS12_381]](order)
      let fftOk = fft_nn(fftDesc, freq, data)
      doAssert fftOk == FFT_Success, "FFT failed"

      # Inverse FFT
      var recovered = newSeq[Fr[BLS12_381]](order)
      let ifftOk = ifft_nn(fftDesc, recovered, freq)
      doAssert ifftOk == FFT_Success, "IFFT failed"

      # Verify roundtrip
      for i in 0 ..< order:
        doAssert (recovered[i] == data[i]).bool,
          "Roundtrip failed at size " & $order & " index " & $i

      echo "  Size ", order, ": OK"

    echo "=== All FFT/IFFT Roundtrip Tests PASSED ===\n"

  roundtrip_all_sizes()
