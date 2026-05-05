# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/ec_shortweierstrass,
  constantine/math/ec_twistededwards,
  constantine/platforms/[allocs, views]

{.push raises: [], checks: off.}

type
  PrecomputedMSM*[EC; N: static int] = object
    ## Herold-Hagopian Precomputed MSM
    ##
    ## **EC** — Projective coordinate type (e.g. EC_ShortW_Jac, EC_TwEdw_Prj).
    ##          `affine(EC)` is deduced from `EC` internally.
    ## **N** — Number of basis points (MSM width).
    ##
    ## **t** and **b** are stored as runtime fields:
    ##   **t** — Stride (bits between precomputed layers). Larger `t` reduces
    ##        table size but adds doublings during MSM.
    ##   **b** — Window size in bits. Each lookup table has `2^b` entries.
    ##
    ## When `t == 0` or `b == 0`, the table is not built (kNoPrecompute mode).
    ##
    ## - Notes on MSMs with Precomputation
    ##   Herold, 2023
    ##   https://hackmd.io/WfIjm0icSmSoqy2cfqenhQ
    ## - Verkle Trees - Another iteration of VKTs MSM
    ##   Hagopian, 2024
    ##   https://hackmd.io/@jsign/vkt-another-iteration-of-vkt-msms
    table: ptr UncheckedArray[affine(EC)]
    tableLen: int
    t, b: int

proc `=destroy`*[EC; N](ctx: var PrecomputedMSM[EC, N]) {.raises: [].} =
  if ctx.table != nil:
    freeHeapAligned(cast[pointer](ctx.table))
    ctx.table = nil
  ctx.tableLen = 0
  ctx.t = 0
  ctx.b = 0


# Metadata
# --------------------------------------------------------------------------------------

func msmPrecompEstimateOps*[EC](_: typedesc[EC]; N, t, b: int): tuple[add, dbl: int] =
  ## Returns (additions, doublings) for one MSM execution
  const bits = EC.getScalarField().bits()

  # Doublings: one per t iteration (except first)
  let dbl = t - 1

  # Additions: Total bit extractions = N * bits
  # Each window consumes b bits, so total windows = ceil(N * bits / b)
  let totalBitExtractions = N * bits
  let numWindows = (totalBitExtractions + b - 1) div b

  # For random scalars, almost all windows are non-zero
  let add = numWindows

  (add, dbl)

func msmPrecompSize*[EC](_: typedesc[EC]; N, t, b: int): int =
  ## Returns the number of elements (table entries) in the precomputed lookup table.
  ## Returns 0 if t == 0 or b == 0 (no precompute).
  if t == 0 or b == 0:
    return 0
  const FrBits = EC.getScalarField().bits()
  let pointsPerColumn = (FrBits + t - 1) div t
  let expandedBasisLen = N * pointsPerColumn
  let numWindows = (expandedBasisLen + b - 1) div b
  let windowSize = 1 shl b
  numWindows * windowSize

# Logic
# --------------------------------------------------------------------------------------

func precomputeWindow[ECaff, EC](
      tableSlice: var openArray[ECaff],
      basisSlice: openArray[EC],
      scratchspace: var openArray[EC],
      b: int) =
  ## Build one window's lookup table using binary-tree precomputation.
  ## For each basis element, doubles the number of reachable group elements
  ## by accumulating partial sums, then converts to affine in one batch.
  static: doAssert ECaff is affine(EC)
  doAssert basisSlice.len <= b
  doAssert tableSlice.len == (1 shl b)
  doAssert tableSlice.len == scratchspace.len

  let windowSize = 1 shl b
  scratchspace[0].setNeutral()

  var currentSize = 1
  for basisIdx in 0 ..< basisSlice.len:
    let prevSize = currentSize
    currentSize = min(currentSize * 2, windowSize)
    for s in 0..<prevSize:
      if (s + prevSize) < windowSize:
        scratchspace[s + prevSize].sum_vartime(scratchspace[s], basisSlice[basisIdx])

  tableSlice.batchAffine_vartime(scratchspace)

func init*[EC; N](
    ctx: var PrecomputedMSM[EC, N],
    basis: openArray[affine(EC)],
    t, b: int) =
  ## Build the precomputed lookup table for `basis` points.
  ##
  ## **Preconditions**
  ## - `basis.len == N` (checked at runtime via `doAssert`)
  ## - `t >= 1` and `b >= 1` (checked at runtime via `doAssert`)
  ## - Passing `(0, 0)` skips table construction (kNoPrecompute mode).
  ##
  ## **Important:** `init` assumes the caller provides *well-formed* basis points:
  ## - Each point MUST lie on the curve
  ## - Each point MUST be in the correct prime-order subgroup
  ## - Each point MUST NOT be the neutral element (infinity)
  ##
  ## No on-curve or subgroup validation is performed. Passing invalid points
  ## silently produces meaningless tables. This is safe in practice because
  ## callers that parse external data (e.g. SRS files) validate during parsing,
  ## and hardcoded/test bases are known-correct.
  ##
  ## If `ctx.table` is already allocated, it is freed before the new table is built.
  doAssert basis.len == N

  # (0, 0) means no precompute
  if t == 0 or b == 0:
    ctx.t = 0
    ctx.b = 0
    return

  if ctx.table != nil:
    freeHeapAligned(ctx.table)
    ctx.table = nil
    ctx.tableLen = 0

  ctx.t = t
  ctx.b = b

  const FrBits = EC.getScalarField().bits()
  let pointsPerColumn = (FrBits + t - 1) div t
  let expandedBasisLen = N * pointsPerColumn
  let expandedBasis = allocHeapArrayAligned(EC, expandedBasisLen, alignment = 64)

  # Fill expanded basis: P, P^(2^t), P^(2^(2t)), ... for each basis point
  var idx = 0
  for i in 0 ..< N:
    expandedBasis[idx].fromAffine(basis[i])
    idx += 1
    # Expand: P_j = P_0^(2^(j*t)) via doubling chain
    for j in 1 ..< pointsPerColumn:
      expandedBasis[idx].double(expandedBasis[idx - 1])
      for _ in 1 ..< t:
        expandedBasis[idx].double()
      idx += 1

  let numWindows = (expandedBasisLen + b - 1) div b
  let windowSize = 1 shl b
  let totalTableSize = msmPrecompSize(EC, N, t, b)

  ctx.table = allocHeapArrayAligned(affine(EC), totalTableSize, alignment = 64)
  ctx.tableLen = totalTableSize

  let scratchspace = allocHeapArrayAligned(EC, windowSize, alignment = 64)

  for windowIdx in 0 ..< numWindows:
    let startIdx = windowIdx * b
    let endIdx = min(startIdx + b, expandedBasisLen)

    precomputeWindow(
      ctx.table.toOpenArray(windowIdx*windowSize, windowIdx*windowSize + windowSize - 1),
      expandedBasis.toOpenArray(startIdx, endIdx - 1),
      scratchspace.toOpenArray(windowSize),
      b
    )

  freeHeapAligned(scratchspace)
  freeHeapAligned(expandedBasis)

func msm_vartime*[EC; N](
  ctx: PrecomputedMSM[EC, N],
  r: var EC,
  scalars: openArray[BigInt]
): tuple[add, dbl: int] {.tags:[VarTime], discardable.} =
  ## Variable-time MSM using the precomputed lookup table.
  ##
  ## **Returns** `(add, dbl)` — number of mixed additions and doublings performed.
  ##
  ## ⚠️ **VARIABLE-TIME** — execution depends on scalar bit patterns.
  ##   This MUST NOT be used with secret scalars.

  doAssert ctx.t > 0 and ctx.b > 0, "[ctt] Internal error: t|b parameter must be > 0"

  r.setNeutral()

  type ECaff = affine(EC)
  const FrBits = ECaff.getScalarField().bits()
  let windowSize = 1 shl ctx.b

  result = (add: 0, dbl: 0)

  for t_i in 0 ..< ctx.t:
    if t_i > 0:
      r.double()
      inc result.dbl

    var currWindow = 0
    var windowScalar = 0
    var windowBitPos = 0

    for scalarIdx in 0..<N:
      var k = 0
      while k < FrBits:
        let scalarBitPos = k + ctx.t - t_i - 1
        if scalarBitPos < FrBits:
          let bit = int(scalars[scalarIdx].bit(scalarBitPos))
          windowScalar = windowScalar or (bit shl windowBitPos)
        windowBitPos += 1

        if windowBitPos == ctx.b:
          if windowScalar > 0:
            r.mixedSum_vartime(r, ctx.table[currWindow * windowSize + windowScalar])
            inc result.add
          currWindow += 1
          windowScalar = 0
          windowBitPos = 0

        k += ctx.t

    # Final partial window for this t_i iteration
    if windowScalar > 0:
      r.mixedSum_vartime(r, ctx.table[currWindow * windowSize + windowScalar])
      inc result.add
