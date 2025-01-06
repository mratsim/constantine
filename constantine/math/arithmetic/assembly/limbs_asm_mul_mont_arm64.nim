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
#        Assembly implementation of finite fields
#
# ############################################################

static: doAssert UseASM_ARM64

# Montgomery multiplication
# ------------------------------------------------------------

macro mulMont_CIOS_sparebit_gen[N: static int](
        r_PIR: var Limbs[N], a_PIR, b_PIR,
        M_PIR: Limbs[N], m0ninv_REG: BaseType,
        lazyReduce: static bool): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ##
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 1 (i.e. less than 0b01111...1111)
  ## https://hackmd.io/@gnark/modular_multiplication

  result = newStmtList()
  var ctx = init(Assembler_arm64, BaseType)

  let
    r = asmArray(r_PIR, N, PointerInReg, asmInput, memIndirect = memWrite)
    b = asmArray(b_PIR, N, PointerInReg, asmInput, memIndirect = memRead)

    tSym = ident"t"
    t = asmArray(tSym, N, ElemsInReg, asmOutputEarlyClobber)
    m0ninv = asmValue(m0ninv_REG, Reg, asmInput)
    aSym = ident"A"
    A = asmValue(aSym, Reg, asmOutputEarlyClobber)
    biSym = ident"bi"
    bi = asmValue(biSym, Reg, asmOutputEarlyClobber)

    aaSym = ident"aa"
    aa = asmArray(aaSym, N, ElemsInReg, asmInputOutput) # used as buffer for final substraction
    mmSym = ident"mm"
    mm = asmArray(mmSym, N, ElemsInReg, asmInput)
    mSym = ident"m"
    m = asmValue(mSym, Reg, asmOutputEarlyClobber)

    uSym = ident"u"
    vSym = ident"v"

  var # Break dependencies chain
    u = asmValue(uSym, Reg, asmOutputEarlyClobber)
    v = asmValue(vSym, Reg, asmOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `tSym`{.noinit, used.}, `aaSym`{.noinit, used.}, `mmSym`{.noInit, used.}: typeof(`r_PIR`)
    var `aSym`{.noinit.}, `biSym`{.noInit.}, `mSym`{.noinit.}: BaseType
    var `uSym`{.noinit.}, `vSym`{.noInit.}: BaseType

    `aaSym` = `a_PIR`
    `mmSym` = `M_PIR`

  # Algorithm
  # -----------------------------------------
  #
  # On x86, with a single carry chain and a spare bit:
  #
  # for i=0 to N-1
  #   (A, t[0]) <- a[0] * b[i] + t[0]
  #    m        <- (t[0] * m0ninv) mod 2ʷ
  #   (C, _)    <- m * M[0] + t[0]
  #   for j=1 to N-1
  #     (A, t[j])   <- a[j] * b[i] + A + t[j]
  #     (C, t[j-1]) <- m * M[j] + C + t[j]
  #
  #   t[N-1] = C + A
  #
  # with MULX, ADCX, ADOX dual carry chains
  #
  # for i=0 to N-1
  #   for j=0 to N-1
  # 		(A,t[j])  := t[j] + a[j]*b[i] + A
  #   m := t[0]*m0ninv mod W
  # 	C,_ := t[0] + m*M[0]
  # 	for j=1 to N-1
  # 		(C,t[j-1]) := t[j] + m*M[j] + C
  #   t[N-1] = C + A
  #
  # In our case, we only have a single carry flag
  # but we have a lot of registers
  #
  # Hence we can use the dual carry chain approach
  # one chain after the other instead of interleaved like on x86.

  # TODO: we don't do complicated prefetching
  #       as the algorithm is already complex
  #       we assume that the instruction fetch-decode-execute
  #       has enough look-ahead to prefetch next loop inputs in memory
  #       while waiting for current inputs

  template mulloadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul u, lhs, rhs
    ctx.adds dst, addend, u
    swap(u, v)
  template mulloadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.mul u, lhs, rhs
    ctx.adcs dst, addend, u
    swap(u, v)

  template mulhiadd_co(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adds dst, addend, u
    swap(u, v)
  template mulhiadd_cio(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adcs dst, addend, u
    swap(u, v)
  template mulhiadd_ci(ctx, dst, lhs, rhs, addend) {.dirty.} =
    ctx.umulh u, lhs, rhs
    ctx.adc dst, addend, u
    swap(u, v)

  doAssert N >= 2

  for i in 0 ..< N:
    # Multiplication
    # -------------------------------
    #   for j=0 to N-1
    # 		(A,t[j])  := t[j] + a[j]*b[i] + A
    #
    # for 4 limbs, implicit column-wise carries
    #
    # t[0]     = t[0] + (a[0]*b[i]).lo
    # t[1]     = t[1] + (a[1]*b[i]).lo + (a[0]*b[i]).hi
    # t[2]     = t[2] + (a[2]*b[i]).lo + (a[1]*b[i]).hi
    # t[3]     = t[3] + (a[3]*b[i]).lo + (a[2]*b[i]).hi
    # overflow =                         (a[3]*b[i]).hi
    #
    # or
    #
    # t[0]     = t[0] + (a[0]*b[i]).lo
    # t[1]     = t[1] + (a[0]*b[i]).hi + (a[1]*b[i]).lo
    # t[2]     = t[2] + (a[2]*b[i]).lo + (a[1]*b[i]).hi
    # t[3]     = t[3] + (a[2]*b[i]).hi + (a[3]*b[i]).lo
    # overflow =    carry              + (a[3]*b[i]).hi
    #
    # Depending if we chain lo/hi or even/odd
    # The even/odd carry chain is more likely to be optimized via μops-fusion
    # as it's common to compute the full product. That said:
    # - it's annoying if the number of limbs is odd with edge conditions.
    # - fusion is not listed https://dougallj.github.io/applecpu/firestorm.html
    #   "Other tested patterns are not fused, including adrp + add, mov + movk, mul + umulh, and udiv + msub."

    ctx.mov A, xzr
    ctx.ldr bi, b[i]
    if i == 0:
      for j in 0 ..< N:
        ctx.mul t[j], aa[j], bi
    else:
      ctx.mulloadd_co(t[0], aa[0], bi, t[0])
      for j in 1 ..< N:
        ctx.mulloadd_cio(t[j], aa[j], bi, t[j])
      ctx.adc A, xzr, xzr                        # assumes N > 1
    ctx.mulhiadd_co(t[1], aa[0], bi, t[1])       # assumes N > 1
    for j in 2 ..< N:
      ctx.mulhiadd_cio(t[j], aa[j-1], bi, t[j])
    ctx.mulhiadd_ci(A, aa[N-1], bi, A)

    # Reduction
    # -------------------------------
    #   m := t[0]*m0ninv mod W
    #
    # 	C,_ := t[0] + m*M[0]
    # 	for j=1 to N-1
    # 		(C,t[j-1]) := t[j] + m*M[j] + C
    #   t[N-1] = C + A
    #
    # for 4 limbs, implicit column-wise carries
    #    _  = t[0] + (m*M[0]).lo
    #  t[0] = t[1] + (m*M[1]).lo + (m*M[0]).hi
    #  t[1] = t[2] + (m*M[2]).lo + (m*M[1]).hi
    #  t[2] = t[3] + (m*M[3]).lo + (m*M[2]).hi
    #  t[3] = A + carry          + (m*M[3]).hi
    #
    # or
    #
    #    _  = t[0] + (m*M[0]).lo
    #  t[0] = t[1] + (m*M[0]).hi + (m*M[1]).lo
    #  t[1] = t[2] + (m*M[2]).lo + (m*M[1]).hi
    #  t[2] = t[3] + (m*M[2]).hi + (m*M[3]).lo
    #  t[3] = A + carry          + (m*M[3]).hi

    ctx.mul m, t[0], m0ninv
    ctx.mul u, m, mm[0]
    ctx.cmn t[0], u         # TODO: bad latency chain, hopefully done parallel to prev loop
    swap(u, v)

    for j in 1 ..< N:
      ctx.mulloadd_cio(t[j-1], m, mm[j], t[j])
    ctx.adc t[N-1], A, xzr

    # assumes N > 1
    ctx.mulhiadd_co(t[0], m, mm[0], t[0])
    for j in 1 ..< N-1:
      ctx.mulhiadd_cio(t[j], m, mm[j], t[j])
    ctx.mulhiadd_ci(t[N-1], m, mm[N-1], t[N-1])

  if lazyReduce:
    for i in 0 ..< N:
      ctx.str t[i], r[i]
  else:
    # Final substraction
    # we reuse the aa buffer
    template s: untyped = aa

    for i in 0 ..< N:
      if i == 0:
        ctx.subs s[i], t[i], mm[i]
      else:
        ctx.sbcs s[i], t[i], mm[i]

    # if carry clear t < M, so pick t
    for i in 0 ..< N:
      ctx.csel t[i], t[i], s[i], cc
      ctx.str t[i], r[i]

  result.add ctx.generate()

func mulMont_CIOS_sparebit_asm*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType, lazyReduce: static bool = false) =
  ## Constant-time Montgomery multiplication
  ## If "lazyReduce" is set
  ## the result is in the range [0, 2M)
  ## otherwise the result is in the range [0, M)
  ##
  ## This procedure can only be called if the modulus doesn't use the full bitwidth of its underlying representation
  r.mulMont_CIOS_sparebit_gen(a, b, M, m0ninv, lazyReduce)