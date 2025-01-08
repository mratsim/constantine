# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  constantine/platforms/abstractions

# ############################################################
#
#        Assembly implementation of bigint multiplication
#
# ############################################################

static: doAssert UseASM_ARM64

macro mul_gen[rLen, aLen, bLen: static int](
        r_PIR: var Limbs[rLen],
        a_REG: Limbs[aLen],
        b_PIR: Limbs[bLen]) =
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## Assumes r doesn't alias a or b

  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)
  let
    r = asmArray(r_PIR, rLen, PointerInReg, asmInput, memIndirect = memWrite)
    a = asmArray(a_REG, aLen, ElemsInReg, asmInput)
    b = asmArray(b_PIR, bLen, PointerInReg, asmInput, memIndirect = memRead)

    tSym = ident"t"
    tSlots = aLen+1 # Extra for high words

    biSym = ident"bi"
    bi = asmValue(biSym, Reg, asmOutputEarlyClobber)

    uSym = ident"u"
    vSym = ident"v"

  var t = asmArray(tSym, tSlots, ElemsInReg, asmOutputEarlyClobber)

  var # Break dependencies chain
    u = asmValue(uSym, Reg, asmOutputEarlyClobber)
    v = asmValue(vSym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `tSym`{.noInit, used.}: array[`tSlots`, BaseType]
    var `uSym`{.noinit.}, `vSym`{.noInit.}: BaseType
    var `biSym`{.noInit.}: BaseType

  template mulloadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul u, lhs, rhs
    ctx.adds dst, u, addend
    swap(u, v)
  template mulloadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul u, lhs, rhs
    ctx.adcs dst, u, addend
    swap(u, v)

  template mulhiadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adds dst, u, addend
    swap(u, v)
  template mulhiadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adcs dst, u, addend
    swap(u, v)
  template mulhiadd_ci(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adc dst, u, addend
    swap(u, v)

  doAssert aLen >= 2

  for i in 0 ..< min(rLen, bLen):
    ctx.ldr bi, b[i]
    if i == 0:
      ctx.mul u, a[0], bi
      ctx.str u, r[i]
      ctx.umulh t[0], a[0], bi
      swap(u, v)
      for j in 1 ..< aLen:
        ctx.mul u, a[j], bi
        ctx.umulh t[j], a[j], bi
        if j == 1:
          ctx.adds t[j-1], t[j-1], u
        else:
          ctx.adcs t[j-1], t[j-1], u
      ctx.adc t[aLen-1], t[aLen-1], xzr
      swap(u, v)
    else:
      ctx.mulloadd_co(t[0], a[0], bi, t[0])
      ctx.str t[0], r[i]
      for j in 1 ..< aLen:
        ctx.mulloadd_cio(t[j], a[j], bi, t[j])
      ctx.adc t[aLen], xzr, xzr                    # assumes N > 1

      ctx.mulhiadd_co(t[1], a[0], bi, t[1])
      for j in 2 ..< aLen:
        ctx.mulhiadd_cio(t[j], a[j-1], bi, t[j])
      ctx.mulhiadd_ci(t[aLen], a[aLen-1], bi, t[aLen])

      t.rotateLeft()

  # Copy upper-limbs to result
  for i in bLen ..< min(aLen+bLen, rLen):
    ctx.str t[i-bLen], r[i]

  # Zero the extra
  for i in aLen+bLen ..< rLen:
    ctx.str xzr, r[i]

  result.add ctx.generate()

func mul_asm*[rLen, aLen, bLen: static int](
       r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mul_gen(r, a, b)

# Squaring
# -----------------------------------------------------------------------------------------------
#
# Strategy:
# We want to use the same scheduling as mul_asm_adx
# and so process `a[0..<N]` by `word`
# and store the intermediate result in `[t[n..1]:r0]`
#
# However for squarings, all the multiplications a[i,j] * a[i,j]
# with i != j occurs twice, hence we can do them only once and double them at an opportune time.
#
# Assuming a 4 limbs bigint we have the following multiplications to do:
#
#                    a₃a₂a₁a₀
# *                  a₃a₂a₁a₀
# ---------------------------
#                        a₀a₀
#                    a₁a₁
#                a₂a₂
#            a₃a₃
#
#                      a₁a₀   |
#                    a₂a₀     |
#                  a₃a₀       |
#                             | * 2
#                  a₂a₁       |
#                a₃a₁         |
#                             |
#              a₃a₂           |
#
#            r₇r₆r₅r₄r₃r₂r₁r₀
#
# The multiplication strategy is to mulx+adox+adcx on a row (a₁a₀, a₂a₀, a₃a₀ for example)
# handling both carry into next mul and partial sums carry into t
# then saving the lowest word in t into r.
#
#   Note: a row is a sequence of multiplication that share a carry chain
#         a column is a sequence of multiplication that accumulate in the same index of r
#
# We want `t` of size N+1 with N the number of limbs just like multiplication,
# and reuse the multiplication algorithm
# this means that we need to reorganize scheduling like so to maximize utilization
#
# with 4 limbs
#                    a₃ a₂ a₁ a₀
# *                  a₃ a₂ a₁ a₀
# ------------------------------
#                          a₀*a₀
#                    a₁*a₁
#              a₂*a₂
#        a₃*a₃
#
#                 a₂*a₁ a₁*a₀   |
#              a₃*a₁ a₂*a₀      | * 2
#           a₃*a₂ a₃*a₀         |
#
#        r₇ r₆ r₅ r₄ r₃ r₂ r₁ r₀

# with 6 limbs
#                     a₅ a₄ a₃ a₂ a₁ a₀
# *                   a₅ a₄ a₃ a₂ a₁ a₀
# -------------------------------------
#                                 a₀*a₀
#                           a₁*a₁
#                     a₂*a₂
#               a₃*a₃
#         a₄*a₄
#   a₅*a₅
#
#                  a₃*a₂ a₂*a₁ a₁*a₀           |
#               a₄*a₂ a₃*a₁ a₂*a₀              |
#            a₄*a₃ a₄*a₁ a₃*a₀                 | * 2
#         a₅*a₃ a₅*a₁ a₄*a₀                    |
#      a₅*a₄ a₅*a₂ a₅*a₀                       |
#
#
# r₁₁ r₁₀ r₉ r₈ r₇ r₆ r₅ r₄ r₃ r₂ r₁ r₀
#
# We want to use an index as much as possible in the row.
# There is probably a clever solution
#   (graphs with longest path/subsequence, polyhedral or tree traversal)
# but we only care about 4*4 and 6*6 at the moment.

template sqr_firstrow(
      ctx: var Assembler_arm64,
      r, a: OperandArray,
      t: OperandArray) =

  # First row. a₀ * [aₙ₋₁ .. a₂ a₁]
  # ------------------------------------
  # This assumes that t will be rotated left and so
  # t1 is in t[0] and tn in t[n-1]

  let N = a.len
  doAssert t.len == N+1
  let lo = t[N] # extra temp buffer

  ctx.comment "First diagonal. a₀ * [aₙ₋₁ .. a₂ a₁]"
  ctx.comment "----------"
  # ctx.mov t[0], xzr
  ctx.str xzr, r[0]

  ctx.comment "a₁*a₀"
  ctx.mul lo, a[1], a[0]
  ctx.str lo, r[1]            # r₁ finished
  ctx.umulh t[1], a[1], a[0]  # t₁ partial sum of r₂

  for j in 1 ..< N-1:
    ctx.comment "a" & $j & "*a₀"
    ctx.mul lo, a[j+1], a[0]
    ctx.umulh t[j+1], a[j+1], a[0]
    if j == 1:
      ctx.adds t[1], t[1], lo
      ctx.str t[1], r[2]      # r₂ finished
    else:
      ctx.adcs t[j], t[j], lo

  ctx.comment "final carry"
  ctx.adc t[N-1], t[N-1], xzr

template mulloadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
  ctx.mul u, lhs, rhs
  ctx.adds dst, u, addend
template mulloadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
  ctx.mul u, lhs, rhs
  ctx.adcs dst, u, addend

template mulhiadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
  ctx.umulh u, lhs, rhs
  ctx.adds dst, u, addend
template mulhiadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
  ctx.umulh u, lhs, rhs
  ctx.adcs dst, u, addend
template mulhiadd_ci(ctx, dst, lhs, rhs, addend) {.dirty.} =
  ctx.umulh u, lhs, rhs
  ctx.adc dst, u, addend

template sqr_row[N: static int](
      ctx: var Assembler_arm64,
      r, a: OperandArray, t: var OperandArray,
      coords: array[N-1, (int, int)],
      finalized_columns: set[range[0..255]], # set[range[3..2*N]],
      u: Operand) =

  doAssert N == a.len
  ctx.mov t[N], xzr
  t.rotateLeft()            # Our schema is big-endian (rotate right)
  ctx.mov t[N], xzr
  t.rotateLeft()            # but we are little-endian (rotateLeft)
  # Partial sums, for 2nd row 6 limbs:
  #  t₀ is r₃, t₁ is r₄, t₂ is r₅,
  #  t₃ is r₆, t₄ is r₇, t₅ is r₈

  for k in 0 ..< coords.len:
    let (i, j) = coords[k]
    if k == 0:
      ctx.mulloadd_co(t[0], a[i], a[j], t[0])
    else:
      ctx.mulloadd_cio(t[k], a[i], a[j], t[k])

    if i+j in finalized_columns:
      ctx.str t[k], r[i+j]

  ctx.adc t[N], xzr, xzr # Accumulate carry of the word

  for k in 0 ..< coords.len:
    let (i, j) = coords[k]
    if k == 0:
      ctx.mulhiadd_co(t[1], a[i], a[j], t[1])
    elif k == N-1:
      # 0xFFFFFFFF_FFFFFFFF² -> (hi: 0xFFFFFFFFFFFFFFFE, lo: 0x0000000000000001)
      # so even if there is a carry from the low limb in preceding
      #   ctx.adc t[N], xzr, xzr
      # we can't overflow here
      ctx.mulhiadd_ci(t[N], a[i], a[j], t[N])
    else:
      ctx.mulhiadd_cio(t[k+1], a[i], a[j], t[k+1])

    if i+j+1 in finalized_columns:
      ctx.str t[k+1], r[i+j+1]

template merge_diag_and_partsum(r, rr, a, u): untyped =
  let N = a.len
  # Doubling
  # r₀ = 0 as only a0*a0 would update it
  # r₂ₙ₋₁ is empty as only aₙ₋₁*aₙ₋₁ would update it
  ctx.adds rr[1], rr[1], rr[1]
  for i in 2 ..< 2*N-1:
    ctx.adcs rr[i], rr[i], rr[i]
  ctx.adc rr[2*N-1], xzr, xzr

  # Squaring diagonal
  ctx.mulloadd_co(rr[0], a[0], a[0], rr[0])
  for i in 1 ..< N:
    ctx.mulhiadd_cio(rr[2*i-1], a[i-1], a[i-1], rr[2*i-1])
    ctx.stp rr[2*i-2], rr[2*i-1], r[2*i-2]
    ctx.mulloadd_cio(rr[2*i], a[i], a[i], rr[2*i])
  ctx.mulhiadd_ci(rr[2*N-1], a[N-1], a[N-1], rr[2*N-1])
  ctx.stp rr[2*N-2], rr[2*N-1], r[2*N-2]

macro sqr_gen*[rLen, aLen: static int](r_PIR: var Limbs[rLen], a_REG: Limbs[aLen]) =
  ## Squaring
  ## r must have double the number of limbs of a
  ##
  ## Assumes r doesn't aliases a
  doAssert rLen == 2*aLen
  result = newStmtList()

  var ctx = init(Assembler_arm64, BaseType)
  let
    r = asmArray(r_PIR, rLen, PointerInReg, asmInput, memIndirect = memWrite)
    a = asmArray(a_REG, aLen, ElemsInReg, asmInput)

    tSym = ident"t"
    tSlots = aLen+1 # Extra for high words

    uSym = ident"u"
    u = asmValue(uSym, Reg, asmOutputEarlyClobber)

  var t = asmArray(tSym, tSlots, ElemsInReg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `tSym`{.noInit, used.}: array[`tSlots`, BaseType]
    var `uSym`{.noinit.}: BaseType

  # 1st part: Compute cross-products
  ctx.sqr_firstrow(r, a, t)
  if aLen == 4:
    ctx.sqr_row(
      r, a, t,
      coords = [(2, 1), (3, 1), (3, 2)],
      finalized_columns = {3..6},
      u
    )
  elif aLen == 6:
    ctx.sqr_row(
      r, a, t,
      coords = [(2, 1), (3, 1), (4, 1), (5, 1), (5, 2)],
      finalized_columns = {3..4},
      u
    )
    ctx.sqr_row(
      r, a, t,
      coords = [(3, 2), (4, 2), (4, 3), (5, 3), (5, 4)],
      finalized_columns = {5..10},
      u
    )

  result.add ctx.generate()

  # 2nd part: Double cross-products, compute diagonal squarings, sum all
  # We separate into 2 parts as loading `r` can take a lot of registers (2*aLen, with aLen usually 4 or 6)
  ctx = init(Assembler_arm64, BaseType)
  let
    rrSym = ident"rr"
    rr = asmArray(rrSym, rLen, ElemsInReg, asmInputOutputEarlyClobber)

  result.add quote do:
    let `rrSym`{.noinit, used.} = `r_PIR`

  merge_diag_and_partsum(r, rr, a, u)
  result.add ctx.generate()

func square_asm*[rLen, aLen: static int](r: var Limbs[rLen], a: Limbs[aLen]) =
  ## Multi-precision Squaring
  ## Assumes r doesn't alias a
  sqr_gen(r, a)