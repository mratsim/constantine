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
  ./impl_curves_ops_jacobian

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.pub_curves_jacobian"

proc genEcFromAffine*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point `fromAffine` proc
  ## with signature
  ##   void name(CurveTypeJac r, CurveTypeAff a)
  ## with r the result and a the input in affine coordinates
  ## and return the corresponding name to call it

  let name = cd.name & "_isNeutral"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy, cd.curveTyAff]):
    let (jac, aff) = llvmParams
    asy.fromAffine(cd, jac, aff)
    asy.br.retVoid()

  return name

proc genEcIsNeutral*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point isNeutral proc
  ## with signature
  ##   void name(*bool r, CurveType a)
  ## with r the result and a the operand
  ## and return the corresponding name to call it

  let name = cd.name & "_isNeutral"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [ptrBool, cd.curveTy]):
    let (r, a) = llvmParams
    asy.isNeutral(cd, r, a)
    asy.br.retVoid()

  return name

proc genEcSetNeutral*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point `setNeutral` proc
  ## with signature
  ##   void name(CurveType a)
  ## with a the EC point to be set to the neutral element.
  ##
  ## It returns the corresponding name to call it
  let name = cd.name & "_setNeutral"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy]):
    let r = llvmParams
    asy.setNeutral(cd, r)
    asy.br.retVoid()

  return name

proc genEcCcopy*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point ccopy proc
  ## with signature
  ##   `void name(CurveType a, CurveType b, bool condition)`
  ## with `a` and `b` EC curve point elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodificd.
  ## and return the corresponding name to call it

  let name = cd.name & "_ccopy"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy, cd.curveTy, asy.ctx.int1_t()]):
    let (a, b, c) = llvmParams
    asy.ccopy(cd, a, b, c)
    asy.br.retVoid()

  return name

proc genEcNeg*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point neg proc
  ## with signature
  ##   `void name(CurveType a)`
  ## with `a` the EC curve point to be negatcd.
  ## and return the corresponding name to call it

  let name = cd.name & "_neg"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy]):
    let a = llvmParams
    asy.neg(cd, a)
    asy.br.retVoid()

  return name

proc genEcCneg*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point conditional neg proc
  ## with signature
  ##   `void name(CurveType a, bool condition)`
  ## with `a` the EC curve point to be negated if `condition` is true.
  ## Returns the name to call the kernel.

  let name = cd.name & "_neg"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy, asy.ctx.int1_t()]):
    let (a, c) = llvmParams
    asy.cneg(cd, a, c)
    asy.br.retVoid()

  return name

proc genEcSum*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a publc elliptic curve point addition proc
  ## with signature
  ##   `void name(CurveType r, CurveType p, CurveType q)`
  ## with `a` and `b` EC curve point elements to be added.
  ## The result is stored in `r`.
  ##
  ## Returns the name of the produced kernel to call it.
  let name = cd.name & "_sum"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy, cd.curveTy, cd.curveTy]):
    let (ri, pi, qi) = llvmParams
    asy.sum(cd, ri, pi, qi)
    asy.br.retVoid()
  result = name

proc genEcDouble*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a publc elliptic curve point doubling proc
  ## with signature
  ##   `void name(CurveType r, CurveType p)`
  ## with `p` the EC point to be doubled and stored in `r`.
  ##
  ## Returns the name of the produced kernel to call it.
  let name = cd.name & "_double"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy, cd.curveTy]):
    let (ri, pi) = llvmParams
    asy.double(cd, ri, pi)
    asy.br.retVoid()
  result = name

proc genEcMixedSum*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a publc elliptic curve point addition proc between
  ## a point in Jacobian and another in Affine coordinates
  ## with signature
  ##   `void name(CurveType r, CurveTypeJac p, CurveTypeAff q)`
  ## with `a` and `b` EC curve point elements to be added.
  ## The result is stored in `r`.
  ##
  ## Returns the name of the produced kernel to call it.
  let name = cd.name & "_mixedSum"
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [cd.curveTy, cd.curveTy, cd.curveTyAff]):
    let (ri, pi, qi) = llvmParams
    asy.mixedSum(cd, ri, pi, qi)
    asy.br.retVoid()
  result = name
