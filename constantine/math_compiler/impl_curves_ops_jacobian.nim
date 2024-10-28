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
  ./impl_fields_globals,
  ./impl_fields_dispatch,
  ./impl_fields_ops,
  ./impl_curves_ops_affine,
  std / typetraits # for distinctBase

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.curves_jacobian"

type
  EcPointJac* {.borrow: `.`.} = distinct Array

proc asEcPointJac*(asy: Assembler_LLVM, arrayPtr: ValueRef, arrayTy: TypeRef): EcPointJac =
  ## Constructs an elliptic curve point in Jacobian coordinates from an array pointer.
  ##
  ## `arrayTy` is an `array[FieldTy, 3]` where `FieldTy` itsel is an array of
  ## `array[WordTy, NumWords]`.
  result = EcPointJac(asy.asArray(arrayPtr, arrayTy))

proc asEcPointJac*(asy: Assembler_LLVM, cd: CurveDescriptor, arrayPtr: ValueRef): EcPointJac =
  ## Constructs an elliptic curve point in Jacobian coordinates from an array pointer,
  ## taking the required `arrayTy` from the `CurveDescriptor`.
  ##
  ## `arrayTy` is an `array[FieldTy, 3]` where `FieldTy` itsel is an array of
  ## `array[WordTy, NumWords]`.
  result = EcPointJac(asy.asArray(arrayPtr, cd.curveTy))

proc newEcPointJac*(asy: Assembler_LLVM, cd: CurveDescriptor): EcPointJac =
  ## Use field descriptor for size etc?
  result = EcPointJac(asy.makeArray(cd.curveTy))

func getIdx*(br: BuilderRef, ec: EcPointJac, idx: int): Field =
  let pelem = distinctBase(ec).getElementPtr(0, idx)
  result = br.asField(pelem, ec.elemTy)

func getX*(ec: EcPointJac): Field = ec.builder.getIdx(ec, 0)
func getY*(ec: EcPointJac): Field = ec.builder.getIdx(ec, 1)
func getZ*(ec: EcPointJac): Field = ec.builder.getIdx(ec, 2)

proc store*(dst: EcPointJac, src: EcPointJac) =
  ## Stores the `dst` in `src`. Both must correspond to the same field of course.
  assert dst.arrayTy.getArrayLength() == src.arrayTy.getArrayLength()
  store(dst.getX(), src.getX())
  store(dst.getY(), src.getY())
  store(dst.getZ(), src.getZ())

template declEllipticJacOps*(asy: Assembler_LLVM, cd: CurveDescriptor): untyped =
  ## This template can be used to make operations on `Field` elements
  ## more convenient.
  ## XXX: extend to include all ops
  # Boolean checks
  template isNeutral(res, x: EcPointJac): untyped = asy.isNeutral(cd, res, x.buf)
  template isNeutral(x: EcPointJac): untyped =
    var res = asy.br.alloca(asy.ctx.int1_t())
    asy.isNeutral(cd, res, x.buf)
    res

  # Conditional ops
  template ccopy(x, y: EcPointJac, c): untyped = asy.ccopy(cd, x.buf, y.buf, derefBool c)

  # Accessors
  template x(ec: EcPointJac): Field = ec.getX()
  template y(ec: EcPointJac): Field = ec.getY()
  template z(ec: EcPointJac): Field = ec.getZ()

proc fromAffine_impl*(asy: Assembler_LLVM, cd: CurveDescriptor, jac: var EcPointJac, aff: EcPointAff) =
  # Inject templates for convenient access
  declFieldOps(asy, cd.fd)
  declEllipticJacOps(asy, cd)
  declEllipticAffOps(asy, cd)

  jac.x.store(aff.x)
  jac.y.store(aff.y)
  jac.z.setOne()
  jac.z.csetZero(aff.isNeutral())

proc fromAffine*(asy: Assembler_LLVM, cd: CurveDescriptor, j, a: ValueRef) =
  ## Given an EC point in affine coordinates, converts the point to
  ## Jacobian coordinates as `jac`.
  let name = cd.name & "_fromAffine_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([j, a]),
          {kHot}):
    tagParameter(1, "sret")

    let (ji, ai) = llvmParams
    var jac = asy.asEcPointJac(cd, ji)
    let aff = asy.asEcPointAff(cd, ai)

    asy.fromAffine_impl(cd, jac, aff)

    asy.br.retVoid()

  asy.callFn(name, [j, a])

proc isNeutral*(asy: Assembler_LLVM, cd: CurveDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point isNeutral proc
  ## with signature
  ##   void name(*bool r, CurveType a)
  ## with r the result and a the operand
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_isNeutral_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):
    tagParameter(1, "sret")

    let (ri, ai) = llvmParams
    let aEc = asy.asEcPointJac(ai, cd.curveTy)

    let z = aEc.getZ()
    asy.isZero(cd.fd, ri, z.buf)

    asy.br.retVoid()

  asy.callFn(name, [r, a])

proc setNeutral*(asy: Assembler_LLVM, cd: CurveDescriptor, r: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point `setNeutral` proc
  ## with signature
  ##   void name(CurveType r)
  ## with r the point to be 'neutralized'.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_setNeutral_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r]),
          {kHot}):
    tagParameter(1, "sret")

    let ri = llvmParams
    let P = asy.asEcPointJac(ri, cd.curveTy)

    declFieldOps(asy, cd.fd)
    declEllipticJacOps(asy, cd)
    P.x.setOne()
    P.y.setOne()
    P.z.setZero()

    asy.br.retVoid()

  asy.callFn(name, [r])

proc ccopy*(asy: Assembler_LLVM, cd: CurveDescriptor, a, b, c: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point ccopy proc
  ## with signature
  ##   `void name(CurveType a, CurveType b, bool condition)`
  ## with `a` and `b` EC curve point elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodified.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_ccopy_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a, b, c]),
          {kHot}):
    tagParameter(1, "sret")

    let (ai, bi, ci) = llvmParams
    let aEc = asy.asEcPointJac(ai, cd.curveTy)
    let bEc = asy.asEcPointJac(bi, cd.curveTy)

    asy.ccopy(cd.fd, aEc.getX().buf, bEc.getX().buf, ci)
    asy.ccopy(cd.fd, aEc.getY().buf, bEc.getY().buf, ci)
    asy.ccopy(cd.fd, aEc.getZ().buf, bEc.getZ().buf, ci)

    asy.br.retVoid()

  asy.callFn(name, [a, b, c])

proc neg*(asy: Assembler_LLVM, cd: CurveDescriptor, a: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point negation proc
  ## with signature
  ##   `void name(CurveType a)`
  ## with `a` the EC point to be negated.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_neg_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a]),
          {kHot}):
    tagParameter(1, "sret")

    let ai = llvmParams
    let aEc = asy.asEcPointJac(ai, cd.curveTy)
    asy.neg(cd.fd, aEc.getY().buf, aEc.getY().buf)

    asy.br.retVoid()

  asy.callFn(name, [a])

proc cneg*(asy: Assembler_LLVM, cd: CurveDescriptor, a, c: ValueRef) {.used.} =
  ## Generate an internal elliptic curve point conditional negation proc
  ## with signature
  ##   `void name(CurveType a, bool condition)`
  ## with `a` the EC curve point to be negated if `condition` is true.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_cneg_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a, c]),
          {kHot}):
    tagParameter(1, "sret")

    let (ai, ci) = llvmParams
    let aEc = asy.asEcPointJac(ai, cd.curveTy)
    asy.cneg(cd.fd, aEc.getY().buf, aEc.getY().buf, ci)

    asy.br.retVoid()

  asy.callFn(name, [a, c])

proc sum*(asy: Assembler_LLVM, cd: CurveDescriptor, r, p, q: ValueRef) =
  ## Generate an internal elliptic curve point addition proc
  ## with signature
  ##   `void name(CurveType r, CurveType p, CurveType q)`
  ## with `a` and `b` EC curve point elements to be added.
  ## The result is stored in `r`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_sum_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, p, q]),
          {kHot}):
    tagParameter(1, "sret")
    let (ri, pi, qi) = llvmParams
    let Q = asy.asEcPointJac(qi, cd.curveTy)
    let P = asy.asEcPointJac(pi, cd.curveTy)
    let rA = asy.asEcPointJac(ri, cd.curveTy)

    ## Helper templates to allow the logic below to be roughly equivalent to the regular
    ## CPU code in `ec_shortweierstrass_jacobian.nim`.

    # Make finite field point operations nicer
    declFieldOps(asy, cd.fd)
    # And EC points
    declEllipticJacOps(asy, cd)

    var
      Z1Z1 = asy.newField(cd.fd)
      U1   = asy.newField(cd.fd)
      S1   = asy.newField(cd.fd)
      H    = asy.newField(cd.fd)
      R    = asy.newField(cd.fd)

    block: # Addition-only, check for exceptional cases
      var
        Z2Z2 = asy.newField(cd.fd)
        U2   = asy.newField(cd.fd)
        S2   = asy.newField(cd.fd)

      ## XXX: Similarly to `prod` below, `skipFinalSub = true` here, also breaks the
      ## code at a different point.
      Z2Z2.square(Q.z, skipFinalSub = false)
      ## XXX: If we set this `skipFinalSub` to true, the code will fail to produce the
      ## correct result in some cases. Not sure yet why. See `tests/gpu/t_ec_sum.nim`.
      S1.prod(Q.z, Z2Z2, skipFinalSub = false)
      S1 *= P.y           # S₁ = Y₁*Z₂³
      U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²

      Z1Z1.square(P.z, skipFinalSub = not cd.coef_a == -3)
      S2.prod(P.z, Z1Z1, skipFinalSub = true)
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
      HH_or_YY = asy.newField(cd.fd)
      HHH_or_Mpre = asy.newField(cd.fd)

    H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
    HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

    V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
    V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

    block: # Compute M for doubling
      if cd.coef_a == 0:
        var
          a = asy.newField(cd.fd)
          b = asy.newField(cd.fd)
        store(a, H)
        store(b, HH_or_YY)
        a.ccopy(P.x, isDbl)           # H or X₁
        b.ccopy(P.x, isDbl)           # HH or X₁
        HHH_or_Mpre.prod(a, b)        # HHH or X₁²

        var M = asy.newField(cd.fd)
        store(M, HHH_or_Mpre) # Assuming on doubling path
        M.div2()                      #  X₁²/2
        M += HHH_or_Mpre              # 3X₁²/2
        R_or_M.ccopy(M, isDbl)

      elif cd.coef_a == -3:
        var
          a = asy.newField(cd.fd)
          b = asy.newField(cd.fd)
        a.sum(P.x, Z1Z1)
        b.diff(P.z, Z1Z1)
        a.ccopy(H_or_Y, not isDbl)    # H   or X₁+ZZ
        b.ccopy(HH_or_YY, not isDbl)  # HH  or X₁-ZZ
        HHH_or_Mpre.prod(a, b)        # HHH or X₁²-ZZ²

        var M = asy.newField(cd.fd)
        store(M, HHH_or_Mpre) # Assuming on doubling path
        M.div2()                      # (X₁²-ZZ²)/2
        M += HHH_or_Mpre              # 3(X₁²-ZZ²)/2
        R_or_M.ccopy(M, isDbl)

      else:
        # TODO: Costly `a` coefficients can be computed
        # by merging their computation with Z₃ = Z₁*Z₂*H (add) or Z₃ = Y₁*Z₁ (dbl)
        var
          a = asy.newField(cd.fd)
          b = asy.newField(cd.fd)
        store(a, H)
        store(b, HH_or_YY)
        a.ccopy(P.x, isDbl)
        b.ccopy(P.x, isDbl)
        HHH_or_Mpre.prod(a, b)  # HHH or X₁²

        # Assuming doubling path
        a.square(HHH_or_Mpre, skipFinalSub = true)
        a *= HHH_or_Mpre              # a = 3X₁²
        b.square(Z1Z1)
        b.mulCheckSparse(cd.coef_a)       # b = αZZ, with α the "a" coefficient of the curve

        a += b
        a.div2()
        R_or_M.ccopy(a, isDbl)        # (3X₁² - αZZ)/2

    # Let's count our horses, at this point:
    # - R_or_M is set with R (add) or M (dbl)
    # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
    # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
    var o = asy.newEcPointJac(cd)
    block: # Finishing line
      var t = asy.newField(cd.fd)
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

      store(t, Q.z)                      # `t = Q.z`
      t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
      t.prod(t, P.z)                     # Z₁Z₂ (add) or Y₁Z₁ (dbl)
      o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
      o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)

    # if P or R were infinity points they would have spread 0 with Z₁Z₂
    block: # Infinity points
      o.ccopy(Q, P.isNeutral())
      o.ccopy(P, Q.isNeutral())

    store(rA, o)                         # `r = o`

    asy.br.retVoid()

  asy.callFn(name, [r, p, q])

proc double*(asy: Assembler_LLVM, cd: CurveDescriptor, r, p: ValueRef) =
  ## Generate an internal elliptic curve point doubling procedure
  ## with signature
  ##   `void name(CurveType r, CurveType p)`
  ## with `p` the EC point to be doubled and stored in `r`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_double_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, p]),
          {kHot}):
    tagParameter(1, "sret")
    let (ri, pi) = llvmParams
    let P = asy.asEcPointJac(pi, cd.curveTy)
    let rA = asy.asEcPointJac(ri, cd.curveTy)

    ## Helper templates to allow the logic below to be roughly equivalent to the regular
    ## CPU code in `ec_shortweierstrass_jacobian.nim`.

    ## XXX: These helpers will likely become either a template to be used in other EC
    ## procs in the near term or exported templates using the `Field` and `EcPointJac` types
    ## for overload resolution in the longer term. Still, the explicit `asy/ed` dependencies
    ## makes it difficult to provide a clean API without -- effectively -- hacky templates,
    ## unless we absorb not only the `Builder` in the `Field` / `EcPointJac` objects, but also
    ## the full `asy`/`ed` types as refs. It is an option though.

    # Make operations more convenient, for fields:
    declFieldOps(asy, cd.fd)
    # and for EC points
    declEllipticJacOps(asy, cd)

    var
      A = asy.newField(cd.fd)
      B = asy.newField(cd.fd)
      C = asy.newField(cd.fd)

    # "dbl-2009-l" doubling formula - https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html#doubling-dbl-2009-l
    #
    #     Cost: 2M + 5S + 6add + 3*2 + 1*3 + 1*8.
    #     Source: 2009.04.01 Lange.
    #     Explicit formulas:
    #
    #           A = X₁²
    #           B = Y₁²
    #           C = B²
    #           D = 2*((X₁+B)²-A-C)
    #           E = 3*A
    #           F = E²
    #           X₃ = F-2*D
    #           Y₃ = E*(D-X₃)-8*C
    #           Z₃ = 2*Y₁*Z₁
    #
    A.square(P.x)
    B.square(P.y)
    C.square(B)
    B += P.x
    # aliasing: we don't use P.x anymore

    B.square()
    B -= A
    B -= C
    B.double()         # D = 2*((X₁+B)²-A-C)
    A *= 3             # E = 3*A
    rA.x.square(A)      # F = E²

    rA.x -= B
    rA.x -= B           # X₃ = F-2*D

    B -= rA.x           # (D-X₃)
    A *= B             # E*(D-X₃)
    C *= 8

    rA.z.prod(P.z, P.y)
    rA.z.double()       # Z₃ = 2*Y₁*Z₁
    # aliasing: we don't use P.y, P.z anymore

    rA.y.diff(A, C)     # Y₃ = E*(D-X₃)-8*C

    asy.br.retVoid()

  asy.callFn(name, [r, p])

proc mixedSum*(asy: Assembler_LLVM, cd: CurveDescriptor, r, p, q: ValueRef) =
  ## Generate an internal elliptic curve point addition proc
  ## a point in Jacobian and another in Affine coordinates
  ## with signature
  ##   `void name(CurveType r, CurveTypeJac p, CurveTypeAff q)`
  ## with `a` and `b` EC curve point elements to be added.
  ## The result is stored in `r`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = cd.name & "_mixedSum_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, p, q]),
          {kHot}):
    tagParameter(1, "sret")
    let (ri, pi, qi) = llvmParams
    let P = asy.asEcPointJac(pi, cd.curveTy)
    let Q = asy.asEcPointAff(qi, cd.curveTyAff)
    let rA = asy.asEcPointJac(ri, cd.curveTy)

    ## Helper templates to allow the logic below to be roughly equivalent to the regular
    ## CPU code in `ec_shortweierstrass_jacobian.nim`.
    # Make finite field point operations nicer
    declFieldOps(asy, cd.fd)
    # And EC points
    declEllipticJacOps(asy, cd)
    # and for Affine
    declEllipticAffOps(asy, cd)

    var
      Z1Z1 = asy.newField(cd.fd)
      U1   = asy.newField(cd.fd)
      S1   = asy.newField(cd.fd)
      H    = asy.newField(cd.fd)
      R    = asy.newField(cd.fd)

    block: # Addition-only, check for exceptional cases
      var
        U2 = asy.newField(cd.fd)
        S2   = asy.newField(cd.fd)

      U1 = P.x
      S1 = P.y

      ## XXX: either of these `skipFinalSub = true` breaks the code at some point.
      ## See also `tests/gpu/t_ec_sum.nim`.
      Z1Z1.square(P.z, skipFinalSub = false) #not (cd.coef_a == -3))
      S2.prod(P.z, Z1Z1, skipFinalSub = false)
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
      HH_or_YY = asy.newField(cd.fd)
      HHH_or_Mpre = asy.newField(cd.fd)

    H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
    HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

    V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
    V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

    block: # Compute M for doubling
      if cd.coef_a == 0:
        var
          a = asy.newField(cd.fd)
          b = asy.newField(cd.fd)
        store(a, H)
        store(b, HH_or_YY)
        a.ccopy(P.x, isDbl)           # H or X₁
        b.ccopy(P.x, isDbl)           # HH or X₁
        HHH_or_Mpre.prod(a, b)        # HHH or X₁²

        var M = asy.newField(cd.fd)   # Assuming on doubling path
        store(M, HHH_or_Mpre)

        M.div2()                      #  X₁²/2
        M += HHH_or_Mpre              # 3X₁²/2
        R_or_M.ccopy(M, isDbl)

      elif cd.coef_a == -3:
        var
          a = asy.newField(cd.fd)
          b = asy.newField(cd.fd)
        a.sum(P.x, Z1Z1)
        b.diff(P.z, Z1Z1)
        a.ccopy(H_or_Y, not isDbl)    # H   or X₁+ZZ
        b.ccopy(HH_or_YY, not isDbl)  # HH  or X₁-ZZ
        HHH_or_Mpre.prod(a, b)        # HHH or X₁²-ZZ²

        var M = asy.newField(cd.fd)   # Assuming on doubling path
        store(M, HHH_or_Mpre)

        M.div2()                      # (X₁²-ZZ²)/2
        M += HHH_or_Mpre              # 3(X₁²-ZZ²)/2
        R_or_M.ccopy(M, isDbl)

      else:
        # TODO: Costly `a` coefficients can be computed
        # by merging their computation with Z₃ = Z₁*Z₂*H (add) or Z₃ = Y₁*Z₁ (dbl)
        var
          a = asy.newField(cd.fd)
          b = asy.newField(cd.fd)
        store(a, H)
        store(b, HH_or_YY)
        a.ccopy(P.x, isDbl)
        b.ccopy(P.x, isDbl)
        HHH_or_Mpre.prod(a, b)        # HHH or X₁²

        # Assuming doubling path
        a.square(HHH_or_Mpre, skipFinalSub = true)
        a *= HHH_or_Mpre              # a = 3X₁²
        b.square(Z1Z1)
        b.mulCheckSparse(cd.coef_a)   # b = αZZ, with α the "a" coefficient of the curve

        a += b
        a.div2()
        R_or_M.ccopy(a, isDbl)        # (3X₁² - αZZ)/2

    # Let's count our horses, at this point:
    # - R_or_M is set with R (add) or M (dbl)
    # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
    # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)

    var o = asy.newEcPointJac(cd)
    block: # Finishing line
      var t = asy.newField(cd.fd)
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

      t.setOne()
      t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
      t.prod(t, P.z) # , true)           # Z₁Z₂ (add) or Y₁Z₁ (dbl)
      o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
      o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)

    block: # Infinity points
      o.x.ccopy(Q.x, P.isNeutral())
      o.y.ccopy(Q.y, P.isNeutral())
      o.z.csetOne(P.isNeutral())

      o.ccopy(P, Q.isNeutral())

    store(rA, o)

    asy.br.retVoid()

  asy.callFn(name, [r, p, q])
