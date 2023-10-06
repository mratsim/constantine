# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../arithmetic,
  ../extension_fields,
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_jacobian,
  ./ec_shortweierstrass_projective,
  ./ec_shortweierstrass_jacobian_extended

# No exceptions allowed, or array bound checks or integer overflow
{.push raises: [], checks:off.}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                     Batch conversion
#
# ############################################################

func batchAffine*[F, G](
       affs: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       projs: ptr UncheckedArray[ECP_ShortW_Prj[F, G]],
       N: int) {.noInline, tags:[Alloca].} =
  # Algorithm: Montgomery's batch inversion
  # - Speeding the Pollard and Elliptic Curve Methods of Factorization
  #   Section 10.3.1
  #   Peter L. Montgomery
  #   https://www.ams.org/journals/mcom/1987-48-177/S0025-5718-1987-0866113-7/S0025-5718-1987-0866113-7.pdf
  # - Modern Computer Arithmetic
  #   Section 2.5.1 Several inversions at once
  #   Richard P. Brent and Paul Zimmermann
  #   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf

  # To avoid temporaries, we store partial accumulations
  # in affs[i].x
  let zeroes = allocStackArray(SecretBool, N)
  affs[0].x = projs[0].z
  zeroes[0] = affs[0].x.isZero()
  affs[0].x.csetOne(zeroes[0])

  for i in 1 ..< N:
    # Skip zero z-coordinates (infinity points)
    var z = projs[i].z
    zeroes[i] = z.isZero()
    z.csetOne(zeroes[i])

    if i != N-1:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = true)
    else:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = false)

  var accInv {.noInit.}: F
  accInv.inv(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Extract 1/Pᵢ
    var invi {.noInit.}: F
    invi.prod(accInv, affs[i-1].x, skipFinalSub = true)
    invi.csetZero(zeroes[i])

    # Now convert Pᵢ to affine
    affs[i].x.prod(projs[i].x, invi)
    affs[i].y.prod(projs[i].y, invi)

    # next iteration
    invi = projs[i].z
    invi.csetOne(zeroes[i])
    accInv.prod(accInv, invi, skipFinalSub = true)

  block: # tail
    accInv.csetZero(zeroes[0])
    affs[0].x.prod(projs[0].x, accInv)
    affs[0].y.prod(projs[0].y, accInv)

func batchAffine*[N: static int, F, G](
       affs: var array[N, ECP_ShortW_Aff[F, G]],
       projs: array[N, ECP_ShortW_Prj[F, G]]) {.inline.} =
  batchAffine(affs.asUnchecked(), projs.asUnchecked(), N)

func batchAffine*[F, G](
       affs: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       jacs: ptr UncheckedArray[ECP_ShortW_Jac[F, G]],
       N: int) {.noInline, tags:[Alloca], meter.} =
  # Algorithm: Montgomery's batch inversion
  # - Speeding the Pollard and Elliptic Curve Methods of Factorization
  #   Section 10.3.1
  #   Peter L. Montgomery
  #   https://www.ams.org/journals/mcom/1987-48-177/S0025-5718-1987-0866113-7/S0025-5718-1987-0866113-7.pdf
  # - Modern Computer Arithmetic
  #   Section 2.5.1 Several inversions at once
  #   Richard P. Brent and Paul Zimmermann
  #   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf

  # To avoid temporaries, we store partial accumulations
  # in affs[i].x and whether z == 0 in affs[i].y
  var zeroes = allocStackArray(SecretBool, N)
  affs[0].x  = jacs[0].z
  zeroes[0] = affs[0].x.isZero()
  affs[0].x.csetOne(zeroes[0])

  for i in 1 ..< N:
    # Skip zero z-coordinates (infinity points)
    var z = jacs[i].z
    zeroes[i] = z.isZero()
    z.csetOne(zeroes[i])

    if i != N-1:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = true)
    else:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = false)

  var accInv {.noInit.}: F
  accInv.inv(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Extract 1/Pᵢ
    var invi {.noInit.}: F
    invi.prod(accInv, affs[i-1].x, skipFinalSub = true)
    invi.csetZero(zeroes[i])

    # Now convert Pᵢ to affine
    var invi2 {.noinit.}: F
    invi2.square(invi, skipFinalSub = true)
    affs[i].x.prod(jacs[i].x, invi2)
    invi.prod(invi, invi2, skipFinalSub = true)
    affs[i].y.prod(jacs[i].y, invi)

    # next iteration
    invi = jacs[i].z
    invi.csetOne(zeroes[i])
    accInv.prod(accInv, invi, skipFinalSub = true)

  block: # tail
    var invi2 {.noinit.}: F
    accInv.csetZero(zeroes[0])
    invi2.square(accInv, skipFinalSub = true)
    affs[0].x.prod(jacs[0].x, invi2)
    accInv.prod(accInv, invi2, skipFinalSub = true)
    affs[0].y.prod(jacs[0].y, accInv)

func batchAffine*[N: static int, F, G](
       affs: var array[N, ECP_ShortW_Aff[F, G]],
       jacs: array[N, ECP_ShortW_Jac[F, G]]) {.inline.} =
  batchAffine(affs.asUnchecked(), jacs.asUnchecked(), N)

func batchAffine*[M, N: static int, F, G](
       affs: var array[M, array[N, ECP_ShortW_Aff[F, G]]],
       projs: array[M, array[N, ECP_ShortW_Prj[F, G]]]) {.inline.} =
  batchAffine(affs[0].asUnchecked(), projs[0].asUnchecked(), M*N)

func batchAffine*[M, N: static int, F, G](
       affs: var array[M, array[N, ECP_ShortW_Aff[F, G]]],
       projs: array[M, array[N, ECP_ShortW_Jac[F, G]]]) {.inline.} =
  batchAffine(affs[0].asUnchecked(), projs[0].asUnchecked(), M*N)

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                     Sum Reduction
#
# ############################################################

# Affine primitives
# ------------------------------------------------------------
#
# The equation for elliptic curve addition is in affine (x, y) coordinates:
#
# P + Q = R
# (Px, Py) + (Qx, Qy) = (Rx, Ry)
#
# with
#   Rx = λ² - Px - Qx
#   Ry = λ(Px - Rx) - Py
#
# in the case of addition
#   λ = (Qy - Py) / (Qx - Px)
#
# which is undefined for P == Q or P == -Q as -(x, y) = (x, -y)
#
# if P = Q, the doubling formula uses the slope of the tangent at the limit
#   λ = (3 Px² + a) / (2 Px)
#
# if P = -Q, the sum is the point at infinity
#
# ~~~~
#
# Those formulas require
#   addition: 2M + 1S + 1I
#   doubling: 2M + 2S + 1I
#
# Inversion is very expensive:
#   119.5x multiplications (with ADX) for BN254
#   98.4x  multiplications (with ADX) for BLS12-381
#
# However, n inversions can use Montgomery's batch inversion
# at the cost of 3(n-1)M + 1I
#
# Hence sum reduction can have an asymptotic cost of
#   5M + 1S
# Compared to
#   Jacobian addition:         12M + 4S
#   Jacobian mixed addition:    7M + 4S
#   Projective addition:       12M      (for curves in the form y² = x³ + b)
#   Projective mixed addition: 11M      (for curves in the form y² = x³ + b)

func lambdaAdd*[F; G: static Subgroup](lambda_num, lambda_den: var F, P, Q: ECP_ShortW_Aff[F, G]) {.inline.} =
  ## Compute the slope of the line (PQ)
  lambda_num.diff(Q.y, P.y)
  lambda_den.diff(Q.x, P.x)

func lambdaSub*[F; G: static Subgroup](lambda_num, lambda_den: var F, P, Q: ECP_ShortW_Aff[F, G]) {.inline.} =
  ## Compute the slope of the line (PQ)
  lambda_num.neg(Q.y)
  lambda_num -= P.y
  lambda_den.diff(Q.x, P.x)

func lambdaDouble*[F; G: static Subgroup](lambda_num, lambda_den: var F, P: ECP_ShortW_Aff[F, G]) {.inline.} =
  ## Compute the tangent at P
  lambda_num.square(P.x)
  lambda_num *= 3
  when F.C.getCoefA() != 0:
    t += F.C.getCoefA()

  lambda_den.double(P.y)

func affineAdd*[F; G: static Subgroup](
       r{.noAlias.}: var ECP_ShortW_Aff[F, G],
       lambda: F,
       P, Q: ECP_ShortW_Aff[F, G]) =
  ## `r` MUST NOT alias P or Q
  r.x.square(lambda)
  r.x -= P.x
  r.x -= Q.x

  r.y.diff(P.x, r.x)
  r.y *= lambda
  r.y -= P.y

func accum_half_vartime[F; G: static Subgroup](
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       len: int) {.noInline, tags:[VarTime, Alloca].} =
  ## Affine accumulation of half the points into the other half
  ## Warning ⚠️ : variable-time
  ##
  ## Accumulate `len` points pairwise into `len/2`
  ##
  ## Input/output:
  ## - points: `len/2` affine points to add (must be even)
  ##           Partial sums are stored in [0, len/2)
  ##           [len/2, len) data has been destroyed
  ##
  ## Output:
  ## - r

  debug: doAssert len and 1 == 0, "There must be an even number of points"

  let N = len shr 1
  let lambdas = allocStackArray(tuple[num, den: F], N)

  # Step 1: Compute numerators and denominators of λᵢ = λᵢ_num / λᵢ_den
  for i in 0 ..< N:
    let p = i
    let q = i+N
    let q_prev = i-1+N

    # As we can't divide by 0 in normal cases, λᵢ_den != 0,
    # so we use it to indicate special handling.
    template markSpecialCase(): untyped {.dirty.} =
      #  we use Qy as an accumulator, so we save Qy in λᵢ_num
      lambdas[i].num = points[q].y
      # Mark for special handling
      lambdas[i].den.setZero()

      # Step 2: Accumulate denominators in Qy, which is not used anymore.
      if i == 0:
        points[q].y.setOne()
      else:
        points[q].y = points[q_prev].y

    # Special case 1: infinity points have affine coordinates (0, 0) by convention
    #                 it doesn't match the y²=x³+ax+b equation so slope formula need special handling
    if points[p].isInf().bool() or points[q].isInf().bool():
      markSpecialCase()
      continue

    # Special case 2: λ = (Qy-Py)/(Qx-Px) which is undefined when Px == Qx
    #                 This happens when P == Q or P == -Q
    if bool(points[p].x == points[q].x):
      if bool(points[p].y == points[q].y):
        lambdaDouble(lambdas[i].num, lambdas[i].den, points[p])
      else: # P = -Q, so P+Q = inf
        markSpecialCase()
        continue
    else:
      lambdaAdd(lambdas[i].num, lambdas[i].den, points[p], points[q])

    # Step 2: Accumulate denominators in Qy, which is not used anymore.
    if i == 0:
      points[q].y = lambdas[i].den
    elif i == N-1:
      points[q].y.prod(points[q_prev].y, lambdas[i].den)
    else:
      points[q].y.prod(points[q_prev].y, lambdas[i].den, skipFinalSub = true)

  # Step 3: batch invert
  var accInv {.noInit.}: F
  accInv.inv_vartime(points[len-1].y)

  # Step 4: Compute the partial sums

  template recallSpecialCase(i, p, q): untyped {.dirty.} =
    # As Qy is used as an accumulator, we saved Qy in λᵢ_num
    # For special cases handling, restore it.
    points[q].y = lambdas[i].num
    if points[p].isInf().bool():
      points[i] = points[q]
    elif points[q].x.isZero().bool() and lambdas[i].num.isZero().bool():
      discard "points[q] is infinity => point[p] unchanged"
    else:
      points[i].setInf()

  for i in countdown(N-1, 1):
    let p = i
    let q = i+N
    let q_prev = i-1+N

    if lambdas[i].den.isZero().bool():
      recallSpecialCase(i, p, q)
      continue

    # Compute lambda
    points[q].y.prod(accInv, points[q_prev].y, skipFinalSub = true)
    points[q].y.prod(points[q].y, lambdas[i].num, skipFinalSub = true)

    # Compute EC addition
    var r{.noInit.}: ECP_ShortW_Aff[F, G]
    r.affineAdd(lambda = points[q].y, points[p], points[q])

    # Store result
    points[i] = r

    # Next iteration
    accInv.prod(accInv, lambdas[i].den, skipFinalSub = true)

  block: # Tail
    let i = 0
    let p = 0
    let q = N

    if lambdas[0].den.isZero().bool():
      recallSpecialCase(i, p, q)
    else:
      # Compute lambda
      points[q].y.prod(lambdas[0].num, accInv, skipFinalSub = true)

      # Compute EC addition
      var r{.noInit.}: ECP_ShortW_Aff[F, G]
      r.affineAdd(lambda = points[q].y, points[p], points[q])

      # Store result
      points[0] = r

# Batch addition - High-level
# ------------------------------------------------------------

func accumSum_chunk_vartime*[F; G: static Subgroup](
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G] or ECP_ShortW_JacExt[F, G]),
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], len: int) {.noInline, tags:[VarTime, Alloca].} =
  ## Accumulate `points` into r.
  ## `r` is NOT overwritten
  ## r += ∑ points
  ##
  ## `len` should be chosen so that `len` points
  ## use cache efficiently

  let accumulators = allocStackArray(ECP_ShortW_Aff[F, G], len)
  let size = len * sizeof(ECP_ShortW_Aff[F, G])
  copyMem(accumulators[0].addr, points[0].unsafeAddr, size)

  const minNumPointsSerial = 16
  var n = len

  while n >= minNumPointsSerial:
    if (n and 1) == 1: # odd number of points
      ## Accumulate the last
      r.madd_vartime(r, points[n-1])
      n -= 1

    # Compute [0, n/2) += [n/2, n)
    accum_half_vartime(points, n)

    # Next chunk
    n = n div 2

  # Tail
  for i in 0 ..< n:
    r.madd_vartime(r, points[i])

func accum_batch_vartime[F; G: static Subgroup](
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G] or ECP_ShortW_JacExt[F, G]),
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], pointsLen: int) =
  ## Batch accumulation of `points` into `r`
  ## `r` is accumulated into

  # We chunk the addition to limit memory usage
  # especially as we allocate on the stack.

  # From experience in high-performance computing,
  # here are the constraints we want to optimize for
  #   1. MSVC limits stack to 1MB by default, we want to use a fraction of that.
  #   2. We want to use a large fraction of L2 cache, but not more.
  #   3. We want to use a large fraction of the memory addressable by the TLB.
  #   4. We optimize for hyperthreading with 2 sibling threads (Xeon Phi hyperthreads have 4 siblings).
  #      Meaning we want to use less than half the L2 cache so that if run on siblings threads (same physical core),
  #      the chunks don't evict each other.
  #
  # Hardware:
  # - a Raspberry Pi 4 (2019, Cortex A72) has 1MB L2 cache size
  # - Intel Ice Lake (2019, Core 11XXX) and AMD Zen 2 (2019, Ryzen 3XXX) have 512kB L2 cache size
  #
  # After one chunk is processed we are well within all 64-bit CPU L2 cache bounds
  # as we halve after each chunk.

  const maxTempMem = 262144 # 2¹⁸ = 262144
  const maxStride = maxTempMem div sizeof(ECP_ShortW_Aff[F, G])

  for i in countup(0, pointsLen-1, maxStride):
    let n = min(maxStride, pointsLen - i)
    r.accumSum_chunk_vartime(points +% i, n)

func sum_reduce_vartime*[F; G: static Subgroup](
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G] or ECP_ShortW_JacExt[F, G]),
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], pointsLen: int) {.inline, tags:[VarTime, Alloca].} =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  r.setInf()
  if pointsLen == 0:
    return
  r.accum_batch_vartime(points, pointsLen)

func sum_reduce_vartime*[F; G: static Subgroup](
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G] or ECP_ShortW_JacExt[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) {.inline, tags:[VarTime, Alloca].} =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  r.sum_reduce_vartime(points.asUnchecked(), points.len)

# ############################################################
#
#                  EC Addition Accumulator
#
# ############################################################

# Accumulators stores partial additions
# They allow supporting EC additions in a streaming fashion

type EcAddAccumulator_vartime*[EC, F; G: static Subgroup; AccumMax: static int] = object
  ## Elliptic curve addition accumulator
  ## **Variable-Time**
  # The `len` is dereferenced first so better locality if at the beginning
  # Do we want alignment guarantees?
  len: uint32
  accum: EC
  buffer: array[AccumMax, ECP_ShortW_Aff[F, G]]

func init*(ctx: var EcAddAccumulator_vartime) =
  static: doAssert EcAddAccumulator_vartime.AccumMax >= 16, "There is no point in a EcAddBatchAccumulator if the batch size is too small"
  ctx.accum.setInf()
  ctx.len = 0

func consumeBuffer[EC, F; G: static Subgroup; AccumMax: static int](
       ctx: var EcAddAccumulator_vartime[EC, F, G, AccumMax]) {.noInline, tags: [VarTime, Alloca].}=
  if ctx.len == 0:
    return

  ctx.accum.accumSum_chunk_vartime(ctx.buffer.asUnchecked(), ctx.len.int)
  ctx.len = 0

func update*[EC, F, G; AccumMax: static int](
        ctx: var EcAddAccumulator_vartime[EC, F, G, AccumMax],
        P: ECP_ShortW_Aff[F, G]) =

  if P.isInf().bool:
    return

  if ctx.len == AccumMax:
    ctx.consumeBuffer()

  ctx.buffer[ctx.len] = P
  ctx.len += 1

func handover*(ctx: var EcAddAccumulator_vartime) {.inline.} =
  ctx.consumeBuffer()

func merge*[EC, F, G; AccumMax: static int](
       ctxDst: var EcAddAccumulator_vartime[EC, F, G, AccumMax],
       ctxSrc: EcAddAccumulator_vartime[EC, F, G, AccumMax]) =

  var sCur = 0'u32
  var itemsLeft = ctxSrc.len

  if ctxDst.len + ctxSrc.len >= AccumMax:
    # previous partial update, fill the buffer and do a batch addition
    let free = AccumMax - ctxDst.len
    for i in 0 ..< free:
      ctxDst.buffer[ctxDst.len+i] = ctxSrc.buffer[i]
    ctxDst.len = AccumMax
    ctxDst.consumeBuffer()
    sCur = free
    itemsLeft -= free

  # Store the tail
  for i in 0 ..< itemsLeft:
    ctxDst.buffer[ctxDst.len+i] = ctxSrc.buffer[sCur+i]

  ctxDst.len += itemsLeft

  ctxDst.accum.sum_vartime(ctxDst.accum, ctxSrc.accum)


func finish*[EC, F, G; AccumMax: static int](
        ctx: var EcAddAccumulator_vartime[EC, F, G, AccumMax],
        accumulatedResult: var EC) =
  ctx.consumeBuffer()
  accumulatedResult = ctx.accum