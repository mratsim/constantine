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
  PrecomputedMSM*[EC; N, t, b: static int] = object
    ## Herold-Hagopian Precomputed MSM
    ##
    ## **EC** — Projective coordinate type (e.g. EC_ShortW_Jac, EC_TwEdw_Prj).
    ##          `affine(EC)` is deduced from `EC` internally.
    ## **N** — Number of basis points (MSM width).
    ## **t** — Stride (bits between precomputed layers). Larger `t` reduces
    ##        table size but adds doublings during MSM.
    ## **b** — Window size in bits. Each lookup table has `2^b` entries.
    ##
    ## - Notes on MSMs with Precomputation
    ##   Herold, 2023
    ##   https://hackmd.io/WfIjm0icSmSoqy2cfqenhQ
    ## - Verkle Trees - Another iteration of VKTs MSM
    ##   Hagopian, 2024
    ##   https://hackmd.io/@jsign/vkt-another-iteration-of-vkt-msms
    table: ptr UncheckedArray[affine(EC)]
    tableLen: int

func msmPrecompEstimateOps*[EC](_: typedesc[EC]; N, t, b: static int): tuple[add, dbl: int] =
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

proc new[EC; N, t, b: static int](
        _: typedesc[PrecompBenchContext[EC, N, t, b]],
        seed: uint64): PrecompBenchContext[EC, N, t, b] =
  const bits = EC.getScalarField().bits()
  new(result)
  template ctx: untyped = result
  ctx.rng.seed(seed)
  ctx.basisJac = newSeq[EC](N)
  ctx.basis = newSeq[EC.affine()](N)
  ctx.scalars = newSeq[BigInt[bits]](N)

  for i in 0..<N:
    ctx.scalars[i] = ctx.rng.random_unsafe(BigInt[bits])

  for i in 0..<N:
    ctx.basisJac[i] = ctx.rng.random_unsafe(EC)
    ctx.basisJac[i].clearCofactor()

  ctx.basis.asUnchecked().batchAffine_vartime(ctx.basisJac.asUnchecked(), N)

  # Precomputation timing
  let start = getMonotime()
  ctx.precomp.init(ctx.basis)
  let stop = getMonotime()
  ctx.precompTimeMs = float64(inNanoSeconds(stop-start)) / 1e6
  ctx.precompMemMiB = float64(ctx.precomp.tableLen * sizeof(affine(EC))) / 1e6

proc `=destroy`*[EC; N, t, b](ctx: var PrecomputedMSM[EC, N, t, b]) {.raises: [].} =
  if ctx.table != nil:
    freeHeapAligned(cast[pointer](ctx.table))
    ctx.table = nil
    ctx.tableLen = 0

func `=copy`*[EC; N, t, b](dst: var PrecomputedMSM[EC, N, t, b], src: PrecomputedMSM[EC, N, t, b]) {.error.}

func precomputeWindow[ECaff, EC](
      tableSlice: var openArray[ECaff],
      basisSlice: openArray[EC],
      scratchspace: var openArray[EC],
      b: static int) =
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

func init*[EC; N, t, b](
    ctx: var PrecomputedMSM[EC, N, t, b],
    basis: openArray[affine(EC)]) =
  ## Build the precomputed lookup table for `basis` points.
  ##
  ## **Preconditions**
  ## - `basis.len == N` (checked at runtime via `doAssert`)
  ## - `t >= 1` (checked at compile time via `static: doAssert`)
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
  static: doAssert t >= 1
  doAssert basis.len == N

  if ctx.table != nil:
    freeHeapAligned(ctx.table)
    ctx.table = nil

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
  let totalTableSize = numWindows * windowSize

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

func msm_vartime*[EC; N, t, b](
  ctx: PrecomputedMSM[EC, N, t, b],
  r: var EC,
  scalars: openArray[BigInt]
): tuple[add, dbl: int] {.tags:[VarTime], discardable.} =
  ## Variable-time MSM using the precomputed lookup table.
  ##
  ## **Returns** `(add, dbl)` — number of mixed additions and doublings performed.
  ##
  ## ⚠️ **VARIABLE-TIME** — execution depends on scalar bit patterns.
  ##   This MUST NOT be used with secret scalars.

  r.setNeutral()

  type ECaff = affine(EC)
  const FrBits = ECaff.getScalarField().bits()
  let windowSize = 1 shl b

  result = (add: 0, dbl: 0)

  for t_i in 0 ..< t:
    if t_i > 0:
      r.double()
      inc result.dbl

    var currWindow = 0
    var windowScalar = 0
    var windowBitPos = 0

    for scalarIdx in 0..<N:
      var k = 0
      while k < FrBits:
        let scalarBitPos = k + t - t_i - 1
        if scalarBitPos < FrBits:
          let bit = int(scalars[scalarIdx].bit(scalarBitPos))
          windowScalar = windowScalar or (bit shl windowBitPos)
        windowBitPos += 1

        if windowBitPos == b:
          if windowScalar > 0:
            r.mixedSum_vartime(r, ctx.table[currWindow * windowSize + windowScalar])
            inc result.add
          currWindow += 1
          windowScalar = 0
          windowBitPos = 0

        k += t

    # Final partial window for this t_i iteration
    if windowScalar > 0:
      r.mixedSum_vartime(r, ctx.table[currWindow * windowSize + windowScalar])
      inc result.add
