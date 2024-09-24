# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# NOTE: We probably don't want the explicit `asm_nvidia` dependency here, I imagine? Currently it's
# for direct usage of `slct` in `neg`.
import
  constantine/platforms/llvm/[llvm, asm_nvidia],
  ./ir,
  ./pub_fields,
  ./impl_fields_globals,
  ./impl_fields_dispatch

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.pub_curves"

proc isNeutral_internal*(asy: Assembler_LLVM, ed: CurveDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point isNeutral proc
  ## with signature
  ##   void name(*bool r, CurveType a)
  ## with r the result and a the operand
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = ed.name & "_isNeutral_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):
    tagParameter(1, "sret")

    let (ri, ai) = llvmParams
    let aEc = asy.asEcPoint(ai, ed.curveTy)

    let z = aEc.getZ()
    asy.isZero_internal(ed.fd, ri, z.buf)

    asy.br.retVoid()

  asy.callFn(name, [r, a])

proc genEcIsNeutral*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  ## Generate a public elliptic curve point isNeutral proc
  ## with signature
  ##   void name(*bool r, CurveType a)
  ## with r the result and a the operand
  ## and return the corresponding name to call it

  let name = ed.name & "_isNeutral"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ptrBool, ed.curveTy]):
    let (r, a) = llvmParams
    asy.isNeutral_internal(ed, r, a)
    asy.br.retVoid()

  return name

proc ccopy_internal*(asy: Assembler_LLVM, ed: CurveDescriptor, a, b, c: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point ccopy proc
  ## with signature
  ##   `void name(CurveType a, CurveType b, bool condition)`
  ## with `a` and `b` EC curve point elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodified.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = ed.name & "_ccopy_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a, b, c]),
          {kHot}):
    tagParameter(1, "sret")

    let (ai, bi, ci) = llvmParams
    let aEc = asy.asEcPoint(ai, ed.curveTy)
    let bEc = asy.asEcPoint(bi, ed.curveTy)

    asy.ccopy_internal(ed.fd, aEc.getX().buf, bEc.getX().buf, ci)
    asy.ccopy_internal(ed.fd, aEc.getY().buf, bEc.getY().buf, ci)
    asy.ccopy_internal(ed.fd, aEc.getZ().buf, bEc.getZ().buf, ci)

    asy.br.retVoid()

  asy.callFn(name, [a, b, c])

proc genEcCcopy*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  ## Generate a public elliptic curve point ccopy proc
  ## with signature
  ##   `void name(CurveType a, CurveType b, bool condition)`
  ## with `a` and `b` EC curve point elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodified.
  ## and return the corresponding name to call it

  let name = ed.name & "_ccopy"
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.curveTy, ed.curveTy, asy.ctx.int1_t()]):
    let (a, b, c) = llvmParams
    asy.ccopy_internal(ed, a, b, c)
    asy.br.retVoid()

  return name

proc neg_internal*(asy: Assembler_LLVM, ed: CurveDescriptor, a: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point negation proc
  ## with signature
  ##   `void name(CurveType a)`
  ## with `a` the EC point to be negated.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = ed.name & "_neg_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a]),
          {kHot}):
    tagParameter(1, "sret")

    let ai = llvmParams
    let aEc = asy.asEcPoint(ai, ed.curveTy)
    ## XXX: maybe need to copy aEc?
    asy.neg_internal(ed.fd, aEc.getY().buf, aEc.getY().buf)

    asy.br.retVoid()

  asy.callFn(name, [a])

proc genEcNeg*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  ## Generate a public elliptic curve point neg proc
  ## with signature
  ##   `void name(CurveType a)`
  ## with `a` the EC curve point to be negated.
  ## and return the corresponding name to call it

  let name = ed.name & "_neg"
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.curveTy]):
    let a = llvmParams
    asy.neg_internal(ed, a)
    asy.br.retVoid()

  return name

proc cneg_internal*(asy: Assembler_LLVM, ed: CurveDescriptor, a, c: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point conditional negation proc
  ## with signature
  ##   `void name(CurveType a, bool condition)`
  ## with `a` the EC curve point to be negated if `condition` is true.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = ed.name & "_cneg_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a, c]),
          {kHot}):
    tagParameter(1, "sret")

    let (ai, ci) = llvmParams
    let aEc = asy.asEcPoint(ai, ed.curveTy)
    ## XXX: maybe need to copy aEc?
    asy.cneg_internal(ed.fd, aEc.getY().buf, aEc.getY().buf, ci)

    asy.br.retVoid()

  asy.callFn(name, [a, c])

proc genEcCneg*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  ## Generate a public elliptic curve point conditional neg proc
  ## with signature
  ##   `void name(CurveType a, bool condition)`
  ## with `a` the EC curve point to be negated if `condition` is true.
  ## Returns the name to call the kernel.

  let name = ed.name & "_neg"
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.curveTy, asy.ctx.int1_t()]):
    let (a, c) = llvmParams
    asy.cneg_internal(ed, a, c)
    asy.br.retVoid()

  return name


proc sum_internal*(asy: Assembler_LLVM, ed: CurveDescriptor, r, p, q: ValueRef) =
  ## Generate an internal elliptic curve point addition proc
  ## with signature
  ##   `void name(CurveType r, CurveType p, CurveType q)`
  ## with `a` and `b` EC curve point elements to be added.
  ## The result is stored in `r`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  ##
  ## XXX: For now we just port the coefA == 0 branch!
  let name = ed.name & "_sum_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, p, q]),
          {kHot}):
    tagParameter(1, "sret")
    let (ri, pi, qi) = llvmParams
    let Q = asy.asEcPoint(qi, ed.curveTy)
    let P = asy.asEcPoint(pi, ed.curveTy)
    let rA = asy.asEcPoint(ri, ed.curveTy)

    ## Helper templates to allow the logic below to be roughly equivalent to the regular
    ## CPU code in `ec_shortweierstrass_jacobian.nim`.

    ## XXX: These helpers will likely become either a template to be used in other EC
    ## procs in the near term or exported templates using the `Field` and `EcPoint` types
    ## for overload resolution in the longer term. Still, the explicit `asy/ed` dependencies
    ## makes it difficult to provide a clean API without -- effectively -- hacky templates,
    ## unless we absorb not only the `Builder` in the `Field` / `EcPoint` objects, but also
    ## the full `asy`/`ed` types as refs. It is an option though.

    # For finite field points
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

    # For EC points
    template isNeutral(res, x): untyped = asy.isNeutral_internal(ed, res, x.buf)
    template isNeutral(x): untyped =
      var res = asy.br.alloca(asy.ctx.int1_t())
      asy.isNeutral_internal(ed, res, x.buf)
      res

    template ccopy(x, y: EcPoint, c): untyped = asy.ccopy_internal(ed, x.buf, y.buf, derefBool c)

    template x(ec: EcPoint): Field = ec.getX()
    template y(ec: EcPoint): Field = ec.getY()
    template z(ec: EcPoint): Field = ec.getZ()

    ## XXX: Required to extent for coefA != 0!
    when false:
      # "when" static evaluation doesn't shortcut booleans :/
      # which causes issues when CoefA isn't an int but Fp or Fp2
      when CoefA is int:
        const CoefA_eq_zero = CoefA == 0
        const CoefA_eq_minus3 {.used.} = CoefA == -3
      else:
        const CoefA_eq_zero = false
        const CoefA_eq_minus3 = false

    var
      Z1Z1 = asy.newField(ed.fd)
      U1   = asy.newField(ed.fd)
      S1   = asy.newField(ed.fd)
      H    = asy.newField(ed.fd)
      R    = asy.newField(ed.fd)

    block: # Addition-only, check for exceptional cases
      var
        Z2Z2 = asy.newField(ed.fd)
        U2   = asy.newField(ed.fd)
        S2   = asy.newField(ed.fd)

      Z2Z2.square(Q.z)
      S1.prod(Q.z, Z2Z2)
      S1 *= P.y           # S₁ = Y₁*Z₂³
      U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²

      Z1Z1.square(P.z)
      S2.prod(P.z, Z1Z1)
      S2 *= Q.y           # S₂ = Y₂*Z₁³
      U2.prod(Q.x, Z1Z1)  # U₂ = X₂*Z₁²

      H.diff(U2, U1)      # H = U₂-U₁
      R.diff(S2, S1)      # R = S₂-S₁

    # Exceptional cases
    # Expressing H as affine, if H == 0, P == Q or -Q
    # H = U₂-U₁ = X₂*Z₁² - X₁*Z₂² = x₂*Z₂²*Z₁² - x₁*Z₁²*Z₂²
    # if H == 0 && R == 0, P = Q -> doubling
    # if only H == 0, P = -Q     -> infinity, implied in Z₃ = Z₁*Z₂*H = 0
    # if only R == 0, P and Q are related by the cubic root endomorphism

    let isDbl = H.isZero() and R.isZero()

    # Rename buffers under the form (add_or_dbl)
    template R_or_M: untyped = R
    template H_or_Y: untyped = H
    template V_or_S: untyped = U1
    var
      HH_or_YY = asy.newField(ed.fd)
      HHH_or_Mpre = asy.newField(ed.fd)

    H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
    HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

    V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
    V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

    # Block for `coefA == 0`
    ## XXX: when CoefA_eq_zero:
    block: # Compute M for doubling
      var
        a = asy.newField(ed.fd)
        b = asy.newField(ed.fd)
      asy.store(a, H)
      asy.store(b, HH_or_YY)
      a.ccopy(P.x, isDbl)           # H or X₁
      b.ccopy(P.x, isDbl)           # HH or X₁
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²

      var M = asy.newField(ed.fd)
      asy.store(M, HHH_or_Mpre) # Assuming on doubling path
      M.div2()                      #  X₁²/2
      M += HHH_or_Mpre              # 3X₁²/2
      R_or_M.ccopy(M, isDbl)

    ## XXX: Required to extent for coefA != 0!
    #  elif CoefA_eq_minus3:
    #    var a{.noInit.}, b{.noInit.}: F
    #    a.sum(P.x, Z1Z1)
    #    b.diff(P.z, Z1Z1)
    #    a.ccopy(H_or_Y, not isDbl)    # H   or X₁+ZZ
    #    b.ccopy(HH_or_YY, not isDbl)  # HH  or X₁-ZZ
    #    HHH_or_Mpre.prod(a, b)        # HHH or X₁²-ZZ²
    #
    #    var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
    #    M.div2()                      # (X₁²-ZZ²)/2
    #    M += HHH_or_Mpre              # 3(X₁²-ZZ²)/2
    #    R_or_M.ccopy(M, isDbl)
    #
    #  else:
    #    # TODO: Costly `a` coefficients can be computed
    #    # by merging their computation with Z₃ = Z₁*Z₂*H (add) or Z₃ = Y₁*Z₁ (dbl)
    #    var a{.noInit.} = H
    #    var b{.noInit.} = HH_or_YY
    #    a.ccopy(P.x, isDbl)
    #    b.ccopy(P.x, isDbl)
    #    HHH_or_Mpre.prod(a, b)  # HHH or X₁²
    #
    #    # Assuming doubling path
    #    a.square(HHH_or_Mpre, skipFinalSub = true)
    #    a *= HHH_or_Mpre              # a = 3X₁²
    #    b.square(Z1Z1)
    #    b.mulCheckSparse(CoefA)       # b = αZZ, with α the "a" coefficient of the curve
    #
    #    a += b
    #    a.div2()
    #    R_or_M.ccopy(a, isDbl)        # (3X₁² - αZZ)/2

    # Let's count our horses, at this point:
    # - R_or_M is set with R (add) or M (dbl)
    # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
    # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
    var o = asy.newEcPoint(ed)
    block: # Finishing line
      var t = asy.newField(ed.fd)
      t.double(V_or_S)
      o.x.square(R_or_M)
      o.x -= t                           # X₃ = R²-2*V (add) or M²-2*S (dbl)
      o.x.csub(HHH_or_Mpre, not isDbl)   # X₃ = R²-HHH-2*V (add) or M²-2*S (dbl)

      V_or_S -= o.x                      # V-X₃ (add) or S-X₃ (dbl)
      o.y.prod(R_or_M, V_or_S)           # Y₃ = R(V-X₃) (add) or M(S-X₃) (dbl)
      HHH_or_Mpre.ccopy(HH_or_YY, isDbl) # HHH (add) or YY (dbl)
      S1.ccopy(HH_or_YY, isDbl)          # S1 (add) or YY (dbl)
      HHH_or_Mpre *= S1                  # HHH*S1 (add) or YY² (dbl)
      o.y -= HHH_or_Mpre                 # Y₃ = R(V-X₃)-S₁*HHH (add) or M(S-X₃)-YY² (dbl)

      asy.store(t, Q.z)                  # `t = Q.z`
      t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
      t.prod(t, P.z)                     # Z₁Z₂ (add) or Y₁Z₁ (dbl)
      o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
      o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)

    # if P or R were infinity points they would have spread 0 with Z₁Z₂
    block: # Infinity points
      o.ccopy(Q, P.isNeutral())
      o.ccopy(P, Q.isNeutral())

    asy.store(rA, o)                     # `r = o`

    asy.br.retVoid()

  asy.callFn(name, [r, p, q])

proc genEcSum*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  ## Generate a publc elliptic curve point addition proc
  ## with signature
  ##   `void name(CurveType r, CurveType p, CurveType q)`
  ## with `a` and `b` EC curve point elements to be added.
  ## The result is stored in `r`.
  ##
  ## Returns the name of the produced kernel to call it.
  let name = ed.name & "_sum"
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.curveTy, ed.curveTy, ed.curveTy]):
    let (ri, pi, qi) = llvmParams
    asy.sum_internal(ed, ri, pi, qi)
    asy.br.retVoid()
  result = name
