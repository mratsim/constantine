# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                     Trace operations
#
# ############################################################

# Types
# --------------------------------------------------

const CTT_METER {.booldefine.} = off
const CTT_TRACE {.booldefine.} = off # For manual "debug-echo"-style timing.

when CTT_METER or CTT_TRACE:

  import ./benchmarking

  type
    Metadata* = object
      procName*: string
      module: string
      package: string
      tag: string # Can be change to multi-tags later
      numCalls*: int64
      cumulatedTimeNs*: int64 # in microseconds
      when SupportsGetTicks:
        cumulatedCycles*: int64

  var ctMetrics{.compileTime.}: seq[Metadata]
    ## Metrics are collected here, this is just a temporary holder of compileTime values
    ## Unfortunately the "seq" is emptied when passing the compileTime/runtime boundaries
    ## due to Nim bugs


  # strformat doesn't work in templates.
  from strutils import alignLeft, formatFloat
  import std/[macros, times, monotimes]

  var Metrics*: seq[Metadata]
    ## We can't directly use it at compileTime because it doesn't exist.
    ## We need `Metrics = static(ctMetrics)`
    ## To transfer the compileTime content to runtime at an opportune time.

  proc resetMetering*() =
    Metrics = static(ctMetrics)


  # Utils
  # --------------------------------------------------
  const someGcc = defined(gcc) or defined(llvm_gcc) or defined(clang) or defined(icc)
  const hasThreadSupport = defined(threads)

  proc atomicInc*(memLoc: var int64, x = 1'i64): int64 =
    when someGcc and hasThreadSupport:
      result = atomicAddFetch(memLoc.addr, x, ATOMIC_RELAXED)
    elif defined(vcc) and hasThreadSupport:
      result = addAndFetch(memLoc.addr, x)
      result += x
    else:
      memloc += x
      result = memLoc

  # Symbols
  # --------------------------------------------------

  template fnEntry(name: string, id: int, startTime, startCycle: untyped): untyped =
    ## Bench tracing to insert on function entry
    {.noSideEffect, gcsafe.}:
      discard Metrics[id].numCalls.atomicInc()
      let startTime = getMonoTime()
      when SupportsGetTicks:
        let startCycle = getTicks()
      else:
        let startCycle = 0

  template fnExit(name: string, id: int, startTime, startCycle: untyped): untyped =
    ## Bench tracing to insert before each function exit
    {.noSideEffect, gcsafe.}:
      when SupportsGetTicks:
        let stopCycle = getTicks()
      let stopTime = getMonoTime()
      when SupportsGetTicks:
        let elapsedCycles = stopCycle - startCycle
      let elapsedTime = inNanoseconds(stopTime - startTime)

      discard Metrics[id].cumulatedTimeNs.atomicInc(elapsedTime)
      when SupportsGetTicks:
        discard Metrics[id].cumulatedCycles.atomicInc(elapsedCycles)

      when CTT_TRACE:
        # Advice: Use "when name == relevantProc" to isolate specific procedures.
        # strformat doesn't work in templates.
        when SupportsGetTicks:
          echo static(alignLeft(name, 50)),
              "Time (µs): ", alignLeft(formatFloat(elapsedTime.float64 * 1e-3, precision=3), 10),
              "Cycles (billions): ", formatFloat(elapsedCycles.float64 * 1e-9, precision=3)
        else:
          echo static(alignLeft(name, 50)),
              "Time (µs): ", alignLeft(formatFloat(elapsedTime.float64 * 1e-3, precision=3), 10)

  macro meterAnnotate(procAst: untyped): untyped =
    procAst.expectKind({nnkProcDef, nnkFuncDef})

    let id = ctMetrics.len
    let name = procAst[0].repr & procAst[3].repr
    # TODO, get the module and the package the proc is coming from
    #       and the tag "Fp", "ec", "polynomial" ...

    ctMetrics.add Metadata(procName: name)
    var newBody = newStmtList()
    let startTime = genSym(nskLet, "metering_" & name & "_startTime_")
    let startCycle = genSym(nskLet, "metering_" & name & "_startCycles_")
    newBody.add getAst(fnEntry(name, id, startTime, startCycle))
    newbody.add nnkDefer.newTree(getAst(fnExit(name, id, startTime, startCycle)))
    newBody.add procAst.body

    if procAst[4].kind != nnkEmpty:
      # Timing procedures adds the TimeEffect tag, which interferes with {.tags:[VarTime].}
      # as TimeEffect is not listed. We drop the `tags` for metering
      var pragmas: NimNode
      if procAst[4].len == 1:
        if procAst[4][0].kind == nnkExprColonExpr and procAst[4][0][0].eqIdent"tags":
          pragmas = newEmptyNode()
        else:
          pragmas = procAst[4]
      else:
        pragmas = nnkPragma.newTree()
        for i in 0 ..< procAst[4].len:
          if procAst[4][0].kind == nnkExprColonExpr and procAst[4][0][0].eqIdent"tags":
            continue
          else:
            pragmas.add procAst[4][0]
      procAst[4] = pragmas

    procAst.body = newBody
    result = procAst

template meter*(procBody: untyped): untyped =
  when CTT_METER or CTT_TRACE:
    meterAnnotate(procBody)
  else:
    procBody

# Sanity checks
# ---------------------------------------------------

when isMainModule:

  static: doAssert CTT_METER or CTT_TRACE, "CTT_METER or CTT_TRACE must be on for tracing"

  when CTT_METER or CTT_TRACE: # Avoid warnings from nim check or nimsuggest
    expandMacros:
      proc foo(x: int): int{.meter.} =
        echo "Hey hey hey"
        result = x

    resetMetering()

    echo Metrics
    discard foo(10)
    echo Metrics
    doAssert Metrics[0].numCalls == 1
