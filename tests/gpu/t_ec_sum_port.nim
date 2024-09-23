# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

##[

NOTE:

This test case was used to port the `sumImpl` template implementation for CPU targets from
`ec_shortweierstrass_jacobian.nim` to the LLVM based GPU target.

It contains multiple commented out lines of proc signatures, input types and many `asy.store`
instructions. By using `asy.store` and adjusting the return type of the LLVM based procedure,
(i.e. the first argument in the following line from below:

`asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.curveTy, ed.curveTy, ed.curveTy]):`
                                                          ^--- First argument == return type

and adjusting the `cpuSumImpl` below to return the 'same' value, one can compare all intermediary
results line by line to verify correctness. Porting the entire code first and then trying
to pin down small bugs is a lot more bothersome.

]##

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/math/arithmetic,
  constantine/math/elliptic/ec_shortweierstrass_jacobian,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, pub_curves, codegen_nvidia, impl_fields_globals],
  # Test utilities
  helpers/prng_unsafe

proc genSumImpl*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  let name = ed.name & "_sum_internal"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  #asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.fd.fieldTy, ed.curveTy, ed.curveTy]):
  #asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ptrBool, ed.curveTy, ed.curveTy]):
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.curveTy, ed.curveTy, ed.curveTy]):
    let (ri, pi, qi) = llvmParams
    # Assuming fd.numWords is the number of limbs in the field element
    let Q = asy.asEcPoint(qi, ed.curveTy)
    let P = asy.asEcPoint(pi, ed.curveTy)
    let rA = asy.asEcPoint(ri, ed.curveTy)
    #let rA = asy.asField(ri, ed.fd.fieldTy)

    ## XXX: For now we just port the coefA == 0 branch!

    var
      Z1Z1 = asy.newField(ed.fd)
      U1   = asy.newField(ed.fd)
      S1   = asy.newField(ed.fd)
      H    = asy.newField(ed.fd)
      R    = asy.newField(ed.fd)

    template square(res, y): untyped = asy.nsqr_internal(ed.fd, res.buf, y.buf, count = 1)
    template prod(res, x, y): untyped = asy.mul_internal(ed.fd, res.buf, x.buf, y.buf)
    template diff(res, x, y): untyped = asy.sub_internal(ed.fd, res.buf, x.buf, y.buf)
    template add(res, x, y): untyped = asy.add_internal(ed.fd, res.buf, x.buf, y.buf)
    template double(res, x): untyped = asy.double_internal(ed.fd, res.buf, x.buf)
    template isZero(res, x): untyped = asy.isZero_internal(ed.fd, res, x.buf)
    template isZero(x): untyped =
      var res = asy.br.alloca(asy.ctx.int1_t())
      asy.isZero_internal(ed.fd, res, x.buf)
      res
    template ccopy(x, y: Field, c): untyped = asy.ccopy_internal(ed.fd, x.buf, y.buf, c)
    template div2(x): untyped = asy.div2_internal(ed.fd, x.buf)
    template csub(x, y, c): untyped = asy.csub_internal(ed.fd, x.buf, y.buf, c)

    template `not`(x: ValueRef): untyped = asy.br.`not`(x)

    template `*=`(x, y: Field): untyped = x.prod(x, y)
    template `+=`(x, y: Field): untyped = x.add(x, y)
    template `-=`(x, y: Field): untyped = x.diff(x, y)

    template derefBool(x): untyped = asy.load2(asy.ctx.int1_t(), x)

    template `and`(x, y): untyped =
      var res = asy.br.alloca(asy.ctx.int1_t())
      res = asy.br.`and`(derefBool x, derefBool y)
      res

    ## For EC points
    template isNeutral(res, x): untyped = asy.isNeutral_internal(ed, res, x.buf)
    template isNeutral(x): untyped =
      var res = asy.br.alloca(asy.ctx.int1_t())
      asy.isNeutral_internal(ed, res, x.buf)
      res

    template ccopy(x, y: EcPoint, c): untyped = asy.ccopy_internal(ed, x.buf, y.buf, derefBool c)

    template x(ec: EcPoint): Field = ec.getX()
    template y(ec: EcPoint): Field = ec.getY()
    template z(ec: EcPoint): Field = ec.getZ()


    block: # Addition-only, check for exceptional cases
      var
        Z2Z2 = asy.newField(ed.fd)
        U2   = asy.newField(ed.fd)
        S2   = asy.newField(ed.fd)

      Z2Z2.square(Q.z) # , skipFinalSub = true)
      #asy.store(rA, Z2Z2)
      S1.prod(Q.z, Z2Z2) #, skipFinalSub = true)
      #asy.store(rA, S1)
      S1 *= P.y           # S₁ = Y₁*Z₂³
      #S1.prod(S1, P.y)
      #asy.store(rA, S1)
      U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²
      #asy.store(rA, U1)

      Z1Z1.square(P.z) # , skipFinalSub = not CoefA_eq_minus3)
      #asy.store(rA, Z1Z1)
      S2.prod(P.z, Z1Z1)#, skipFinalSub = true)
      #asy.store(rA, S2)
      S2 *= Q.y           # S₂ = Y₂*Z₁³
      #asy.store(rA, S2)
      U2.prod(Q.x, Z1Z1)  # U₂ = X₂*Z₁²
      #asy.store(rA, U2)

      H.diff(U2, U1)      # H = U₂-U₁
      #asy.store(rA, H)
      R.diff(S2, S1)      # R = S₂-S₁
      #asy.store(rA, R)

    # Exceptional cases
    # Expressing H as affine, if H == 0, P == Q or -Q
    # H = U₂-U₁ = X₂*Z₁² - X₁*Z₂² = x₂*Z₂²*Z₁² - x₁*Z₁²*Z₂²
    # if H == 0 && R == 0, P = Q -> doubling
    # if only H == 0, P = -Q     -> infinity, implied in Z₃ = Z₁*Z₂*H = 0
    # if only R == 0, P and Q are related by the cubic root endomorphism

    ## TEST: Set H and R to zero to verify that our `isZero` & `and` logic works
    # asy.setZero_internal(ed.fd, H.buf)
    # asy.setZero_internal(ed.fd, R.buf)

    let isDbl = H.isZero() and R.isZero()
    #asy.store(ri, isDbl)

    # Rename buffers under the form (add_or_dbl)
    template R_or_M: untyped = R
    template H_or_Y: untyped = H
    template V_or_S: untyped = U1
    var
      HH_or_YY = asy.newField(ed.fd)
      HHH_or_Mpre = asy.newField(ed.fd)

    H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
    #asy.store(rA, H_or_Y)
    HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)
    #asy.store(rA, HH_or_YY)
    #
    V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
    #asy.store(rA, V_or_S)
    V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)
    #asy.store(rA, V_or_S)

    # Block for `coefA == 0`
    block: # Compute M for doubling
      var
        a = asy.newField(ed.fd)
        b = asy.newField(ed.fd)
      asy.store(a, H)
      asy.store(b, HH_or_YY)
      a.ccopy(P.x, isDbl)           # H or X₁
      #asy.store(rA, a)
      b.ccopy(P.x, isDbl)           # HH or X₁
      #asy.store(rA, b)
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²
      #asy.store(rA, HHH_or_Mpre)
      #
      var M = asy.newField(ed.fd)
      asy.store(M, HHH_or_Mpre) # Assuming on doubling path
      M.div2()                      #  X₁²/2
      #asy.store(rA, M)
      M += HHH_or_Mpre              # 3X₁²/2
      #asy.store(rA, M)
      R_or_M.ccopy(M, isDbl)
      #asy.store(rA, R_or_M)

    # Let's count our horses, at this point:
    # - R_or_M is set with R (add) or M (dbl)
    # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
    # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
    var o = asy.newEcPoint(ed)
    block: # Finishing line
      var t = asy.newField(ed.fd)
      t.double(V_or_S)
      #asy.store(rA, t)
      o.x.square(R_or_M)
      #asy.store(rA, o.x)
      o.x -= t                           # X₃ = R²-2*V (add) or M²-2*S (dbl)
      #asy.store(rA, o.x)
      o.x.csub(HHH_or_Mpre, not isDbl)   # X₃ = R²-HHH-2*V (add) or M²-2*S (dbl)
      #asy.store(rA, o.x)

      V_or_S -= o.x                      # V-X₃ (add) or S-X₃ (dbl)
      #asy.store(rA, V_or_S)
      o.y.prod(R_or_M, V_or_S)           # Y₃ = R(V-X₃) (add) or M(S-X₃) (dbl)
      #asy.store(rA, o.y)
      HHH_or_Mpre.ccopy(HH_or_YY, isDbl) # HHH (add) or YY (dbl)
      #asy.store(rA, HHH_or_Mpre)
      S1.ccopy(HH_or_YY, isDbl)          # S1 (add) or YY (dbl)
      #asy.store(rA, S1)
      HHH_or_Mpre *= S1                  # HHH*S1 (add) or YY² (dbl)
      #asy.store(rA, HHH_or_Mpre)
      o.y -= HHH_or_Mpre                 # Y₃ = R(V-X₃)-S₁*HHH (add) or M(S-X₃)-YY² (dbl)
      #asy.store(rA, o.y)

      asy.store(t, Q.z) # t = Q.z
      #asy.store(rA, t)
      t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
      #asy.store(rA, t)
      t.prod(t, P.z) #, true)               # Z₁Z₂ (add) or Y₁Z₁ (dbl)
      #asy.store(rA, t)
      o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
      #asy.store(rA, o.z)
      o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)
      #asy.store(rA, o.z)


    # if P or R were infinity points they would have spread 0 with Z₁Z₂
    block: # Infinity points
      o.ccopy(Q, P.isNeutral())
      #asy.store(rA, o)
      o.ccopy(P, Q.isNeutral())
      #asy.store(rA, o)

    asy.store(rA, o) # r = o

    asy.br.retVoid()

  result = name

proc cpuSumImpl[Name: static Algebra](P, Q: EC_ShortW_Jac[Fp[Name], G1]): EC_ShortW_Jac[Fp[Name], G1] =
#proc cpuSumImpl[Name: static Algebra](P, Q: EC_ShortW_Jac[Fp[Name], G1]): Fp[Name] =
#proc cpuSumImpl[Name: static Algebra](P, Q: EC_ShortW_Jac[Fp[Name], G1]): bool =
  type F = Fp[Name]
  var Z1Z1 {.noInit.}, U1 {.noInit.}, S1 {.noInit.}, H {.noInit.}, R {.noinit.}: F

  block: # Addition-only, check for exceptional cases
    var Z2Z2 {.noInit.}, U2 {.noInit.}, S2 {.noInit.}: F
    Z2Z2.square(Q.z) #, skipFinalSub = true)
    S1.prod(Q.z, Z2Z2) #, skipFinalSub = true)
    S1 *= P.y           # S₁ = Y₁*Z₂³
    U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²

    Z1Z1.square(P.z) #, skipFinalSub = not CoefA_eq_minus3)
    S2.prod(P.z, Z1Z1, skipFinalSub = true)
    S2 *= Q.y           # S₂ = Y₂*Z₁³
    U2.prod(Q.x, Z1Z1)  # U₂ = X₂*Z₁²

    H.diff(U2, U1)      # H = U₂-U₁
    R.diff(S2, S1)      # R = S₂-S₁
    #result = R

  # Exceptional cases
  # Expressing H as affine, if H == 0, P == Q or -Q
  # H = U₂-U₁ = X₂*Z₁² - X₁*Z₂² = x₂*Z₂²*Z₁² - x₁*Z₁²*Z₂²
  # if H == 0 && R == 0, P = Q -> doubling
  # if only H == 0, P = -Q     -> infinity, implied in Z₃ = Z₁*Z₂*H = 0
  # if only R == 0, P and Q are related by the cubic root endomorphism
  let isDbl = H.isZero() and R.isZero()
  #result = bool isDbl

  # Rename buffers under the form (add_or_dbl)
  template R_or_M: untyped = R
  template H_or_Y: untyped = H
  template V_or_S: untyped = U1
  var HH_or_YY {.noInit.}: F
  var HHH_or_Mpre {.noInit.}: F

  H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
  HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

  V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
  V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

  block: # Compute M for doubling
    when true: # CoefA_eq_zero:
      var a {.noInit.} = H
      var b {.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)           # H or X₁
      b.ccopy(P.x, isDbl)           # HH or X₁
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      #  X₁²/2
      M += HHH_or_Mpre              # 3X₁²/2
      R_or_M.ccopy(M, isDbl)

  # Let's count our horses, at this point:
  # - R_or_M is set with R (add) or M (dbl)
  # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
  # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
  var o {.noInit.}: typeof(P)
  block: # Finishing line
    var t {.noInit.}: F
    t.double(V_or_S)
    #result = t
    o.x.square(R_or_M)
    #result = o.x
    o.x -= t                           # X₃ = R²-2*V (add) or M²-2*S (dbl)
    #result = o.x
    o.x.csub(HHH_or_Mpre, not isDbl)   # X₃ = R²-HHH-2*V (add) or M²-2*S (dbl)
    #result = o.x

    V_or_S -= o.x                      # V-X₃ (add) or S-X₃ (dbl)
    #result = V_or_S
    o.y.prod(R_or_M, V_or_S)           # Y₃ = R(V-X₃) (add) or M(S-X₃) (dbl)
    #result = o.y
    HHH_or_Mpre.ccopy(HH_or_YY, isDbl) # HHH (add) or YY (dbl)
    #result = HHHor_Mpre
    S1.ccopy(HH_or_YY, isDbl)          # S1 (add) or YY (dbl)
    #result = S1
    HHH_or_Mpre *= S1                  # HHH*S1 (add) or YY² (dbl)
    #result = HHH_or_Mpre
    o.y -= HHH_or_Mpre                 # Y₃ = R(V-X₃)-S₁*HHH (add) or M(S-X₃)-YY² (dbl)
    #result = o.y

    t = Q.z
    #result = t
    t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
    #result = t
    t.prod(t, P.z, true)               # Z₁Z₂ (add) or Y₁Z₁ (dbl)
    #result = t
    o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
    #result = o.z
    o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)
    #result = o.z

    # if P or R were infinity points they would have spread 0 with Z₁Z₂
    block: # Infinity points
      o.ccopy(Q, P.isNeutral())
      #result = o
      o.ccopy(P, Q.isNeutral())
      #result = o

    result = o # r = o

proc exec*[T; U](jitFn: CUfunction, r: var T; a, b: U) =
  # The execution wrapper provided are mostly for testing and debugging low-level kernels
  # that serve as building blocks, like field addition or multiplication.
  # They aren't parallelizable so we are not concern about the grid and block size.
  # We also aren't concerned about the cuda stream when testing.
  #
  # This is not the case for production kernels (multi-scalar-multiplication, FFT)
  # as we want to execute kernels asynchronously then merge results which might require multiple streams.

  static: doAssert cpuEndian == littleEndian, block:
    # From https://developer.nvidia.com/cuda-downloads?target_os=Linux
    # Supported architectures for Cuda are:
    # x86-64, PowerPC 64 little-endian, ARM64 (aarch64)
    # which are all little-endian at word-level.
    #
    # Due to limbs being also stored in little-endian, on little-endian host
    # the CPU and GPU will have the same binary representation
    # whether we use 32-bit or 64-bit words, so naive memcpy can be used for parameter passing.

    "Most CPUs (x86-64, ARM) are little-endian, as are Nvidia GPUs, which allows naive copying of parameters.\n" &
    "Your architecture '" & $hostCPU & "' is big-endian and GPU offloading is unsupported on it."

  # We assume that all arguments are passed by reference in the Cuda kernel, hence the need for GPU alloc.

  var rGPU, aGPU, bGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))
  check cuMemAlloc(aGPU, csize_t sizeof(a))
  check cuMemAlloc(bGPU, csize_t sizeof(b))

  check cuMemcpyHtoD(aGPU, a.addr, csize_t sizeof(a))
  check cuMemcpyHtoD(bGPU, b.addr, csize_t sizeof(b))

  let params = [pointer(rGPU.addr), pointer(aGPU.addr), pointer(bGPU.addr)]

  check cuLaunchKernel(
          jitFn,
          1, 1, 1, # grid(x, y, z)
          1, 1, 1, # block(x, y, z)
          sharedMemBytes = 0,
          CUstream(nil),
          params[0].unsafeAddr, nil)

  check cuMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))

  check cuMemFree(rGPU)
  check cuMemFree(aGPU)
  check cuMemFree(bGPU)

# Init LLVM
# -------------------------
initializeFullNVPTXTarget()

# Init GPU
# -------------------------
let cudaDevice = cudaDeviceInit()
var sm: tuple[major, minor: int32]
check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

proc test[Name: static Algebra](field: type FF[Name], wordSize: int,
                                a, b: EC_ShortW_Jac[field, G1],) =
  # Codegen
  # -------------------------
  let name = if field is Fp: $Name & "_fp"
             else: $Name & "_fr"
  let asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("t_nvidia_" & name & $wordSize))
  let ed = asy.ctx.configureCurve(
    name, field.bits(),
    field.getModulus().toHex(),
    v = 1, w = wordSize
  )

  asy.definePrimitives(ed)

  let kernName = asy.genSumImpl(ed)
  let ptx = asy.codegenNvidiaPTX(sm)

  # GPU exec
  # -------------------------
  var cuCtx: CUcontext
  var cuMod: CUmodule
  check cuCtxCreate(cuCtx, 0, cudaDevice)
  check cuModuleLoadData(cuMod, ptx)
  defer:
    check cuMod.cuModuleUnload()
    check cuCtx.cuCtxDestroy()

  let kernel = cuMod.getCudaKernel(kernName)

  # For CPU:
  var rCPU: EC_ShortW_Jac[field, G1]
  #var rCPU: field
  #var rCPU: bool
  rCPU = cpuSumImpl(a, b)

  # For GPU:
  var rGPU: EC_ShortW_Jac[field, G1]
  #var rGPU: field
  #var rGPU: bool
  kernel.exec(rGPU, a, b)

  echo "Input: ", a.toHex()
  echo "CPU:   ", rCPU.toHex()
  echo "GPU:   ", rGPU.toHex()
  doAssert bool(rCPU == rGPU)

let x = "0x2ef34a5db00ff691849861d49415d8081d9d0e10cba33b57b2dd1f37f13eeee0"
let y = "0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a"
let pt = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x, y)
echo pt.toHex()

let x2 = "0x226c85cf65f4596a77da7d247310a81ac9aa9220e819e3ef23b6cbe0218ce272"
let y2 = "0xf53265870f65aa18bded3ccb9c62a4d8b060a32a05a75d455710bce95a991df"
let pt2 = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x2, y2)

test(Fp[BN254_Snarks], 64, pt, pt2)
