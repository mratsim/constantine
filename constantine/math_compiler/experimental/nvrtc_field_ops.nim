import std / strformat

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions {.all.},
  constantine/platforms/abis/nvidia_abi,
  constantine/math_compiler/experimental/runtime_compile,
  constantine/serialization/io_limbs,
  constantine/named/deriv/precompute

import constantine/platforms/abstractions
export negInvModWord

import std / macros
macro asm_comment*(msg: typed): untyped =
  var msgLit = nnkTripleStrLit.newNimNode()
  msgLit.strVal = "\"// " & msg.strVal & "\""
  result = nnkAsmStmt.newTree(newEmptyNode(), msgLit)

template bigintToUint32Limbs*(b: typed): untyped =
  let limbs = b.limbs
  when CTT_32:
    var res = default(array[b.limbs.len, uint32])
    for i in 0 ..< limbs.len:
      res[i] = limbs[i].uint32
  else:
    {.error: "Logic to convert 64 bit limbs to 32 bit limbs at compile time still unfinished.".}
    # need twice as many limbs to go from 64bit to 32bit
    ## XXX: Use number of bits required to check if the
    ## last limbs needs to be dropped
    var res = default(array[b.limbs.len * 2, uint32])
    for i in 0 ..< b.limbs.len:
      res[i*2]     = limbs[i].uint32
      res[i*2 + 1] = (limbs[i] shr 32).uint32
  res

template defBigInt*(N: typed): untyped {.dirty.} =
  # Utility for add with carry operations
  type
    BigInt = object
      limbs: array[N, uint32]
  template `[]`(x: BigInt, idx: int): untyped = x.limbs[idx]
  template `[]=`(x: BigInt, idx: int, val: uint32): untyped = x.limbs[idx] = val
  template `[]`(x: ptr BigInt, idx: int): untyped = x[].limbs[idx]
  template `[]=`(x: ptr BigInt, idx: int, val: uint32): untyped = x[].limbs[idx] = val

  template len(x: BigInt): int = N

template defPtxHelpers*(): untyped {.dirty.} =
  ## Note: the below would just be generated from a macro of course, similar to
  ## `constantine/platforms/llvm/asm_nvidia.nim`.

  ## IMPORTANT NOTE: For the below procs that define inline PTX statements:
  ## It is very important (in the current implementation) that each of the
  ## return values is marked `{.volatile.}` so that the NVRTC compiler does not
  ## eliminate any of the function calls. Despite them being `__forceinline__`,
  ## it might do such a thing if the return value is not used.

  proc add_cio(a, b: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"addc.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc add_ci(a, b: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"addc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc add_co(a, b: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"add.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc sub_bo(a, b: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"sub.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc sub_bi(a, b: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"subc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc sub_bio(a, b: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"subc.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc slct(a, b: uint32, pred: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
# "slct.s32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(pred)
    asm """
"slct.u32.s32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(pred)
"""
    return res

  proc mul_lo(a, b: uint32): uint32 {.device, forceinline.} =
    ## Returns the lower 32 bit of the uint32 multiplication, i.e.
    ## behaves as unsigned multiplication modulo 2^32 (matches LLVM `mul`).
    var res {.volatile.}: uint32
    asm """
"mul.lo.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc mul_hi(a, b: uint32): uint32 {.device, forceinline.} =
    ## Returns the upper 32 bit of the uint32 multiplication
    var res {.volatile.}: uint32
    asm """
"mul.hi.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res


  # r <- a * b + c
  proc mulloadd(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"mad.lo.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  proc mulloadd_co(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"mad.lo.cc.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  proc mulloadd_ci(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"madc.lo.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  proc mulloadd_cio(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"madc.lo.cc.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  # r <- (a * b) >> 32 + c
  # r <- (a * b) >> 64 + c
  proc mulhiadd(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"mad.hi.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  proc mulhiadd_co(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"mad.hi.cc.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  proc mulhiadd_ci(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"madc.hi.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

  proc mulhiadd_cio(a, b, c: uint32): uint32 {.device, forceinline.} =
    var res {.volatile.}: uint32
    asm """
"madc.hi.cc.u32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(c)
"""
    return res

template defCoreFieldOps*(T: typed): untyped {.dirty.} =
  # Need to get the limbs & spare bits data in a static context
  template getM0ninv(): untyped = static: T.getModulus().negInvModWord().uint32
  template spareBits(): untyped = static: (BigInt().limbs.len * WordSize - T.bits())

  ## TODO: avoid the explicit array size here
  proc toBigInt(limbs: array[1, uint32]): BigInt {.nimonly.} =
    result.limbs = limbs

  const M = toBigInt(bigintToUint32Limbs(T.getModulus))
  const MontyOne = toBigInt(bigintToUint32Limbs(T.getMontyOne))
  const PP1D2 = toBigInt(bigintToUint32Limbs(T.getPrimePlus1div2))
  const M0NInv = getM0ninv()

  proc finalSubMayOverflow(a, M: BigInt): BigInt {.device.} =
    ## If a >= Modulus: r <- a-M
    ## else:            r <- a
    ##
    ## This is constant-time straightline code.
    ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
    ##
    ## To be used when the final substraction can
    ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)
    var scratch: BigInt = BigInt()

    # Contains 0x0001 (if overflowed limbs) or 0x0000
    let overflowedLimbs = add_ci(0'u32, 0'u32)

    # Now substract the modulus, and test a < M with the last borrow
    scratch[0] = sub_bo(a[0], M[0])
    staticFor i, 1, N:
      scratch[i] = sub_bio(a[i], M[i])

    # 1. if `overflowedLimbs`, underflowedModulus >= 0
    # 2. if a >= M, underflowedModulus >= 0
    # if underflowedModulus >= 0: a-M else: a
    # TODO: predicated mov instead?
    ## TODO: Fix this. `slct` needs a negative value for the else branch
    let underflowedModulus = sub_bi(overflowedLimbs, 0'u32)

    var r: BigInt = BigInt()
    staticFor i, 0, N:
      r[i] = slct(scratch[i], a[i], underflowedModulus.int32)
    return r

  proc finalSubNoOverflow(a, M: BigInt): BigInt {.device.} =
    ## If a >= Modulus: r <- a-M
    ## else:            r <- a
    ##
    ## This is constant-time straightline code.
    ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
    ##
    ## To be used when the modulus does not use the full bitwidth of the storing words
    ## (say using 255 bits for the modulus out of 256 available in words)
    var scratch: BigInt = BigInt()

    # Now substract the modulus, and test a < M with the last borrow
    scratch[0] = sub_bo(a[0], M[0])
    staticFor i, 1, N:
      scratch[i] = sub_bio(a[i], M[i])

    # If it underflows here, `a` was smaller than the modulus, which is what we want
    ## TODO: Fix this. `slct` needs a negative value for the else branch
    let underflowedModulus = sub_bi(0'u32, 0'u32)

    var r: BigInt = BigInt()
    staticFor i, 0, N:
      r[i] = slct(scratch[i], a[i], underflowedModulus.int32)
    return r

  proc modadd(a, b, M: BigInt): BigInt {.device.} =
    ## Generate an optimized modular addition kernel
    ## with parameters `a, b, modulus: Limbs -> Limbs`
    # try to add two bigints
    var t = BigInt() # temporary

    t[0] = add_co(a[0], b[0])
    staticFor i, 1, N:
      t[i] = add_cio(a[i], b[i])

    # can use `when` of course!
    when spareBits() >= 1: # if spareBits() >= 1: # would also work
      t = finalSubNoOverflow(t, M)
    else:
      t = finalSubMayOverflow(t, M)

    return t

  proc modsub(a, b, M: BigInt): BigInt {.device.} =
    ## Generate an optimized modular substraction kernel
    ## with parameters `a, b, modulus: Limbs -> Limbs`
    var t = BigInt()

    t[0] = sub_bo(a[0], b[0])
    staticFor i, 1, a.len:
      t[i] = sub_bio(a[i], b[i])

    let underflowMask = sub_bi(0'u32, 0'u32)

    # If underflow
    # TODO: predicated mov instead?
    var maskedM: BigInt = BigInt()
    staticFor i, 0, N:
      maskedM[i] = M[i] and underflowMask

    t[0] = add_co(t[0], maskedM[0])
    staticFor i, 1, a.len-1:
      t[i] = add_cio(t[i], maskedM[i])
    when N > 1:
      t[N-1] = add_ci(t[N-1], maskedM[N-1])

    return t

  proc mtymul_CIOS_sparebit(a, b, M: BigInt, finalReduce: bool): BigInt {.device.} =
    ## Generate an optimized modular multiplication kernel
    ## with parameters `a, b, modulus: Limbs -> Limbs`
    var t: BigInt = BigInt()
    template m0ninv: untyped = M0NInv

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
    # and a multiply-accumulate instruction
    #
    # Hence we can use the dual carry chain approach
    # one chain after the other instead of interleaved like on x86.

    when N > 1:
      staticFor i, 0, N:
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
        # - GPUs are RISC architectures and unlikely to have clever instruction rescheduling logic
        let bi = b[i]
        var A = 0'u32

        if i == 0:
          staticFor j, 0, N:
            t[j] = mul_lo(a[j], bi)
        else:
          t[0] = mulloadd_co(a[0], bi, t[0])
          staticFor j, 1, N:
            t[j] = mulloadd_cio(a[j], bi, t[j])
          A = add_ci(0'u32, 0'u32)          # assumes N > 1
        t[1] = mulhiadd_co(a[0], bi, t[1])  # assumes N > 1
        staticFor j, 2, N:
          t[j] = mulhiadd_cio(a[j-1], bi, t[j])
        A = mulhiadd_ci(a[N-1], bi, A)
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

        let m = mul_lo(t[0], m0ninv)
        let _ = mulloadd_co(m, M[0], t[0])
        staticFor j, 1, N:
          t[j-1] = mulloadd_cio(m, M[j], t[j])
        t[N-1] = add_ci(A, 0)
        # assumes N > 1
        t[0] = mulhiadd_co(m, M[0], t[0])
        staticFor j, 1, N-1:
          t[j] = mulhiadd_cio(m, M[j], t[j])
        t[N-1] = mulhiadd_ci(m, M[N-1], t[N-1])
    else: # single limb, e.g. BabyBear (N=1)
      # 1. Compute t = a * b (low and high, emulates lagged code in N limb branch)
      # 2. Compute m = t * m0ninv mod 2^32
      # 3. Compute t = (t + m*M) >> 32

      # Step 1: t = a * b
      let t0 = mul_lo(a[0], b[0]) # lower 32 bit
      let t1 = mul_hi(a[0], b[0]) # upper 32 bit

      # Step 2: m = t * m0ninv mod 2^32
      let m = mul_lo(t0, m0ninv)

      # Step 3: t = (t + m*M) >> 32
      let _ = mulloadd_co(m, M[0], t0) # Low word discarded, but calc for possible carry
      t[0] = mulhiadd_ci(m, M[0], t1)

    if finalReduce:
      t = finalSubNoOverflow(t, M)

    return t
  ##  More general field operations

  proc setZero(a: var BigInt) {.device.} =
    ## Sets all limbs of the field element to zero in place
    # Zero all limbs
    for i in 0 ..< N:
      a[i] = 0'u32

  proc setOne(a: var BigInt) {.device.} =
    ## Sets the field element to one in Montgomery form
    ## For a field element to be valid in Montgomery form,
    ## we need x · R mod M with R = 2^(WordBitWidth * numWords)
    template montyOne: untyped = MontyOne # Get the Montgomery form of 1 from static context
    # Copy the Montgomery form of 1
    for i in 0 ..< N:
      a[i] = montyOne[i] # .uint32

  proc add(r: var BigInt, a, b: BigInt) {.device.} =
    ## Addition of two finite field elements stored in `a` and `b`.
    ## The result is stored in `r`.
    r = modadd(a, b, M)

  proc sub(r: var BigInt, a, b: BigInt) {.device.} =
    ## Subtraction of two finite field elements stored in `a` and `b`.
    ## The result is stored in `r`.
    r = modsub(a, b, M)

  proc mul(r: var BigInt, a, b: BigInt) {.device.} =
    ## Multiplication of two finite field elements stored in `a` and `b`.
    ## The result is stored in `r`.
    r = mtymul_CIOS_sparebit(a, b, M, true)

  proc ccopy(a: var BigInt, b: BigInt, condition: bool) {.device.} =
    ## Conditional copy in CUDA
    ## If condition is true: b is copied into a
    ## If condition is false: a is left unmodified
    ##
    ## Note: This is constant-time
    # Use selp instruction for constant-time selection:
    # if condition then b else a
    ## XXX: add support for `IfExpr`! Requires though.
    var cond: int32
    if condition:
      cond = 1'i32
    else:
      cond = -1'i32 # `slct` checks for `>= 0` as the true branch!
    for i in 0 ..< N:
      a[i] = slct(b[i], a[i], cond)

  proc csetZero(r: var BigInt, condition: bool) {.device.} =
    ## Conditionally set `r` to zero in CUDA
    ##
    ## Note: This is constant-time
    var t = BigInt()
    t.setZero()
    r.ccopy(t, condition)

  proc csetOne(r: var BigInt, condition: bool) {.device.} =
    ## Conditionally set `r` to one in CUDA
    ##
    ## Note: This is constant-time
    template mOne: untyped = MontyOne
    r.ccopy(mOne, condition)

  proc cadd(r: var BigInt, a: BigInt, condition: bool) {.device.} =
    ## Conditionally add `a` to `r` in place in CUDA.
    ##
    ## Note: This is constant-time
    var t = BigInt()
    t.add(r, a)
    r.ccopy(t, condition)

  proc csub(r: var BigInt, a: BigInt, condition: bool) {.device.} =
    ## Conditionally subtract `a` from `r` in place in CUDA.
    ##
    ## Note: This is constant-time
    var t = BigInt()
    t.sub(r, a)
    r.ccopy(t, condition)

  proc doubleElement(r: var BigInt, a: BigInt) {.device.} =
    ## Double `a` and store it in `r` in CUDA.
    ##
    ## Note: This is constant-time
    r.add(a, a)

  proc nsqr(r: var BigInt, a: BigInt, count: int) {.device.} =
    ## Performs `nsqr`, that is multiple squarings of `a` and stores it in `r`
    ## in CUDA.
    ##
    ## Note: This is constant-time
    ##
    ## TODO: Add a `skipFinalSub` argument?
    r = a # copy over a
    for i in 0 ..< count-1:
      r = mtymul_CIOS_sparebit(r, r, M, finalReduce = false)
    # last one with reducing
    r = mtymul_CIOS_sparebit(r, r, M, finalReduce = true)

  proc isZero(r: var bool, a: BigInt) {.device.} =
    ## Checks if `a` is zero in CUDA. Result is written to `r`.
    ##
    ## Note: This is constant-time
    #r = true
    #staticFor i, 0, a.len:
    #  r = r and a[i] == 0'u32
    var isZero = a[0]
    staticFor i, 0, a.len:
      isZero = isZero or a[i]
    r = isZero == 0'u32

  proc isOdd(r: var bool, a: BigInt) {.device.} =
    ## Checks if the Montgomery value of `a` is odd in CUDA. Result is written to `r`.
    ##
    ## IMPORTANT: The canonical value may or may not be odd if the Montgomery
    ## representation is odd (and vice versa!).
    ##
    ## Note: This is constant-time
    # check if least significant byte has first bit set
    r = (a[0] and 1'u32).bool

  proc neg(r: var BigInt, a: BigInt) {.device.} =
    ## Computes the negation of `a` and stores it in `r` in CUDA.
    ##
    ## Note: This is constant-time
    # Check if input is zero
    var isZ: bool = false
    isZ.isZero(a)
    # Subtraction `M - a`
    var t = BigInt()
    ## XXX: Is it safe to use `modsub` here?
    t.sub(M, a)
    # If input zero, we want `r = 0` instead of `r = M`!
    t.csetZero(isZ)
    r = t

  proc cneg(r: var BigInt, a: BigInt, condition: bool) {.device.} =
    ## Conditionally negate `a` and store it in `r` if `condition` is true, otherwise
    ## copy over `a` into `r` in CUDA.
    ##
    ## Note: This is constant-time
    r.neg(a)
    r.ccopy(a, not condition)

  proc shiftRight(r: var BigInt, k: uint32) {.device.} =
    ## Shift `r` right by `k` bits in-nplace in CUDA.
    ##
    ## k MUST be less than the base word size (2^31)
    ##
    ## Note: This is constant-time
    let wordBitWidth = sizeof(uint32) * 8
    let shiftLeft = wordBitWidth.uint32 - k

    # process all but the last word
    staticFor i, 0, r.len - 1:
      let current = r[i]
      let next = r[i + 1]

      let rightPart = current shr k
      let leftPart = next shl shiftLeft
      r[i] = rightPart or leftPart

    # handle the last word
    let lastIdx = r.len - 1
    r[lastIdx] = r[lastIdx] shr k

  proc div2(r: var BigInt) {.device.} =
    ## Divide `r` by 2 in-place in CUDA.
    ##
    ## Note: This is constant-time
    # check if the input is odd
    var isO: bool = false
    isO.isOdd(r)

    # perform the division using a right shift
    r.shiftRight(1)

    # if it was odd, add `M+1/2` to go 'half-way around'
    r.cadd(PP1D2, isO)

