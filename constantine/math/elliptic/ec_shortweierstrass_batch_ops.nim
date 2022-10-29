# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/[abstractions, allocs],
  ../arithmetic,
  ../extension_fields,
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_jacobian,
  ./ec_shortweierstrass_projective

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                     Batch addition
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
# Hence batch addition can have an asymptotic cost of
#   5M + 1S
# Compared to
#   Jacobian addition:         12M + 4S
#   Jacobian mixed addition:    7M + 4S
#   Projective addition:       12M      (for curves in the form y² = x³ + b)
#   Projective mixed addition: 11M      (for curves in the form y² = x³ + b)

func lambdaAdd[F; G: static Subgroup](lambda_num, lambda_den: var F, P, Q: ECP_ShortW_Aff[F, G]) =
  ## Compute the slope of the line (PQ)
  lambda_num.diff(Q.y, P.y)
  lambda_den.diff(Q.x, P.x)

func lambdaDouble[F; G: static Subgroup](lambda_num, lambda_den: var F, P: ECP_ShortW_Aff[F, G]) =
  ## Compute the tangent at P
  lambda_num.square(P.x)
  lambda_num *= 3
  when F.C.getCoefA() != 0:
    t += F.C.getCoefA()

  lambda_den.double(P.y)

func affineAdd[F; G: static Subgroup](
       r: var ECP_ShortW_Aff[F, G],
       lambda: var F,
       P, Q: ECP_ShortW_Aff[F, G]) =
  
  r.x.square(lambda)
  r.x -= P.x
  r.x -= Q.x

  r.y.diff(P.x, r.x)
  r.y *= lambda
  r.y -= P.y

{.push checks:off.}
func accum_half_vartime[F; G: static Subgroup](
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       lambdas: ptr UncheckedArray[tuple[num, den: F]],
       len: uint) {.noinline.} =
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
  ## Scratchspace:
  ## - Lambdas
  ## 
  ## Output:
  ## - r
  ## 
  ## Warning ⚠️ : cannot be inlined if used in loop due to the use of alloca

  debug: doAssert len and 1 == 0, "There must be an even number of points"
  
  let N = len div 2

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
    else:
      points[q].y.prod(points[q_prev].y, lambdas[i].den, skipFinalSub = true)  

  # Step 3: batch invert
  var accInv {.noInit.}: F
  accInv.setZero()
  points[len-1].y += accInv   # Undo skipFinalSub, ensure that the last accum is in canonical form, before inversion
  accInv.inv(points[len-1].y)

  # Step 4: Compute the partial sums

  template recallSpecialCase(i, p, q): untyped {.dirty.} =
    # As Qy is used as an accumulator, we saved Qy in λᵢ_num
    # For special caseshandling, restore it.
    points[q].y = lambdas[i].num
    if points[p].isInf().bool():
      points[i] = points[q]
    elif points[q].x.isZero().bool() and lambdas[i].num.isZero().bool():
      discard "points[i] = points[p]" # i == p
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

{.pop.}

# Batch addition: jacobian
# ------------------------------------------------------------

{.push checks:off.}
func accumSum_chunk_vartime[F; G: static Subgroup](
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       lambdas: ptr UncheckedArray[tuple[num, den: F]],
       len: uint) =
  ## Accumulate `points` into r.
  ## `r` is NOT overwritten
  ## r += ∑ points
  
  const ChunkThreshold = 16
  var n = len

  while n >= ChunkThreshold:
    if (n and 1) == 1: # odd number of points
      ## Accumulate the last
      r += points[n-1]
      n -= 1
    
    # Compute [0, n/2) += [n/2, n)
    accum_half_vartime(points, lambdas, n)

    # Next chunk
    n = n div 2

  # Tail
  for i in 0'u ..< n:
    r += points[i]
{.pop.}

{.push checks:off.}
func sum_batch_vartime*[F; G: static Subgroup](
       r: var (ECP_ShortW_Jac[F, G] or ECP_ShortW_Prj[F, G]),
       points: openArray[ECP_ShortW_Aff[F, G]]) =
  ## Batch addition of `points` into `r`
  ## `r` is overwritten
  
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

  r.setInf()

  const maxChunkSize = 262144 # 2¹⁸ = 262144
  const maxStride = maxChunkSize div sizeof(ECP_ShortW_Aff[F, G])
  
  let n = min(maxStride, points.len)
  let accumulators = alloca(ECP_ShortW_Aff[F, G], n)
  let lambdas = alloca(tuple[num, den: F], n)

  for i in countup(0, points.len-1, maxStride):
    let n = min(maxStride, points.len - i)
    let size = n * sizeof(ECP_ShortW_Aff[F, G])
    copyMem(accumulators[0].addr, points[i].unsafeAddr, size)
    r.accumSum_chunk_vartime(accumulators, lambdas, uint n)

{.pop.} 