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

proc genHeaderGuardAndInclude*(name, body: string): string =
  &"""
#ifndef __CTT_H_{name}__
#define __CTT_H_{name}__

#include "constantine/core/datatypes.h"
{body}
#endif // __CTT_H_{name}__
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
# define ctt_bool _Bool
#else
# define ctt_bool unsigned char
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
#define CTT_WORD_BITWIDTH        (sizeof(secret_word)*8)
#define CTT_WORDS_REQUIRED(bits) ((bits+WordBitWidth-1)/WordBitWidth)
"""

proc genBigInt*(bits: int): string =
  &"typedef struct {{ secret_word limbs[CTT_WORDS_REQUIRED({bits})]; }} big{bits};"

proc genField*(name: string, bits: int): string =
  &"typedef struct {{ secret_word limbs[CTT_WORDS_REQUIRED({bits})]; }} {name};"

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
  "bool":       "ctt_bool   ",
  "SecretBool": "secret_bool",
  "SecretWord": "secret_word",

  # Parallel only, proc are so long we don't care about alignment
  "csize_t":    "size_t",
  "Threadpool": "const ctt_threadpool*"
})

proc toCrettype*(node: NimNode): string =
  node.expectKind({nnkEmpty, nnkSym})
  if node.kind == nnkEmpty:
    # align iwth secret_bool and secret_word
    "void       "
  else:
    TypeMap[$node]

proc toCtrivialParam*(name: string, typ: NimNode): string =
  typ.expectKind({nnkVarTy, nnkPtrTy, nnkSym})

  let isVar = typ.kind == nnkVarTy
  let isPtr = typ.kind == nnkPtrTy

  let constify = if isVar: ""
                 else: "const "
  let ptrify = isVar or isPtr

  let sTyp = if ptrify: $typ[0]
             else: $typ

  if sTyp in TypeMap:
    # Pass-by-value unless explicit pointer
    # if explicit pointer, apply `const` modifier where relevant
    let ptrify = if ptrify: "*"
                 else: ""
    if isPtr:
      constify & TypeMap[sTyp] & ptrify & " " & name
    else:
      TypeMap[sTyp] & ptrify & " " & name
  else:
    # Pass-by-reference
    constify & sTyp & "* " & name

proc toCparam*(name: string, typ: NimNode): string =
  typ.expectKind({nnkVarTy, nnkCall, nnkSym, nnkPtrTy})

  if typ.kind == nnkCall:
    typ[0].expectKind(nnkOpenSymChoice)
    doAssert typ[0][0].eqIdent"[]"
    doAssert typ[1].eqIdent"openArray", block:
      typ.treeRepr()
    let sTyp = $typ[2]
    if sTyp in TypeMap:
      "const " & TypeMap[sTyp] & " "  & name & "[], size_t " & name & "_len"
    else:
      "const " & sTyp & " " & name & "[], size_t " & name & "_len"
  elif typ.kind == nnkVarTy and typ[0].kind == nnkCall:
    typ[0][0].expectKind(nnkOpenSymChoice)
    doAssert typ[0][0][0].eqIdent"[]"
    doAssert typ[0][1].eqIdent"openArray"
    let sTyp = $typ[0][2]
    if sTyp in TypeMap:
      TypeMap[sTyp] & " " & name & "[], size_t " & name & "_len"
    else:
      sTyp & " " & name & "[], size_t " & name & "_len"
  elif typ.kind == nnkPtrTy and typ[0].kind == nnkCall:
    typ[0][0].expectKind(nnkOpenSymChoice)
    doAssert typ[0][0][0].eqIdent"[]"
    doAssert typ[0][1].eqIdent"UncheckedArray"

    let innerType = typ[0][2].getTypeInst()
    if innerType.kind == nnkBracketExpr:
      doAssert innerType[0].eqIdent"BigInt"
      "const big" & $innerType[1].intVal & " " & name & "[]"
    else:
      let sTyp = $innerType
      if sTyp in TypeMap:
        "const " & TypeMap[sTyp] & " " & name & "[]"
      else:
        "const " & sTyp & " " & name & "[]"
  else:
    toCtrivialParam(name, typ)
