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

template defBigInt*(N: typed): untyped {.dirty.} =
  # Utility for add with carry operations
  type
    BigInt = object
      limbs: array[N, uint32]
  template `[]`(x: BigInt, idx: int): untyped = x.limbs[idx]
  template `[]=`(x: BigInt, idx: int, val: uint32): untyped = x.limbs[idx] = val
  template len(x: BigInt): int = N # static: BigInt().limbs.len

template defPtxHelpers*(): untyped {.dirty.} =
  ## Note: the below would just be generated from a macro of course, similar to
  ## `constantine/platforms/llvm/asm_nvidia.nim`.
  #template asm_comment(msg: static string): untyped =
  #  static:
  #    const msg = "// " & msg
  #    asm(msg)

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

template defCoreFieldOps*(): untyped {.dirty.} =
  # Need to get the limbs & spare bits data in a static context
  template getFieldModulus(T: typed): untyped = static: T.getModulus().limbs
  template getM0ninv(T: typed): untyped = static: T.getModulus().negInvModWord().uint32
  template spareBits(): untyped = static: (BigInt().limbs.len * WordSize - T.bits())

  proc finalSubMayOverflow(a, M: BigInt): BigInt {.device.} =
    ## If a >= Modulus: r <- a-M
    ## else:            r <- a
    ##
    ## This is constant-time straightline code.
    ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
    ##
    ## To be used when the final substraction can
    ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)
    let N = a.len
    var scratch: BigInt = BigInt()

    # Contains 0x0001 (if overflowed limbs) or 0x0000
    let overflowedLimbs = add_ci(0'u32, 0'u32)

    # Now substract the modulus, and test a < M with the last borrow
    scratch[0] = sub_bo(a[0], M[0])
    for i in 1 ..< N:
      scratch[i] = sub_bio(a[i], M[i])

    # 1. if `overflowedLimbs`, underflowedModulus >= 0
    # 2. if a >= M, underflowedModulus >= 0
    # if underflowedModulus >= 0: a-M else: a
    # TODO: predicated mov instead?
    let underflowedModulus = sub_bi(overflowedLimbs, 0'u32)

    var r: BigInt = BigInt()
    for i in 0 ..< N:
      r[i] = slct(scratch[i], a[i], underflowedModulus)
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
    let N = a.len
    var scratch: BigInt = BigInt()

    # Now substract the modulus, and test a < M with the last borrow
    scratch[0] = sub_bo(a[0], M[0])
    for i in 1 ..< N:
      scratch[i] = sub_bio(a[i], M[i])

    # If it underflows here, `a` was smaller than the modulus, which is what we want
    let underflowedModulus = sub_bi(0'u32, 0'u32)

    var r: BigInt = BigInt()
    for i in 0 ..< N:
      r[i] = slct(scratch[i], a[i], underflowedModulus)
    return r

  proc modadd(a, b, M: BigInt): BigInt {.device.} =
    ## Generate an optimized modular addition kernel
    ## with parameters `a, b, modulus: Limbs -> Limbs`
    # try to add two bigints
    let N = a.len
    #var res: BigInt[N]
    var res: BigInt = BigInt()

    var t: BigInt = BigInt() # temporary

    t[0] = add_co(a[0], b[0])
    for i in 1 ..< N:
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
    # Pointers are opaque in LLVM now
    var t: BigInt = BigInt()
    let N = a.len

    t[0] = sub_bo(a[0], b[0])
    for i in 1 ..< N:
      t[i] = sub_bio(a[i], b[i])

    let underflowMask = sub_bi(0, 0)

    # If underflow
    # TODO: predicated mov instead?
    var maskedM: BigInt = BigInt()
    for i in 0 ..< N:
      maskedM[i] = M[i] and underflowMask

    block:
      t[0] = add_co(t[0], maskedM[0])
    for i in 1 ..< N-1:
      t[i] = add_cio(t[i], maskedM[i])
    if N > 1:
      t[N-1] = add_ci(t[N-1], maskedM[N-1])

    return t

  proc mtymul_CIOS_sparebit(a, b, M: BigInt, finalReduce: bool): BigInt {.device.} =
    ## Generate an optimized modular multiplication kernel
    ## with parameters `a, b, modulus: Limbs -> Limbs`
    var t: BigInt = BigInt()
    let N = a.len
    let m0ninv = getM0ninv(T)

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
    staticFor i, 0, a.len:
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
        staticFor j, 0, a.len:
          t[j] = mul_lo(a[j], bi)
      else:
        t[0] = mulloadd_co(a[0], bi, t[0])
        staticFor j, 1, a.len:
          t[j] = mulloadd_cio(a[j], bi, t[j])
        A = add_ci(0'u32, 0'u32)          # assumes N > 1
      t[1] = mulhiadd_co(a[0], bi, t[1])  # assumes N > 1
      staticFor j, 2, a.len:
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
      staticFor j, 1, a.len:
        t[j-1] = mulloadd_cio(m, M[j], t[j])
      t[N-1] = add_ci(A, 0)
      # assumes N > 1
      t[0] = mulhiadd_co(m, M[0], t[0])
      staticFor j, 1, a.len-1:
        t[j] = mulhiadd_cio(m, M[j], t[j])
      t[N-1] = mulhiadd_ci(m, M[N-1], t[N-1])

    if finalReduce:
      t = finalSubNoOverflow(t, M)

    return t
