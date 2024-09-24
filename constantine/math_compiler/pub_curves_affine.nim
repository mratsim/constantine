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
  ./impl_fields_dispatch,
  std / typetraits # for distinctBase

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.pub_curves_affine"

type
  EcPointAff* {.borrow: `.`.} = distinct Array

proc asEcPointAff*(asy: Assembler_LLVM, arrayPtr: ValueRef, arrayTy: TypeRef): EcPointAff =
  ## Constructs an elliptic curve point in Affine coordinates from an array pointer.
  ##
  ## `arrayTy` is an `array[FieldTy, 2]` where `FieldTy` itsel is an array of
  ## `array[WordTy, NumWords]`.
  result = EcPointAff(asy.asArray(arrayPtr, arrayTy))

proc asEcPointAff*(asy: Assembler_LLVM, ed: CurveDescriptor, arrayPtr: ValueRef): EcPointAff =
  ## Constructs an elliptic curve point in Affine coordinates from an array pointer,
  ## taking the required `arrayTy` from the `CurveDescriptor`.
  ##
  ## `arrayTy` is an `array[FieldTy, 2]` where `FieldTy` itsel is an array of
  ## `array[WordTy, NumWords]`.
  result = EcPointAff(asy.asArray(arrayPtr, ed.curveTyAff))

proc newEcPointAff*(asy: Assembler_LLVM, ed: CurveDescriptor): EcPointAff =
  ## Use field descriptor for size etc?
  result = EcPointAff(asy.makeArray(ed.curveTyAff))

func getIdx*(br: BuilderRef, ec: EcPointAff, idx: int): Field =
  let pelem = distinctBase(ec).getElementPtr(0, idx)
  result = br.asField(pelem, ec.elemTy)

func getX*(ec: EcPointAff): Field = ec.builder.getIdx(ec, 0)
func getY*(ec: EcPointAff): Field = ec.builder.getIdx(ec, 1)

proc store*(dst: EcPointAff, src: EcPointAff) =
  ## Stores the `dst` in `src`. Both must correspond to the same field of course.
  assert dst.arrayTy.getArrayLength() == src.arrayTy.getArrayLength()
  store(dst.getX(), src.getX())
  store(dst.getY(), src.getY())


#func isNeutral*(P: EC_ShortW_Aff): SecretBool =
#  ## Returns true if P is the neutral element / identity element
#  ## and false otherwise, i.e. ∀Q, P+Q == Q
#  ## For Short Weierstrass curves, this is the infinity point.
#  result = P.x.isZero() and P.y.isZero()

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

    template isZero(res, x): untyped = asy.isZero_internal(ed.fd, res, x.buf)
    template isZero(x): untyped =
      var res = asy.br.alloca(asy.ctx.int1_t())
      asy.isZero_internal(ed.fd, res, x.buf)
      res
    template derefBool(x): untyped = asy.load2(asy.ctx.int1_t(), x)
    template `and`(x, y): untyped =
      var res = asy.br.alloca(asy.ctx.int1_t())
      res = asy.br.`and`(derefBool x, derefBool y)
      res
    template x(ec: EcPointAff): Field = ec.getX()
    template y(ec: EcPointAff): Field = ec.getY()

    let (ri, ai) = llvmParams

    let P = asy.asEcPointAff(ed, ai)

    asy.store(ri, P.x.isZero() and P.y.isZero())

    asy.br.retVoid()

  asy.callFn(name, [r, a])

proc genEcIsNeutral*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  ## Generate a public elliptic curve point isNeutral proc
  ## with signature
  ##   void name(*bool r, CurveType a)
  ## with r the result and a the operand
  ## and return the corresponding name to call it

  let name = ed.name & "aff_isNeutral"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ptrBool, ed.curveTy]):
    let (r, a) = llvmParams
    asy.isNeutral_internal(ed, r, a)
    asy.br.retVoid()

  return name
