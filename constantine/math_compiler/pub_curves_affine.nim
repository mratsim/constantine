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
  ./impl_curves_ops_affine

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.pub_curves_affine"

proc genEcIsNeutralAff*(asy: Assembler_LLVM, cd: CurveDescriptor): string =
  ## Generate a public elliptic curve point isNeutral proc
  ## with signature
  ##   void name(*bool r, CurveType a)
  ## with r the result and a the operand
  ## and return the corresponding name to call it

  let name = cd.name & "isNeutralAff"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & cd.name, asy.void_t, [ptrBool, cd.curveTyAff]):
    let (r, a) = llvmParams
    asy.isNeutralAff_internal(cd, r, a)
    asy.br.retVoid()

  return name
