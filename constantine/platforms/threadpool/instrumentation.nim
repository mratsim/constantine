# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import system/ansi_c

# Loggers
# --------------------------------------------------------

template log*(args: varargs[untyped]): untyped =
  c_printf(args)
  flushFile(stdout)

template debugTermination*(body: untyped): untyped =
  when defined(TP_DebugTermination) or defined(TP_Debug):
    {.noSideEffect, gcsafe.}: body

template debug*(body: untyped): untyped =
  when defined(TP_Debug):
    {.noSideEffect, gcsafe.}: body

# --------------------------------------------------------

import std/macros

# A simple design-by-contract API
# --------------------------------------------------------

# Everything should be a template that doesn't produce any code
# when debugConstantine is not defined.
# Those checks are controlled by a custom flag instead of
# "--boundsChecks" or "--nilChecks" to decouple them from user code checks.
# Furthermore, we want them to be very lightweight on performance

func toHex*(a: SomeInteger): string =
  const hexChars = "0123456789abcdef"
  const L = 2*sizeof(a)
  result = newString(2 + L)
  result[0] = '0'
  result[1] = 'x'
  var a = a
  for j in countdown(result.len-1, 0):
    result[j] = hexChars[a and 0xF]
    a = a shr 4

proc inspectInfix(node: NimNode): NimNode =
  ## Inspect an expression,
  ## Returns the AST as string with runtime values inlined
  ## from infix operators inlined.
  # TODO: pointer and custom type need a default repr
  #       otherwise we can only resulve simple expressions
  proc inspect(node: NimNode): NimNode =
    case node.kind:
    of nnkInfix:
      return newCall(
          bindSym"&",
          newCall(
            bindSym"&",
            newCall(ident"$", inspect(node[1])),
            newLit(" " & $node[0] & " ")
          ),
          newCall(ident"$", inspect(node[2]))
        )
    of {nnkIdent, nnkSym}:
      return node
    of nnkDotExpr:
      return quote do:
        when `node` is pointer or
             `node` is ptr or
             `node` is (proc):
          toHex(cast[ByteAddress](`node`) and 0xffff_ffff)
        else:
          $(`node`)
    of nnkPar:
      result = nnkPar.newTree()
      for sub in node:
        result.add inspect(sub)
    else:
      return node.toStrLit()
  return inspect(node)

macro assertContract(
        checkName: static string,
        predicate: untyped) =
  let lineinfo = lineInfoObj(predicate)

  var strippedPredicate: NimNode
  if predicate.kind == nnkStmtList:
    assert predicate.len == 1, "Only one-liner conditions are supported"
    strippedPredicate = predicate[0]
  else:
    strippedPredicate = predicate

  let debug = "\n    Contract violated for " & checkName & " at " & $lineinfo &
              "\n        " & $strippedPredicate.toStrLit &
              "\n    The following values are contrary to expectations:" &
              "\n        "
  let values = inspectInfix(strippedPredicate)
  let workerID = quote do:
    when declared(workerContext):
      $workerContext.id
    else:
      "N/A"
  let threadpoolID = quote do:
    when declared(workerContext):
      cast[ByteAddress](workerContext.threadpool).toHex()
    else:
      "N/A"

  result = quote do:
    {.noSideEffect.}:
      when compileOption("assertions"):
        assert(`predicate`, `debug` & $`values` & "  [Worker " & `workerID` & " on threadpool " & `threadpoolID` & "]\n")
      elif defined(TP_Asserts):
        if unlikely(not(`predicate`)):
          raise newException(AssertionError, `debug` & $`values` & "  [Worker " & `workerID` & " on threadpool " & `threadpoolID` & "]\n")


template preCondition*(require: untyped) =
  ## Optional runtime check before returning from a function
  assertContract("pre-condition", require)

template postCondition*(ensure: untyped) =
  ## Optional runtime check at the start of a function
  assertContract("post-condition", ensure)

template ascertain*(check: untyped) =
  ## Optional runtime check in the middle of processing
  assertContract("transient condition", check)

# Sanity checks
# ----------------------------------------------------------------------------------

when isMainModule:
  proc assertGreater(x, y: int) =
    postcondition(x > y)

  # We should get a nicely formatted exception
  assertGreater(10, 12)
