# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[strformat, strutils, macros, strtabs]

# Overview
# ------------------------------------------------------------
#
# This files provides template for C header generation

proc genHeaderLicense*(): string =
  """
/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
"""

proc genHeader*(name, body: string): string =
  &"""
#ifndef __CTT_H_{name}__
#define __CTT_H_{name}__

{body}

#endif
"""

proc genCpp*(body: string): string {.raises:[ValueError].} =
  &"""
#ifdef __cplusplus
extern "C" {{
#endif

{body}

#ifdef __cplusplus
}}
#endif
"""

# Types' declarations
# -------------------------------------------

proc genBuiltinsTypes*(): string =
  """
#if defined(__SIZE_TYPE__) && defined(__PTRDIFF_TYPE__)
typedef __SIZE_TYPE__    size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#else
#include <stddef.h>
#endif

#if defined(__UINT8_TYPE__) && defined(__UINT32_TYPE__) && defined(__UINT64_TYPE__)
typedef __UINT8_TYPE__   uint8_t;
typedef __UINT32_TYPE__  uint32_t;
typedef __UINT64_TYPE__  uint64_t;
#else
#include <stdint.h>
#endif

#if defined(__STDC_VERSION__) && __STDC_VERSION__>=199901
# define bool _Bool
#else
# define bool unsigned char
#endif
"""

proc genCttBaseTypedef*(): string =
  """
typedef size_t           secret_word;
typedef size_t           secret_bool;
typedef uint8_t          byte;
"""

proc genWordsRequired*(): string =
  """
#define WordBitWidth         (sizeof(secret_word)*8)
#define words_required(bits) ((bits+WordBitWidth-1)/WordBitWidth)
"""

proc genField*(name: string, bits: int): string =
  &"typedef struct {{ secret_word limbs[words_required({bits})]; }} {name};"

proc genExtField*(name: string, degree: int, basename: string): string =
  &"typedef struct {{ {basename} c[{degree}]; }} {name};"

proc genEllipticCurvePoint*(name, coords, basename: string): string =
  &"typedef struct {{ {basename} {coords}; }} {name};"

# Nim internals
# -------------------------------------------

proc declNimMain*(libName: string): string =
  ## Create the NimMain function.
  ## It initializes:
  ## - the Nim runtime if seqs, strings or heap-allocated types are used,
  ##   this is the case only if Constantine is multithreaded.
  ## - runtime CPU features detection
  ##
  ## Assumes library is compiled with --nimMainPrefix:ctt_{libName}_
  &"""

/*
 * Initializes the library:
 * - detect CPU features like ADX instructions support (MULX, ADCX, ADOX)
 */
void ctt_{libName}_init_NimMain(void);"""

# Subroutines' declarations
# -------------------------------------------

let TypeMap {.compileTime.} = newStringTable({
  "bool": "bool",
  "SecretBool": "secret_bool",
  "SecretWord": "secret_word"
})

proc toCrettype(node: NimNode): string =
  node.expectKind({nnkEmpty, nnkSym})
  if node.kind == nnkEmpty:
    # align iwth secret_bool and secret_word
    "void       "
  else:
    TypeMap[$node]

proc toCtrivialParam(name: string, typ: NimNode): string =
  typ.expectKind({nnkVarTy, nnkSym})

  let isVar = typ.kind == nnkVarTy
  let constify = if isVar: ""
                 else: "const "

  let sTyp = if isVar: $typ[0]
             else: $typ

  if sTyp in TypeMap:
    # Pass-by-value
    constify & TypeMap[sTyp] & " " & name
  else:
    # Pass-by-reference
    constify & sTyp & "* " & name

proc toCparam(name: string, typ: NimNode): string =
  typ.expectKind({nnkVarTy, nnkCall, nnkSym})

  if typ.kind == nnkCall:
    typ[0].expectKind(nnkOpenSymChoice)
    doAssert typ[0][0].eqIdent"[]"
    doAssert typ[1].eqIdent"openArray"
    let sTyp = $typ[2]
    if sTyp in TypeMap:
      "const " & TypeMap[sTyp] & " "  & name & "[], ptrdiff_t " & name & "_len"
    else:
      "const " & sTyp & " " & name & "[], ptrdiff_t " & name & "_len"
  elif typ.kind == nnkVarTy and typ[0].kind == nnkCall:
    typ[0][0].expectKind(nnkOpenSymChoice)
    doAssert typ[0][0][0].eqIdent"[]"
    doAssert typ[0][1].eqIdent"openArray"
    let sTyp = $typ[0][2]
    if sTyp in TypeMap:
      TypeMap[sTyp] & " " & name & "[], ptrdiff_t " & name & "_len"
    else:
      sTyp & " " & name & "[], ptrdiff_t " & name & "_len"
  else:
    toCtrivialParam(name, typ)

macro collectBindings*(cBindingsStr: untyped, body: typed): untyped =
  ## Collect function definitions from a generator template

  body.expectKind(nnkStmtList)

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

  if defined(CTT_GENERATE_HEADERS):
    result = newConstStmt(cBindingsStr, newLit cBindings)
  else:
    result = body
