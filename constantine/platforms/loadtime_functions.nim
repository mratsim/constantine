# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                   Load-time functions
#
# ############################################################
#
# Implement functions that are automatically called at program/library load time.
# Note: They cannot use {.global.} variables as {.global.} are initialized by Nim routines

import std/macros, ./config

macro loadTime*(procAst: untyped): untyped =
  ## This allows a function to be called at program or library load time
  ## Note: such a function cannot be dead-code eliminated.

  procAst.addPragma(ident"used")     # Remove unused warning
  procAst.addPragma(ident"exportc")  # Prevent the proc from being dead-code eliminated

  if GCC_Compatible:
    # {.pragma: gcc_constructor, codegenDecl: "__attribute__((constructor)) $# $#$#".}
    let gcc_constructor =
        nnkExprColonExpr.newTree(
          ident"codegenDecl",
          newLit"__attribute__((constructor)) $# $#$#"
        )
    procAst.addPragma(gcc_constructor) # Implement load-time functionality

    result = procAst

  elif defined(vcc):
    warning "CPU feature autodetection at Constantine load time has not been tested with MSVC"

    template msvcInitSection(procDef: untyped): untyped =
      let procName = astToStr(def)
      procDef
      {.emit:["""
      #pragma section(".CRT$XCU",read)
      __declspec(allocate(".CRT$XCU")) static int (*p)(void) = """, procName, ";"].}

    result = getAst(msvcInitSection(procAst))

  else:
    error "Compiler not supported."