# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ./crossthread/tasks_flowvars

# Parallel offloading API
# -----------------------

# This file implements all the macros necessary
# to provide a comprehensive and hopefully intuitive API
# for all the parallelim paradigms supported:
#
# - Task parallelism
# - Data parallelism / parallel for
#   - parallel-for with thread-local prologue and epilogue
#   - parallel-reduction without atomics or locks
# - Dataflow parallelism
#   - also known as:
#     - Graph parallelism
#     - Stream parallelism
#     - Pipeline parallelism
#     - Data-driven (task) parallelism
#     with precise input/output dependencies

# ############################################################
#                                                            #
#                   Task parallelism                         #
#                                                            #
# ############################################################

proc spawnVoid(funcCall: NimNode, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  # Create the async function
  let fn = funcCall[0]
  let fnName = $fn
  let withArgs = args.len > 0
  let threadpoolSpawn_fn = ident("tpSpawnVoidFn_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("tpSpawnVoidTaskEnv_")   # typed pointer to data

  # Schedule
  let task = ident"tpSpawnVoidTask_"
  let scheduleBlock = newCall(schedule, workerContext, task)

  result = newStmtList()

  if funcCall.len == 2:
    # With only 1 arg, the tuple syntax doesn't construct a tuple
    # let env = (123) # is an int
    fnCall.add nnkDerefExpr.newTree(env)
  else: # This handles the 0 arg case as well
    for i in 1 ..< funcCall.len:
      fnCall.add nnkBracketExpr.newTree(
        env,
        newLit i-1
      )

  # Create the async call
  result.add quote do:
    proc `threadpoolSpawn_fn`(param: pointer) {.nimcall.} =
      when bool(`withArgs`):
        let `env` = cast[ptr `argsTy`](param)
      `fnCall`

  # Create the task
  result.add quote do:
    block enq_deq_task:
      when bool(`withArgs`):
        let `task` = Task.newSpawn(
          parent = `workerContext`.currentTask,
          fn = `threadpoolSpawn_fn`,
          params = `args`)
      else:
        let `task` = Task.newSpawn(
          parent = `workerContext`.currentTask,
          fn = `threadpoolSpawn_fn`)
      `scheduleBlock`

proc spawnRet(funcCall: NimNode, retTy, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  # Create the async function
  let fn = funcCall[0]
  let fnName = $fn
  let threadpoolSpawn_fn = ident("tpSpawnRetFn_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("tpSpawnRetEnv_")   # typed pointer to data

  # Schedule
  let task = ident"tpSpawnRetTask_"
  let scheduleBlock = newCall(schedule, workerContext, task)

  result = newStmtList()

  # tasks have no return value.
  # 1. The start of the task `data` buffer will store the return value for the flowvar and awaiter/sync
  # 2. We create a wrapper threadpoolSpawn_fn without return value that send the return value in the channel
  # 3. We package that wrapper function in a task

  # We store the following in task.data:
  #
  # | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  let fut = ident"tpSpawnRetFut_"
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
      env,
      newLit i+1
    )

  result.add quote do:
    proc `threadpoolSpawn_fn`(param: pointer) {.nimcall.} =
      let `env` = cast[ptr `futArgsTy`](param)
      let res = `fnCall`
      readyWith(`env`[0], res)

  # Regenerate fresh ident, retTy has been tagged as a function call param
  let retTy = ident($retTy)

  # Create the task
  result.add quote do:
    block enq_deq_task:
      let `taskSelfReference` = cast[ptr Task](0xDEADBEEF)
      let `retVal` = default(`retTy`)

      let `task` = Task.newSpawn(
        parent = `workerContext`.currentTask,
        fn = `threadpoolSpawn_fn`,
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

# ############################################################
#                                                            #
#                   Data parallelism                         #
#                                                            #
# ############################################################

proc rebuildUntyped(loopParams: NimNode): NimNode =
  ## In some cases (generics or static proc) Nim gives us
  ## typed NimNode which are hard to process.
  ## This rebuilds the loopParameters to an untyped AST

  if loopParams.kind == nnkInfix:
    result = loopParams
  else:
    # Instead of
    # ---------------
    # Infix
    #   Ident "in"
    #   Ident "i"
    #   Infix
    #     Ident "..<"
    #     IntLit 0
    #     Ident "n"
    #
    # We received
    # ---------------
    # StmtList
    #   Call
    #     OpenSymChoice
    #       Sym "contains"
    #       Sym "contains"
    #       Sym "contains"
    #     Infix
    #       OpenSymChoice
    #         Sym "..<"
    #         Sym "..<"
    #         Sym "..<"
    #         Sym "..<"
    #         Sym "..<"
    #         Sym "..<"
    #       IntLit 0
    #       Ident "n"
    #     Ident "i"
    loopParams[0].expectKind(nnkCall)
    loopParams[0][0].expectKind(nnkOpenSymChoice)
    assert loopParams[0][0][0].eqIdent"contains"
    loopParams[0][1].expectKind(nnkInfix)
    loopParams[0][1][0].expectKind(nnkOpenSymChoice)

    # Rebuild loopParams
    result = nnkInfix.newTree(
      ident"in",
      loopParams[0][2],
      nnkInfix.newTree(
        ident($loopParams[0][1][0][0]),
        loopParams[0][1][1],
        loopParams[0][1][2]
      )
    )

proc checkLP(loopParams: NimNode) =
  ## Checks loop paremeters
  ## --------------------------------------------------------
  ## loopParams should have the form "i in 0..<10"
  loopParams.expectKind(nnkInfix)
  assert loopParams[0].eqIdent"in"
  loopParams[1].expectKind(nnkIdent)
  loopParams[2].expectKind(nnkInfix) # 0 ..< 10 / 0 .. 10, for now we don't support slice objects
  assert loopParams[2][0].eqIdent".." or loopParams[2][0].eqIdent"..<"

proc extractLP(loopParams: NimNode): tuple[idx, start, stop: NimNode] =
  ## Extract the index, start and stop of the loop
  ## Strides must be dealt with separately
  let loopParams = rebuildUntyped(loopParams)
  checkLP(loopParams)
  result.idx = loopParams[1]
  result.start = loopParams[2][1]
  result.stop = loopParams[2][2]
  # We use exclusive bounds
  if loopParams[2][0].eqIdent"..":
    result.stop = newCall(ident"+", result.stop, newLit(1))

proc extractCaptures(body: NimNode, c: int): tuple[captured, capturedTy: NimNode] =
  ## Extract captured variables from the for-loop body.
  ## The capture section is expected at position `c`.
  ## Once extracted the section that declared those captures will be discarded.
  ##
  ## Returns the captured variable and the captured variable types
  ## in a tuple of nnkPar for easy use in tuple construction and destructuring.
  # parallelFor i in 0 ..< 10:
  #   captures: a
  #   ...
  #
  # StmtList
  #   Call
  #     Ident "captures"
  #     StmtList
  #       Curly
  #         Ident "a"
  #   Rest of the body

  body.expectKind(nnkStmtList)
  body[c].expectKind(nnkCall)
  doAssert body[c][0].eqIdent"captures"

  result.captured = nnkPar.newTree()
  result.capturedTy = nnkPar.newTree()

  body[c][1].expectKind(nnkStmtList)
  body[c][1][0].expectKind(nnkCurly)
  for i in 0 ..< body[c][1][0].len:
    result.captured.add body[c][1][0][i]
    result.capturedTy.add newCall(ident"typeof", body[c][1][0][i])

  # Remove the captures section
  body[c] = nnkDiscardStmt.newTree(body[c].toStrLit)

proc extractFutureAndCaptures(body: NimNode): tuple[future, captured, capturedTy: NimNode] =
  ## Extract the result future/flowvar and the captured variables if any
  ## out of a parallelFor / parallelForStrided / parallelForStaged / parallelForStagedStrided
  ## Returns a future, the captured variable and the captured type
  template findCapturesAwaitable(idx: int) =
    if body[idx][0].eqIdent"captures":
      assert result.captured.isNil and result.capturedTy.isNil, "The captured section can only be set once for a loop."
      (result.captured, result.capturedTy) = extractCaptures(body, idx)
    elif body[idx][0].eqIdent"awaitable":
      body[idx][1].expectKind(nnkStmtList)
      body[idx][1][0].expectKind(nnkIdent)
      assert result.future.isNil, "The awaitable section can only be set once for a loop."
      result.future = body[idx][1][0]
      # Remove the awaitable section
      body[idx] = nnkDiscardStmt.newTree(body[idx].toStrLit)

  for i in 0 ..< body.len-1:
    if body[i].kind == nnkCall:
      findCapturesAwaitable(i)

proc packageParallelFor(
        procIdent, wrapperTemplate: NimNode,
        prologue, loopBody, epilogue,
        remoteAccum, returnStmt: NimNode,
        idx, env: NimNode,
        capturedVars, capturedTypes: NimNode,
        resultFvTy: NimNode # For-loops can return a result in the case of parallel reductions
     ): NimNode =
  # Package a parallel for loop into a proc, it requires:
  # - a proc ident that can be used to call the proc package
  # - a wrapper template, to handle runtime metadata
  # - the loop index and loop body
  # - The captured variables and their types
  # - The flowvar wrapped return value of the for loop for reductions
  #   or an EmptyNode
  let pragmas = nnkPragma.newTree(
                  ident"nimcall",
                  ident"gcsafe",
                  ident"inline")

  var params: seq[NimNode]
  if resultFvTy.isNil:
    params.add newEmptyNode()
  else: # Unwrap the flowvar
    params.add nnkDotExpr.newTree(resultFvTy, ident"T")

  var procBody = newStmtList()

  if capturedVars.len > 0:
    params.add newIdentDefs(
      env, nnkPtrTy.newTree(capturedTypes)
    )

    let derefEnv = nnkBracketExpr.newTree(env)
    if capturedVars.len > 1:
      # Unpack the variables captured from the environment
      # let (a, b, c) = env[]
      var unpacker = nnkVarTuple.newTree()
      capturedVars.copyChildrenTo(unpacker)
      unpacker.add newEmptyNode()
      unpacker.add derefEnv

      procBody.add nnkLetSection.newTree(unpacker)
    else:
      procBody.add newLetStmt(capturedVars[0], derefEnv)


  procBody.add newCall(
    wrapperTemplate,
    idx,
    prologue, loopBody, epilogue,
    remoteAccum, resultFvTy, returnStmt
  )

  result = newProc(
    name = procIdent,
    params = params,
    body = procBody,
    pragmas = pragmas
  )

proc addLoopTask(
      statement,
      workerContext, schedule,
      parLoopFn,
      start, stop, stride,
      capturedVars, CapturedTySym,
      futureIdent, resultFutureType: NimNode) =
  ## Add a loop task
  ## futureIdent is the final reduction accumulator

  statement.expectKind nnkStmtList
  parLoopFn.expectKind nnkIdent

  var withArgs = false
  if not capturedVars.isNil:
    withArgs = true
    capturedVars.expectKind nnkPar
    CapturedTySym.expectKind nnkIdent
    assert capturedVars.len > 0

  # TODO: awaitable for loop

  # Dependencies
  # ---------------------------------------------------
  var scheduleBlock: NimNode
  let task = ident"tpLoopTask"
  # TODO: Dataflow parallelism / precise task dependencies
  scheduleBlock = newCall(schedule, workerContext, task)

  # ---------------------------------------------------
  statement.add quote do:
    if likely(`stop`-`start` != 0):
      block enq_deq_task:
        when bool(`withArgs`):
          let `task` = Task.newLoop(
            parent = `workerContext`.currentTask,
            `start`, `stop`, `stride`,
            isFirstIter = true,
            fn = `parLoopFn`,
            params = `capturedVars`)
        else:
          let `task` = Task.newLoop(
            parent = `workerContext`.currentTask,
            `start`, `stop`, `stride`,
            isFirstIter = true,
            fn = `parLoopFn`)
        `scheduleBlock`

proc parallelForImpl*(tp: NimNode{nkSym}, workerContext, schedule, wrapper, loopParams, stride, body: NimNode): NimNode =
  ## Parallel for loop
  ## Syntax:
  ##
  ## parallelFor i in 0 ..< 10:
  ##   echo(i)
  ##
  ## Variables from the external scope needs to be explicitly captured
  ##
  ##  var a = 100
  ##  var b = 10
  ##  parallelFor i in 0 ..< 10:
  ##    captures: {a, b}
  ##    echo a + b + i

  result = newStmtList()

  # Loop parameters
  # --------------------------------------------------------
  let (idx, start, stop) = extractLP(loopParams)

  # Extract resulting flowvar and captured variables
  # --------------------------------------------------------
  let (future, captured, capturedTy) = body.extractFutureAndCaptures()
  let withArgs = capturedTy.len > 0

  let CapturedTy = ident"CapturedTy"
  if withArgs:
    result.add quote do:
      type `CapturedTy` = `capturedTy`

  # Package the body in a proc
  # --------------------------------------------------------
  let parForName = ident"tpParForSection"
  let env = ident("tpParForEnv_") # typed pointer to data
  result.add packageParallelFor(
                parForName, wrapper,
                # prologue, loopBody, epilogue,
                nil, body, nil,
                # remoteAccum, return statement
                nil, nil,
                idx, env,
                captured, capturedTy,
                resultFvTy = nil)

  # Create the async function (that calls the proc that packages the loop body)
  # --------------------------------------------------------
  let parForTask = ident("tpParForTask_")
  var fnCall = newCall(parForName)
  if withArgs:
    fnCall.add(env)

  var futTy: NimNode

  result.add quote do:
    proc `parForTask`(params: pointer) {.nimcall, gcsafe.} =
      when bool(`withArgs`):
        let `env` = cast[ptr `CapturedTy`](params)
      `fnCall`

  # Create the task
  # --------------------------------------------------------
  result.addLoopTask(
    workerContext, schedule,
    parForTask, start, stop, stride, captured, CapturedTy,
    futureIdent = future, resultFutureType = futTy)

  # echo result.toStrLit