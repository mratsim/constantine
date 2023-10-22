# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# This module allows flexible exports of procedures.
# 1. This allows configuring all exported names from the protocol files
#    instead of having those in many different places.
# 2. No extra public wrapper proc are needed, reducing function call/return overhead.
#    i.e. if we have an inner sha256.hash function
#         and we need an exported `ctt_sha256_hash` and we also have a `hash_to_curve` function
#         that internally uses `sha256.hash`,
#         the ideal outcome is for `sha256.hash to be exported as `ctt_sha256_hash` and
#         have `hash_to_curve` directly use that.
# 3. Furthermore while compiling Nim only, no export marker (noconv, dynlib, exportc) are used.
#
# Each prefix must be modified before importing the module to export

# Exportable functions
# ----------------------------------------------------------------------------------------------
# A module that import these functions can modify their C prefix, if needed.
# By assigning to the prefix, in a static block **before** importing the module.

var prefix_sha256* {.compileTime.} = "ctt_sha256_"

# Conditional exports
# ----------------------------------------------------------------------------------------------

import std/macros

macro libPrefix*(prefix: static string, procAst: untyped): untyped =
  if prefix == "":
    return procAst
  else:
    var pragmas = procAst.pragma
    if pragmas.kind == nnkEmpty:
      pragmas = nnkPragma.newTree()

    pragmas.add ident"noconv"
    pragmas.add nnkExprColonExpr.newTree(
      ident"exportc",
      newLit(prefix & "$1"))
    pragmas.add nnkExprColonExpr.newTree(
      ident"raises",
      nnkBracket.newTree())

    if appType == "lib":
      pragmas.add ident"dynlib"

    result = procAst
    result.pragma = pragmas
