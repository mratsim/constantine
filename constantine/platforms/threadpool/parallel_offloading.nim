# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ./crossthread/tasks_flowvars

# Task parallelism - spawn
# ---------------------------------------------

proc spawnVoid(funcCall: NimNode, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  # Create the async function
  let fn = funcCall[0]
  let fnName = $fn
  let withArgs = args.len > 0
  let async_fn = ident("async_" & fnName)
  var fnCall = newCall(fn)
  let data = ident("data")   # typed pointer to data

  # Schedule
  let task = ident"task"
  let scheduleBlock = newCall(schedule, workerContext, task)

  result = newStmtList()

  if funcCall.len == 2:
    # With only 1 arg, the tuple syntax doesn't construct a tuple
    # let data = (123) # is an int
    fnCall.add nnkDerefExpr.newTree(data)
  else: # This handles the 0 arg case as well
    for i in 1 ..< funcCall.len:
      fnCall.add nnkBracketExpr.newTree(
        data,
        newLit i-1
      )

  # Create the async call
  result.add quote do:
    proc `async_fn`(param: pointer) {.nimcall.} =
      when bool(`withArgs`):
        let `data` = cast[ptr `argsTy`](param)
      `fnCall`

  # Create the task
  result.add quote do:
    block enq_deq_task:
      when bool(`withArgs`):
        let `task` = Task.new(
          parent = `workerContext`.currentTask,
          fn = `async_fn`,
          params = `args`)
      else:
        let `task` = Task.new(
          parent = `workerContext`.currentTask,
          fn = `async_fn`)
      `scheduleBlock`

proc spawnRet(funcCall: NimNode, retTy, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  # Create the async function
  let fn = funcCall[0]
  let fnName = $fn
  let async_fn = ident("async_" & fnName)
  var fnCall = newCall(fn)
  let data = ident("data")   # typed pointer to data

  # Schedule
  let task = ident"task"
  let scheduleBlock = newCall(schedule, workerContext, task)

  result = newStmtList()

  # tasks have no return value.
  # 1. The start of the task `data` buffer will store the return value for the flowvar and awaiter/sync
  # 2. We create a wrapper async_fn without return value that send the return value in the channel
  # 3. We package that wrapper function in a task

  # We store the following in task.data:
  #
  # | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  let fut = ident"fut"
  let taskSelfReference = ident"taskSelfReference"
  let retVal = ident"retVal"

  var futArgs = nnkPar.newTree
  var futArgsTy = nnkPar.newTree
  futArgs.add taskSelfReference
  futArgsTy.add nnkPtrTy.newTree(bindSym"Task")
  futArgs.add retVal
  futArgsTy.add retTy

  for i in 1 ..< funcCall.len:
    futArgsTy.add getTypeInst(funcCall[i])
    futArgs.add funcCall[i]

  # data stores | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  # so arguments starts at data[2] in the wrapping funcCall functions
  for i in 1 ..< funcCall.len:
    fnCall.add nnkBracketExpr.newTree(
      data,
      newLit i+1
    )

  result.add quote do:
    proc `async_fn`(param: pointer) {.nimcall.} =
      let `data` = cast[ptr `futArgsTy`](param)
      let res = `fnCall`
      readyWith(`data`[0], res)

  # Regenerate fresh ident, retTy has been tagged as a function call param
  let retTy = ident($retTy)

  # Create the task
  result.add quote do:
    block enq_deq_task:
      let `taskSelfReference` = cast[ptr Task](0xDEADBEEF)
      let `retVal` = default(`retTy`)

      let `task` = Task.new(
        parent = `workerContext`.currentTask,
        fn = `async_fn`,
        params = `futArgs`)
      let `fut` = newFlowvar(`retTy`, `task`)
      `scheduleBlock`
      # Return the future
      `fut`

proc spawnImpl*(tp: NimNode{nkSym}, funcCall: NimNode, workerContext, schedule: NimNode): NimNode =
  funcCall.expectKind(nnkCall)

  # Get the return type if any
  let retType = funcCall[0].getImpl[3][0]
  let needFuture = retType.kind != nnkEmpty

  # Get a serialized type and data for all function arguments
  # We use adhoc tuple
  var argsTy = nnkPar.newTree()
  var args = nnkPar.newTree()
  for i in 1 ..< funcCall.len:
    argsTy.add getTypeInst(funcCall[i])
    args.add funcCall[i]

  # Package in a task
  if not needFuture:
    result = spawnVoid(funcCall, args, argsTy, workerContext, schedule)
  else:
    result = spawnRet(funcCall, retType, args, argsTy, workerContext, schedule)

  # Wrap in a block for namespacing
  result = nnkBlockStmt.newTree(newEmptyNode(), result)
