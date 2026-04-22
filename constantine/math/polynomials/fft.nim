# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Test with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/math_polynomials/t_fft.nim
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/math_polynomials/t_fft_coset.nim

import
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/ec_shortweierstrass,
  constantine/math/elliptic/ec_scalar_mul_vartime,
  constantine/platforms/[abstractions, allocs, views]

{.push raises: [], checks: off.} # No exceptions

# Forward declarations for bit_reversal_permutation (defined later in file)
func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T])
func bit_reversal_permutation*[T](buf: var openArray[T])

# ############################################################
#
#               Fast Fourier Transform
#
# ############################################################

type
  FFTStatus* = enum
    FFT_Success
    FFT_InconsistentInputOutputLengths = "Output length must match input length"
    FFT_TooManyValues = "Input length greater than the field 2-adicity (number of roots of unity)"
    FFT_SizeNotPowerOfTwo = "Input must be of a power of 2 length"

  FrFFT_Descriptor*[F] = object
    ## Metadata for FFT on field elements
    order*: int
    rootsOfUnity*: ptr UncheckedArray[F]

  ECFFT_Descriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rootsOfUnity*: ptr UncheckedArray[getBigInt(EC.getName(), kScalarField)]
      ## domain, starting and ending with 1, length is cardinality+1
      ## This allows FFT and inverse FFT to use the same buffer for roots.

proc `=destroy`*[F](ctx: FrFFT_Descriptor[F]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

proc `=destroy`*[EC](ctx: ECFFT_Descriptor[EC]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

# ############################################################
#
#                   Field FFT
#
# ############################################################

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

func fft_internal_nn[F](
       output: var StridedView[F],
       vals: StridedView[F],
       rootsOfUnity: StridedView[F]) =
  if output.len == 1:
    output[0] = vals[0]
    return

  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  fft_internal_nn(outLeft, evenVals, halfROI)
  fft_internal_nn(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: F

  for i in 0 ..< half:
    y_times_root   .prod(output[i+half], rootsOfUnity[i])
    output[i+half] .diff(output[i], y_times_root)
    output[i]      += y_times_root

func fft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime], meter.} =
  ## FFT from natural order to natural order.
  ## Input: natural order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The FFT algorithm is NOT in-place safe. Using the same array for both
  ## input and output will produce incorrect results.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  fft_internal_nn(voutput, vals.toStridedView(), rootz)
  return FFT_Success

func fft_nr*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## FFT from natural order to bit-reversed order.
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: FFT (natural to natural) + Bit-reverse permutation
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  ##
  ## Use this when you have natural order input and want bit-reversed order output.
  ## If you want natural order output (more convenient), use fft_nn directly.
  let status = fft_nn(desc, output, vals)
  if status != FFT_Success:
    return status

  bit_reversal_permutation(output)
  return FFT_Success

func ifft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime], meter.} =
  ## IFFT from natural order to natural order.
  ## Input: natural order values in Fourier domain
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
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1)
                  .reversed()
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  fft_internal_nn(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: F
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()

  for i in 0 ..< output.len:
    output[i] *= invLen

  return FFT_Success

func ifft_rn*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## IFFT from bit-reversed order to natural order.
  ## Input: bit-reversed order values in Fourier domain
  ## Output: natural order values
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: Bit-reverse permutation + IFFT (natural to natural)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The IFFT algorithm is NOT in-place safe.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  # Create temporary buffer and bit-reverse vals into it (bit-reversed → natural)
  var temp_buf = allocHeapArrayAligned(F, vals.len, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, vals.len-1), vals)

  # Call ifft_nn (natural → natural)
  let status = ifft_nn(desc, output, temp_buf.toOpenArray(0, vals.len-1))
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
# Division by 0 during reconstruction:
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# - When reconstructing from samples, we compute (E * Z)(x) / Z(x)
#   where E is the "extended" polynomial with zeros for missing samples
#   and Z is the vanishing polynomial for missing points
# - Direct division fails when evaluating at points where Z(x) = 0
# - Coset FFT shifts the domain so Z never evaluates to zero
#
# An alternative would be using L'Hôpital's rule
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

func coset_fft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F],
       cosetShift: F): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## Compute FFT over a coset of the roots of unity (natural to natural order).
  ##
  ## This is used for polynomial operations where we need to avoid
  ## division by zero. By shifting the domain, polynomials that vanish
  ## at certain points won't cause issues during division.
  ##
  ## Algorithm:
  ##   1. Multiply vals[i] by shift_factor^i (shift into coset)
  ##   2. Apply standard FFT (natural to natural order)
  ##
  ## Parameters:
  ##   - desc: FFT descriptor with roots of unity
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form
  ##   - cosetShift, the coset shift
  ##
  ## Returns FFT_Success on success, error code otherwise
  let n = vals.len
  var shifted = allocHeapArrayAligned(F, n, alignment = 64)
  shifted.toOpenArray(n).shift_vals(vals, cosetShift)

  result = desc.fft_nn(output, shifted.toOpenArray(n))
  freeHeapAligned(shifted)

func coset_ifft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F],
       cosetShift: F): FFTStatus {.tags: [VarTime], meter.} =
  ## Compute inverse FFT over a coset of the roots of unity (natural to natural order).
  ##
  ## This is used after polynomial division in the coset domain
  ## to get back the polynomial coefficients.
  ##
  ## Algorithm:
  ##   1. Apply standard IFFT (natural to natural)
  ##   2. Multiply result[i] by shift_factor⁻ⁱ (unshift from coset)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The coset IFFT algorithm is NOT in-place safe.
  ##
  ## Parameters:
  ##   - desc: FFT descriptor with roots of unity
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form over coset
  ##   - cosetShift, the coset shift (which will be inverted)
  ##
  ## Returns FFT_Success on success, error code otherwise
  let status = desc.ifft_nn(output, vals)
  if status != FFT_Success:
    return status

  var inv_shift_factor {.noInit.}: F
  inv_shift_factor.inv_vartime(cosetShift)
  output.unshift_vals(output, inv_shift_factor)

  return FFT_Success

func coset_ifft_rn*[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F],
       cosetShift: F): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## Compute inverse FFT over a coset of the roots of unity (bit-reversed to natural order).
  ##
  ## Algorithm:
  ##   1. Bit-reverse permutation (bit-reversed → natural)
  ##   2. Apply standard IFFT (natural to natural)
  ##   3. Multiply result[i] by shift_factor⁻ⁱ (unshift from coset)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The coset IFFT algorithm is NOT in-place safe.
  ##
  ## Parameters:
  ##   - desc: CosetFFT descriptor with roots of unity and shift factor
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form over coset
  ##   - cosetShift, the coset shift (which will be inverted)
  ##
  ## Returns FFT_Success on success, error code otherwise
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len
  var temp_buf = allocHeapArrayAligned(F, n, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, n-1), vals)

  let status = desc.coset_ifft_nn(output, temp_buf.toOpenArray(0, n-1), cosetShift)
  freeHeapAligned(temp_buf)
  return status

# ############################################################
#
#                   Elliptic Curve FFT
#
# ############################################################

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

func fft_internal_nn[EC; bits: static int](
       output: var StridedView[EC],
       vals: StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
  if output.len == 1:
    output[0] = vals[0]
    return

  # Recursive Divide-and-Conquer
  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  fft_internal_nn(outLeft, evenVals, halfROI)
  fft_internal_nn(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: EC

  for i in 0 ..< half:
    # FFT Butterfly
    y_times_root   .scalarMul_vartime(rootsOfUnity[i], output[i+half])
    output[i+half] .diff_vartime(output[i], y_times_root)
    output[i]      .sum_vartime(output[i], y_times_root)

func ec_fft_nn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  fft_internal_nn(voutput, vals.toStridedView(), rootz)
  return FFT_Success

func ec_fft_nr*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## EC FFT from natural order to bit-reversed order
  ## Algorithm: FFT (natural to natural) + Bit-reverse permutation
  let status = ec_fft_nn(desc, output, vals)
  if status != FFT_Success:
    return status

  bit_reversal_permutation(output)
  return status

func ec_ifft_nn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## Inverse FFT from natural order to natural order
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1) # Extra 1 at the end so that when reversed the buffer starts with 1
                  .reversed()
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  fft_internal_nn(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: Fr[EC.getName()]
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()

  for i in 0 ..< output.len:
    output[i].scalarMul_vartime(invLen.toBig())

  return FFT_Success

func ec_ifft_rn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## Inverse FFT from bit-reversed order to natural order
  ## Algorithm: Bit-reverse permutation + IFFT (natural to natural)
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  var temp_buf = allocHeapArrayAligned(EC, vals.len, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, vals.len-1), vals)

  let status = ec_ifft_nn(desc, output, temp_buf.toOpenArray(0, vals.len-1))
  freeHeapAligned(temp_buf)
  return status

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


func bit_reversal_permutation_naive*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
  ## Out-of-place bit reversal permutation using a naive algorithm.
  ##
  ## For each index i, places src[i] into dst[reverseBits(i)].
  ##
  ## **IMPORTANT**: `dst` and `src` must NOT alias (be the same array).
  ## Use the in-place overload if you need to permute in-place.

  debug: doAssert src.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len

  let logN = log2_vartime(uint src.len)
  for i in 0'u ..< src.len.uint:
    dst[int reverseBits(i, logN)] = src[i]

func bit_reversal_permutation_naive*[T](buf: var openArray[T]) {.inline, used.} =
  ## In-place bit reversal permutation using a naive algorithm.
  ##
  ## This uses a swap-based approach where we traverse the array and
  ## swap elements to their bit-reversed positions.
  ## Only used for benchmarking.
  ##   Whether for uint32 (4 bytes) to Fr[BLS12_381]
  ##   the in-place algorithm is at least 2x slower than out-of-place
  ##   AND tuning the naive vs cobra threshold is trickier
  ##   and might severely depend on the memory bandwidth
  ##   and be very different between Apple CPUs and Intel/AMD
  debug: doAssert buf.len.uint.isPowerOf2_vartime()

  let logN = log2_vartime(uint buf.len)
  for i in 0'u ..< buf.len.uint:
    let rev_i = reverseBits(i, logN)
    if i < rev_i:
      swap(buf[i], buf[rev_i])

func bit_reversal_permutation_cobra*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) =
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
        let idx = (cRev shl (logBLen+logTileSize)) or
                  (bRev shl logTileSize) or aRev
        let tIdx = (aRev shl logTileSize) or c
        dst[idx] = t[tIdx]

  freeHeap(t)

func bit_reversal_permutation_cobra[T](buf: var openArray[T]) {.used.} =
  ## In-place bit reversal permutation using the COBRA algorithm.
  ## Only used for benchmarking.
  ##   Whether for uint32 (4 bytes) to Fr[BLS12_381]
  ##   the in-place algorithm is at least 2x slower than out-of-place
  ##   AND tuning the naive vs cobra threshold is trickier
  ##   and might severely depend on the memory bandwidth
  ##   and be very different between Apple CPUs and Intel/AMD
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

const bitReversalInPlaceThreshold {.used.} = 18
  ## Threshold (as log2) above which the COBRA algorithm is used for in-place.
  ## Below this threshold, the naive algorithm is faster on modern CPUs.

const bitReversalOutOfPlaceThreshold = 7
  ## Threshold (as log2) above which the COBRA algorithm is used for out-of-place.
  ## Below this threshold, the naive algorithm is faster on modern CPUs.

func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.meter.} =
  ## Out-of-place bit reversal permutation.
  ##
  ## Automatically selects between naive and COBRA algorithms based on size.
  ## For small sizes (< 2^7 elements), the naive algorithm is faster.
  ## For larger sizes, the COBRA cache-optimized algorithm is used.
  debug: doAssert src.len.uint.isPowerOf2_vartime()
  debug: doAssert dst.len == src.len

  let logN = log2_vartime(uint src.len)
  if logN >= bitReversalOutOfPlaceThreshold:
    # Use out-of-place COBRA for large sizes
    bit_reversal_permutation_cobra(dst, src)
  else:
    # Use naive algorithm for small sizes
    bit_reversal_permutation_naive(dst, src)

func bit_reversal_permutation*[T](buf: var openArray[T]) {.meter.} =
  ## In-place bit reversal permutation.
  ##
  ## Out-of-place is at least 2x faster than in-place so dispatch to out-of-place
  debug: doAssert buf.len > 0
  var tmp = allocHeapArrayAligned(T, buf.len, alignment = 64)
  bit_reversal_permutation(tmp.toOpenArray(0, buf.len-1), buf)
  buf[0].addr.copyMem(tmp[0].addr, buf.len * sizeof(buf[0]))
  tmp.freeHeapAligned()
