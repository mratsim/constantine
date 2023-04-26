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
  ../../../platforms/abstractions

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

static: doAssert UseASM_X86_64

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers
# {.localPassC:"-fomit-frame-pointer".}  # (enabled at -O1)

# Multiplication
# ------------------------------------------------------------
proc mulx_by_word(
       ctx: var Assembler_x86,
       r0: Operand,
       a, t: OperandArray,
       word0: Operand) =
  ## Multiply the `a[0..<N]` by `word`
  ## and store in `[t[n..1]:r0]`
  ## with [t[n..1]:r0] = tn, tn-1, ... t1, r0
  ## This assumes that t will be rotated left and so
  ## t1 is in t[0] and tn in t[n-1]
  doAssert a.len + 1 == t.len
  let N = a.len

  ctx.comment "  Outer loop i = 0, j=0 to " & $N

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # First limb
  ctx.mov rdx, word0
  ctx.`xor` rax, rax # Clear flags (important if steady state is skipped)
  ctx.mulx t[0], rax, a[0], rdx
  ctx.mov r0, rax

  # Steady state
  for j in 1 ..< N:
    ctx.mulx t[j], rax, a[j], rdx
    if j == 1:
      ctx.add t[j-1], rax
    else:
      ctx.adc t[j-1], rax

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.adc t[N-1], 0

proc mulaccx_by_word(
       ctx: var Assembler_x86,
       r: OperandArray,
       i: int,
       a, t: OperandArray,
       word: Operand) =
  ## Multiply the `a[0..<N]` by `word`
  ## and store in `[t[n..0]:r0]`
  ## with [t[n..0]:r0] = tn, tn-1, ... t1, r0
  ## This assumes that t will be rotated left and so
  ## t1 is in t[0] and tn in t[n-1]
  doAssert a.len + 1 == t.len
  let N = min(a.len, r.len)
  let hi = t[a.len]

  doAssert i != 0

  ctx.comment "  Outer loop i = " & $i & ", j in [0, " & $N & ")"
  ctx.mov rdx, word
  ctx.`xor` rax, rax # Clear flags

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # Steady state
  for j in 0 ..< N:
    ctx.mulx hi, rax, a[j], rdx
    ctx.adox t[j], rax
    if j == 0:
      ctx.mov r[i], t[j]
    if j == N-1:
      break
    ctx.adcx t[j+1], hi

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.mov  rdx, 0 # Set to 0 without clearing flags
  ctx.adcx hi, rdx
  ctx.adox hi, rdx

macro mulx_gen[rLen, aLen, bLen: static int](r_PIR: var Limbs[rLen], a_MEM: Limbs[aLen], b_MEM: Limbs[bLen]) =
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## Assumes r doesn't aliases a or b

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, rLen, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    a = asmArray(a_MEM, aLen, MemOffsettable, asmInput)
    b = asmArray(b_MEM, bLen, MemOffsettable, asmInput)

    # MULX requires RDX

    tSym = ident"t"
    tSlots = aLen+1 # Extra for high word

  var # If aLen is too big, we need to spill registers. TODO.
    t = asmArray(tSym, tSlots, ElemsInReg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `tSym`{.noInit, used.}: array[`tSlots`, BaseType]

  for i in 0 ..< min(rLen, bLen):
    if i == 0:
      ctx.mulx_by_word(
        r[0],
        a, t,
        b[0])
    else:
      ctx.mulaccx_by_word(
        r, i,
        a, t,
        b[i])

      t.rotateLeft()

  # Copy upper-limbs to result
  for i in b.len ..< min(a.len+b.len, rLen):
    ctx.mov r[i], t[i-b.len]

  # Zero the extra
  if aLen+bLen < rLen:
    ctx.`xor` rax, rax
    for i in aLen+bLen ..< rLen:
      ctx.mov r[i], rax

  # Codegen
  result.add ctx.generate()

func mul_asm_adx*[rLen, aLen, bLen: static int](
       r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mulx_gen(r, a, b)

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
# The multiplication strategy is to mulx+adox+adcx on a diagonal
# handling both carry into next mul and partial sums carry into t
# then saving the lowest word in t into r.
#
# We want `t` of size N+1 with N the number of limbs just like multiplication,
# and reuse the multiplication algorithm
# this means that we need to reorganize scheduling like so to maximize utilization
#
#                    a₃ a₂ a₁ a₀
# *                  a₃ a₂ a₁ a₀
# ------------------------------
#                          a₀*a₀
#                    a₁*a₁
#               a₂*a₂
#          a₃*a₃
#
#                 a₂*a₁ a₁*a₀   |
#              a₃*a₁ a₂*a₀      | * 2
#           a₃*a₂ a₃*a₀         |
#
#        r₇ r₆ r₅ r₄ r₃ r₂ r₁ r₀
#
# Note that while processing the second diagonal we do
# a₂*a₁ then a₃*a₁ then we change word to a₃*a₂.
#
# We want to use an index as much as possible in the diagonal.
# - There is probably a clever solution using graphs
#   - https://en.wikipedia.org/wiki/Longest_path_problem
#   - https://en.wikipedia.org/wiki/Longest_increasing_subsequence
# - or polyhedral optimization: http://playground.pollylabs.org/
#
# but we only care about 4*4 and 6*6 at the moment, for 6*6 the schedule is
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

template merge_diag_and_partsum(r, a, hi, lo, zero, i): untyped =
  ctx.mulx hi, lo, a[i], rdx
  if i+1 < a.len:
    ctx.mov rdx, a[i+1]     # prepare next iteration
  if i != 0:
    ctx.adox lo, r[2*i]
    ctx.adcx lo, r[2*i]
  ctx.mov r[2*i], lo
  if i+1 < a.len:
    ctx.adox hi, r[2*i+1]
    ctx.adcx hi, r[2*i+1]
  else: # finish carry chain
    ctx.adox hi, zero
    ctx.adcx hi, zero
  ctx.mov r[2*i+1], hi

func sqrx_gen4L(ctx: var Assembler_x86, r, a: OperandArray, t: var OperandArray) =
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

  # First diagonal. a₀ * [aₙ₋₁ .. a₂ a₁]
  # ------------------------------------
  # This assumes that t will be rotated left and so
  # t1 is in t[0] and tn in t[n-1]
  ctx.mov rdx, a[0]
  ctx.`xor` rax, rax # clear flags

  ctx.comment "a₁*a₀"
  ctx.mulx t[1], rax, a[1], rdx    # t₁ partial sum of r₂
  ctx.mov  r[1], rax

  ctx.comment "a₂*a₀"
  ctx.mulx t[2], rax, a[2], rdx    # t₂ partial sum of r₃
  ctx.add  t[1], rax
  ctx.mov  r[2], t[1]              # r₂ finished

  ctx.comment "a₃*a₀"
  ctx.mulx t[3], rax, a[3], rdx    # t₃ partial sum of r₄
  ctx.mov rdx, a[1]                # prepare next iteration
  ctx.adc t[2], rax
  ctx.adc t[3], 0                  # final carry in r₄

  # Second diagonal, a₂*a₁, a₃*a₁, a₃*a₂
  # ------------------------------------

  ctx.`xor` t[a.len], t[a.len]     # Clear flags and upper word
  t.rotateLeft()                   # Our schema are big-endian (rotate right)
  t.rotateLeft()                   # but we are little-endian (rotateLeft)
  # Partial sums: t₀ is r₃, t₁ is r₄, t₂ is r₅, t₃ is r₆
  let hi = t[a.len]

  ctx.comment "a₂*a₁"
  ctx.mulx hi, rax, a[2], rdx
  ctx.adox t[0], rax               # t₀ partial sum r₃
  ctx.mov r[3], t[0]               # r₃ finished
  ctx.adcx t[1], hi                # t₁ partial sum r₄

  ctx.comment "a₃*a₁"
  ctx.mulx hi, rax, a[3], rdx
  ctx.mov rdx, a[2]                # prepare next iteration
  ctx.adox t[1], rax               # t₁ partial sum r₄
  ctx.mov r[4], t[1]               # r₄ finished
  ctx.adcx t[2], hi                # t₂ partial sum r₅

  ctx.comment "a₃*a₂"
  ctx.mulx hi, rax, a[3], rdx
  ctx.mov  rdx, 0                  # Set to 0 without clearing flags
  ctx.adox t[2], rax               # t₂ partial sum r₅
  ctx.mov r[5], t[2]               # r₅ finished
  ctx.adcx hi, rdx                 # Terminate carry chains
  ctx.adox hi, rdx
  ctx.mov rdx, a[0]                # prepare next iteration
  ctx.mov r[6], hi                 # r₆ finished

  # a[i] * a[i] + 2 * r[2n-1 .. 1]
  # ------------------------------
  #
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

  # a₀ in RDX
  var
    hi1 = hi
    lo1 = rax
  var
    hi2 = t[1]
    lo2 = t[0]

  ctx.comment "ai*ai + 2*r[1..<2*n-2]"
  let zero = t[2]
  ctx.`xor` zero, zero             # clear flags, break dependency chains

  merge_diag_and_partsum(r, a, hi1, lo1, zero, 0)
  merge_diag_and_partsum(r, a, hi2, lo2, zero, 1)
  merge_diag_and_partsum(r, a, hi1, lo1, zero, 2)
  merge_diag_and_partsum(r, a, hi2, lo2, zero, 3)


func sqrx_gen6L(ctx: var Assembler_x86, r, a: OperandArray, t: var OperandArray) =
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

  # First diagonal. a₀ * [aₙ₋₁ .. a₂ a₁]
  # ------------------------------------
  # This assumes that t will be rotated left and so
  # t1 is in t[0] and tn in t[n-1]
  ctx.mov rdx, a[0]
  ctx.`xor` rax, rax # clear flags

  ctx.comment "a₁*a₀"
  ctx.mulx t[1], rax, a[1], rdx    # t₁ partial sum of r₂
  ctx.mov  r[1], rax

  ctx.comment "a₂*a₀"
  ctx.mulx t[2], rax, a[2], rdx    # t₂ partial sum of r₃
  ctx.add  t[1], rax
  ctx.mov  r[2], t[1]              # r₂ finished

  ctx.comment "a₃*a₀"
  ctx.mulx t[3], rax, a[3], rdx    # t₃ partial sum of r₄
  ctx.adc t[2], rax

  ctx.comment "a₄*a₀"
  ctx.mulx t[4], rax, a[4], rdx    # t₄ partial sum of r₅
  ctx.adc t[3], rax

  ctx.comment "a₅*a₀"
  ctx.mulx t[5], rax, a[5], rdx    # t₅ partial sum of r₆
  ctx.mov rdx, a[1]                # prepare next iteration
  ctx.adc t[4], rax
  ctx.adc t[5], 0                  # final carry in r₆

  # Second diagonal, a₂*a₁, a₃*a₁, a₄*a₁, a₅*a₁, a₅*a₂
  # --------------------------------------------------

  ctx.`xor` t[a.len], t[a.len]     # Clear flags and upper word
  t.rotateLeft()                   # Our schema are big-endian (rotate right)
  t.rotateLeft()                   # but we are little-endian (rotateLeft)
  # Partial sums: t₀ is r₃, t₁ is r₄, t₂ is r₅, t₃ is r₆, ...
  block:
    let hi = t[a.len]

    ctx.comment "a₂*a₁"
    ctx.mulx hi, rax, a[2], rdx
    ctx.adox t[0], rax               # t₀ partial sum r₃
    ctx.mov r[3], t[0]               # r₃ finished
    ctx.adcx t[1], hi                # t₁ partial sum r₄

    ctx.comment "a₃*a₁"
    ctx.mulx hi, rax, a[3], rdx
    ctx.adox t[1], rax               # t₁ partial sum r₄
    ctx.mov r[4], t[1]               # r₄ finished
    ctx.adcx t[2], hi                # t₂ partial sum r₅

    ctx.comment "a₄*a₁"
    ctx.mulx hi, rax, a[4], rdx
    ctx.adox t[2], rax               # t₂ partial sum r₅
    ctx.adcx t[3], hi                # t₃ partial sum r₆

    ctx.comment "a₅*a₁"
    ctx.mulx hi, rax, a[5], rdx
    ctx.mov rdx, a[2]                # prepare next iteration
    ctx.adox t[3], rax               # t₃ partial sum r₆
    ctx.adcx t[4], hi                # t₄ partial sum r₇

    ctx.comment "a₅*a₂"
    ctx.mulx t[5], rax, a[5], rdx
    ctx.mov hi, 0                    # Set to 0 `hi` (== t[6] = r₉) without clearing flags
    ctx.adox t[4], rax               # t₄ partial sum r₇
    ctx.adcx t[5], hi                # t₅ partial sum r₈, terminate carry chains
    ctx.adox t[5], hi

  # Third diagonal, a₃*a₂, a₄*a₂, a₄*a₃, a₅*a₃, a₅*a₄
  # --------------------------------------------------
  t.rotateLeft()
  t.rotateLeft()
  # Partial sums: t₀ is r₅, t₁ is r₆, t₂ is r₇, t₃ is r₈, t₄ is r₉, t₅ is r₁₀
  # t₄ is r₉ and was set to zero, a₂ in RDX
  block:
    let hi = t[a.len]
    ctx.`xor` hi, hi                 # t₅ is r₁₀ = 0, break dependency chains

    ctx.comment "a₃*a₂"
    ctx.mulx hi, rax, a[3], rdx
    ctx.adox t[0], rax               # t₀ partial sum r₅
    ctx.mov r[5], t[0]               # r₅ finished
    ctx.adcx t[1], hi                # t₁ partial sum r₆

    ctx.comment "a₄*a₂"
    ctx.mulx hi, rax, a[4], rdx
    ctx.mov rdx, a[3]                # prepare next iteration
    ctx.adox t[1], rax               # t₁ partial sum r₆
    ctx.mov r[6], t[1]               # r₆ finished
    ctx.adcx t[2], hi                # t₂ partial sum r₇

    ctx.comment "a₄*a₃"
    ctx.mulx hi, rax, a[4], rdx
    ctx.adox t[2], rax               # t₂ partial sum r₇
    ctx.mov r[7], t[2]               # r₇ finished
    ctx.adcx t[3], hi                # t₃ partial sum r₈

    ctx.comment "a₅*a₃"
    ctx.mulx hi, rax, a[5], rdx
    ctx.mov rdx, a[4]                # prepare next iteration
    ctx.adox t[3], rax               # t₃ partial sum r₈
    ctx.mov r[8], t[3]               # r₈ finished
    ctx.adcx t[4], hi                # t₄ partial sum r₉ (was zero)

    ctx.comment "a₅*a₄"
    ctx.mulx hi, rax, a[5], rdx
    ctx.mov  rdx, 0                  # Set to 0 without clearing flags
    ctx.adox t[4], rax               # t₄ partial sum r₉
    ctx.mov r[9], t[4]               # r₉ finished
    ctx.adcx hi, rdx                 # Terminate carry chains
    ctx.adox hi, rdx
    ctx.mov rdx, a[0]                # prepare next iteration
    ctx.mov r[10], hi                # r₁₀ finished

  # a[i] * a[i] + 2 * r[2n-1 .. 1]
  # -------------------------------------
  #
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

  # a₀ in RDX
  var
    hi1 = t[a.len]
    lo1 = rax
  var
    hi2 = t[1]
    lo2 = t[0]

  ctx.comment "ai*ai + 2*r[1..<2*n-2]"
  let zero = t[2]
  ctx.`xor` zero, zero             # clear flags, break dependency chains

  merge_diag_and_partsum(r, a, hi1, lo1, zero, 0)
  merge_diag_and_partsum(r, a, hi2, lo2, zero, 1)
  merge_diag_and_partsum(r, a, hi1, lo1, zero, 2)
  merge_diag_and_partsum(r, a, hi2, lo2, zero, 3)
  merge_diag_and_partsum(r, a, hi1, lo1, zero, 4)
  merge_diag_and_partsum(r, a, hi2, lo2, zero, 5)

macro sqrx_gen*[rLen, aLen: static int](r_PIR: var Limbs[rLen], a_MEM: Limbs[aLen]) =
  ## Squaring
  ## `a` and `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len * 2
  ## The result will be truncated, i.e. it will be
  ## a² (mod (2^WordBitWidth)^r.limbs.len)
  ##
  ## Assumes r doesn't aliases a
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    # Register count with 6 limbs:
    # r + a + rax + rdx = 4
    # t = 2 * a.len = 12
    # We use the full x86 register set.

    r = asmArray(r_PIR, rLen, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    a = asmArray(a_MEM, aLen, MemOffsettable, asmInput)

    # MULX requires RDX
    tSym = ident"t"
    tSlots = aLen+1 # Extra for high word

  var # If aLen is too big, we need to spill registers. TODO.
    t = asmArray(tSym, tSlots, ElemsInReg, asmOutputEarlyClobber)

  # Prologue
  # -------------------------------
  result.add quote do:
    var `tSym`{.noInit, used.}: array[`tSlots`, BaseType]

  if aLen == 4:
    ctx.sqrx_gen4L(r, a, t)
  elif aLen == 6:
    ctx.sqrx_gen6L(r, a, t)
  else:
    error: "Not implemented"

  # Codegen
  result.add ctx.generate()

func square_asm_adx*[rLen, aLen: static int](r: var Limbs[rLen], a: Limbs[aLen]) =
  ## Multi-precision Squaring
  ## Assumes r doesn't alias a
  sqrx_gen(r, a)
