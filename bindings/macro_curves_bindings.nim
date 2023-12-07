# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when not defined(CTT_MAKE_HEADERS):
  template collectBindings*(cBindingsStr: untyped, body: typed): untyped =
    body
else:
  # We gate `c_typedefs` as it imports strutils
  # which uses the {.rtl.} pragma and might compile in Nim Runtime Library procs
  # that cannot be removed.
  #
  # We want to ensure its only used for header generation, not in deployment.
  import ./c_typedefs
  import std/[macros, strutils]

  macro collectBindings*(cBindingsStr: untyped, body: typed): untyped =
    ## Collect function definitions from a generator template
    var cBindings: string
    for generator in body:
      generator.expectKind(nnkStmtList)
      for fnDef in generator:
        if fnDef.kind notin {nnkProcDef, nnkFuncDef}:
          continue

        cBindings &= "\n"
        # rettype name(pType0* pName0, pType1* pName1, ...);
        cBindings &= fnDef.params[0].toCrettype()
        cBindings &= ' '
        cBindings &= $fnDef.name
        cBindings &= '('
        for i in 1 ..< fnDef.params.len:
          if i != 1: cBindings &= ", "

          let paramDef = fnDef.params[i]
          paramDef.expectKind(nnkIdentDefs)
          let pType = paramDef[^2]
          # No default value
          paramDef[^1].expectKind(nnkEmpty)

          for j in 0 ..< paramDef.len - 2:
            if j != 0: cBindings &= ", "
            var name = $paramDef[j]
            cBindings &= toCparam(name.split('`')[0], pType)

        if fnDef.params[0].eqIdent"bool":
          cBindings &= ") __attribute__((warn_unused_result));"
        else:
          cBindings &= ");"


      result = newConstStmt(nnkPostfix.newTree(ident"*", cBindingsStr), newLit cBindings)
