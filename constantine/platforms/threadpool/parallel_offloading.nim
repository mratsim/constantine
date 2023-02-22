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
  let tpSpawn_fn = ident("ctt_tpSpawnVoidFn_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("ctt_tpSpawnVoidTaskEnv_")   # typed pointer to env

  # Schedule
  let task = ident"ctt_tpSpawnVoidTask_"
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
    proc `tpSpawn_fn`(env: pointer) {.nimcall, gcsafe, raises: [].} =
      when bool(`withArgs`):
        let `env` = cast[ptr `argsTy`](env)
      `fnCall`

  # Create the task
  result.add quote do:
    block enq_deq_task:
      when bool(`withArgs`):
        let `task` = Task.newSpawn(
          parent = `workerContext`.currentTask,
          fn = `tpSpawn_fn`,
          params = `args`)
      else:
        let `task` = Task.newSpawn(
          parent = `workerContext`.currentTask,
          fn = `tpSpawn_fn`)
      `scheduleBlock`

proc spawnRet(funcCall: NimNode, retTy, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  # Create the async function
  result = newStmtList()

  let fn = funcCall[0]
  let fnName = $fn
  let tpSpawn_fn = ident("ctt_tpSpawnRetFn_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("ctt_tpSpawnRetEnv_")   # typed pointer to env

  # tasks have no return value.
  # 1. The start of the task `env` buffer will store the return value for the flowvar and awaiter/sync
  # 2. We create a wrapper tpSpawn_fn without return value that send the return value in the channel
  # 3. We package that wrapper function in a task

  # We store the following in task.env:
  #
  # | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  let fut = ident"ctt_tpSpawnRetFut_"
  let taskSelfReference = ident"ctt_taskSelfReference"
  let retVal = ident"ctt_retVal"

  var envParams = nnkPar.newTree
  var envParamsTy = nnkPar.newTree
  envParams.add taskSelfReference
  envParamsTy.add nnkPtrTy.newTree(bindSym"Task")
  envParams.add retVal
  envParamsTy.add retTy

  for i in 1 ..< funcCall.len:
    envParamsTy.add getTypeInst(funcCall[i])
    envParams.add funcCall[i]

  # env stores | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  # so arguments starts at env[2] in the wrapping funcCall functions
  for i in 1 ..< funcCall.len:
    fnCall.add nnkBracketExpr.newTree(env, newLit i+1)

  result.add quote do:
    proc `tpSpawn_fn`(env: pointer) {.nimcall, gcsafe, raises: [].} =
      let `env` = cast[ptr `envParamsTy`](env)
      let res = `fnCall`
      readyWith(`env`[0], res)

  # Regenerate fresh ident, retTy has been tagged as a function call param
  let retTy = ident($retTy)
  let task = ident"ctt_tpSpawnRetTask_"
  let scheduleBlock = newCall(schedule, workerContext, task)

  # Create the task
  result.add quote do:
    block enq_deq_task:
      let `taskSelfReference` = cast[ptr Task](0xDEADBEEF)
      let `retVal` = default(`retTy`)

      let `task` = Task.newSpawn(
        parent = `workerContext`.currentTask,
        fn = `tpSpawn_fn`,
        params = `envParams`)
      let `fut` = newFlowVar(`retTy`, `task`)
      `scheduleBlock`
      # Return the future
      `fut`

proc spawnImpl*(tp: NimNode{nkSym}, funcCall: NimNode, workerContext, schedule: NimNode): NimNode =
  funcCall.expectKind(nnkCall)

  # Get the return type if any
  let retTy = funcCall[0].getImpl[3][0]
  let needFuture = retTy.kind != nnkEmpty

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
    result = spawnRet(funcCall, retTy, args, argsTy, workerContext, schedule)

  # Wrap in a block for namespacing
  result = nnkBlockStmt.newTree(newEmptyNode(), result)

# ############################################################
#                                                            #
#                   Data parallelism                         #
#                                                            #
# ############################################################

proc rebuildUntypedLoopParams(loopParams: NimNode): NimNode =
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
  let loopParams = rebuildUntypedLoopParams(loopParams)
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
        retTy: NimNode # For-loops can return a result in the case of parallel reductions
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
                  ident"inline",
                  nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree())) # raises: []

  var params: seq[NimNode]
  if retTy.isNil:
    params.add newEmptyNode()
  else:
    params.add retTy

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
    remoteAccum, retTy, returnStmt)

  result = newProc(
    name = procIdent,
    params = params,
    body = procBody,
    pragmas = pragmas)

proc addLoopTask(
      statement,
      workerContext, schedule,
      parLoopFn,
      start, stop, stride,
      capturedVars,
      futureIdent, resultType: NimNode) =
  ## Add a loop task
  ## futureIdent is the final reduction accumulator

  statement.expectKind nnkStmtList
  parLoopFn.expectKind nnkIdent

  var withCaptures = false
  if not capturedVars.isNil:
    withCaptures = true
    capturedVars.expectKind nnkPar
    assert capturedVars.len > 0

  # TODO: awaitable for loop

  # Dependencies
  # ---------------------------------------------------
  var scheduleBlock: NimNode
  let task = ident"ctt_tpLoopTask"
  # TODO: Dataflow parallelism / precise task dependencies
  scheduleBlock = newCall(schedule, workerContext, task)

  # ---------------------------------------------------
  if resultType.isNil():
    statement.add quote do:
      block enq_deq_task: # block for namespacing
        if likely(`stop`-`start` != 0):
            when bool(`withCaptures`):
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
  else:
    statement.add quote do:
      var `futureIdent`: FlowVar[`resultType`]
      block enq_deq_task: # Block for name spacing
        var `task`: ptr Task
        if likely(`stop`-`start` != 0):
          let taskSelfReference = cast[ptr Task](0xDEADBEEF)
          let retVal = default(`resultType`)

          when bool(`withCaptures`):
            `task` = Task.newLoop(
              parent = `workerContext`.currentTask,
              `start`, `stop`, `stride`,
              isFirstIter = true,
              fn = `parLoopFn`,
              params = (taskSelfReference, retVal, `capturedVars`))
          else:
            `task` = Task.newLoop(
              parent = `workerContext`.currentTask,
              `start`, `stop`, `stride`,
              isFirstIter = true,
              fn = `parLoopFn`,
              params = (taskSelfReference, retVal))
          `futureIdent` = newFlowVar(`resultType`, `task`)
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
  let withCaptures = capturedTy.len > 0

  # Package the body in a proc
  # --------------------------------------------------------
  let parForName = ident"ctt_tpParForSection"
  let env = ident("ctt_tpParForEnv_") # typed pointer to env
  result.add packageParallelFor(
                parForName, wrapper,
                # prologue, loopBody, epilogue,
                nil, body, nil,
                # remoteAccum, return statement
                nil, nil,
                idx, env,
                captured, capturedTy,
                retTy = nil)

  # Create the task function (that calls the proc that packages the loop body)
  # --------------------------------------------------------
  let tpParFor_fn = ident("ctt_tpParForFn_")
  var fnCall = newCall(parForName)
  if withCaptures:
    fnCall.add(env)

  result.add quote do:
    proc `tpParFor_fn`(env: pointer) {.nimcall, gcsafe.} =
      when bool(`withCaptures`):
        let `env` = cast[ptr `capturedTy`](env)
      `fnCall`

  # Create the task
  # --------------------------------------------------------
  result.addLoopTask(
    workerContext, schedule,
    tpParFor_fn, start, stop, stride, captured,
    futureIdent = future, resultType = nil)

# ############################################################
#                                                            #
#        Staged Parallel loops error messages                #
#                                                            #
# ############################################################
#
# This outputs nice syntax examples for the parallel reduction
# and parallel staged domain specific languages.

type Example = enum
  Reduce
  Staged

template parReduceExample() {.dirty.}=
  # Used for a nice error message

  proc parallelReduceExample(n: int): int =
    tp.parallelFor i in 0 ..< n:
      ## Declare a parallelFor or parallelForStrided loop as usual
      reduceInto(globalSum: int64):
        ## Indicate that the loop is a reduction and declare the global reduction variable to sync with
        prologue:
          ## Declare your local reduction variable(s) here
          ## It should be initialized with the neutral element
          ## corresponding to your fold operation.
          ## (0 for addition, 1 for multiplication, -Inf for max, +Inf for min, ...)
          ##
          ## This is task-local (and thread-local), each tasks set this section independently.
          ## Splitting in multiple tasks is done dynamically at the runtime discretion
          ## depending on available parallelism and load.
          var localSum = 0
        forLoop:
          ## This is the reduction loop
          localSum += i
        merge(remoteSum: FlowVar[int64]):
          ## Define how to merge with partial reductions from remote threads
          ## Remote threads result come as Flowvar that needs to be synced.
          ## Latency-hiding techniques can be use to overlap epilogue computations
          ## with other threads sync.
          localSum += sync(remoteSum)
        ## Return your local partial reduction
        return localSum

    ## Await the parallel reduction
    return sync(globalSum)

template parStagedExample() {.dirty.} =
  # Used for a nice error message

  proc parallelStagedSumExample(n: int): int =
    ## We will do a sum reduction to illustrate
    ## staged parallel for

    ## First take the address of the result
    let res = result.addr

    ## Declare a parallelForStaged loop
    tp.parallelForStaged i in 0 ..< n:
      captures: {res}
      prologue:
        ## Declare anything needed before the for-loop
        ## This will be thread-local, so each thread will run this section independently.
        ## The loop increment is not available here
        var localSum = 0
      forLoop:
        ## This is within the parallel loop
        localSum += i
      epilogue:
        ## Once the loop is finished, you have a final opportunity for processing.
        ## Thread-local cleanup should happen here as well
        ## Here we print the localSum and atomically increment the global sum
        ## before ending the task.
        echo "localsum = ", localSum
        res[].atomicInc(localSum)

    ## Await all tasks
    tp.syncAll()

proc printReduceExample() =
  let example = getAst(parReduceExample())
  echo example.toStrLit()
proc printStagedExample() =
  let example = getAst(parStagedExample())
  echo example.toStrLit()

proc testKind(nn: NimNode, nnk: NimNodeKind, kind: Example) =
  if nn.kind != nnk:
    case kind
    of Reduce: printReduceExample()
    of Staged: printStagedExample()
    nn.expectKind(nnk) # Gives nice line numbers

# ############################################################
#                                                            #
#                   Parallel Reductions                      #
#                                                            #
# ############################################################

proc extractReductionConfig(body: NimNode, withCaptures: bool): tuple[
    prologue, forLoop, merge,
    remoteAccum, retTy,
    returnStmt, finalAccum: NimNode
  ] =
  # For input
  #   parallelFor i in 0 .. n:
  #     reduceInto(globalSum: int64):
  #       prologue:
  #         var localSum = 0'i64
  #       forLoop:
  #         localSum += int64(i)
  #       merge(remoteSum: Flowvar[int64]):
  #         localSum += sync(remoteSum)
  #       return localSum
  #
  # The body tree representation is
  #
  # StmtList
  #   Call
  #     ObjConstr
  #       Ident "reduceInto"
  #       ExprColonExpr
  #         Ident "globalSum"
  #         Ident "int64"
  #     StmtList
  #       Call
  #         Ident "prologue"
  #         StmtList
  #           VarSection
  #             IdentDefs
  #               Ident "localSum"
  #               Empty
  #               Int64Lit 0
  #       Call
  #         Ident "forLoop"
  #         StmtList
  #           Infix
  #             Ident "+="
  #             Ident "localSum"
  #             Call
  #               Ident "int64"
  #               Ident "i"
  #       Call
  #         ObjConstr
  #           Ident "merge"
  #           ExprColonExpr
  #             Ident "remoteSum"
  #             BracketExpr
  #               Ident "Flowvar"
  #               Ident "int64"
  #         StmtList
  #           Infix
  #             Ident "+="
  #             Ident "localSum"
  #             Call
  #               Ident "sync"
  #               Ident "remoteSum"
  #       ReturnStmt
  #         Ident "localSum"
  let config = if withCaptures: body[1] else: body[0]
  config.testKind(nnkCall, Reduce)
  config[0].testKind(nnkObjConstr, Reduce)
  doAssert config[0][0].eqIdent"reduceInto"
  config[0][1].testKind(nnkExprColonExpr, Reduce)
  config[1].testKind(nnkStmtList, Reduce)

  if config[1].len != 4:
    printReduceExample()
    error "A reduction should have 4 sections named: prologue, forLoop, merge and a return statement"

  let
    finalAccum = config[0][1][0]
    retTy = config[0][1][1]
    prologue = config[1][0]
    forLoop = config[1][1]
    merge = config[1][2]
    remoteAccum = merge[0][1]
    returnStmt = config[1][3]

  # Sanity checks
  prologue.testKind(nnkCall, Reduce)
  forLoop.testKind(nnkCall, Reduce)
  merge.testKind(nnkCall, Reduce)
  remoteAccum.testKind(nnkExprColonExpr, Reduce)
  # remoteAccum[1].testKind(nnkBracketExpr, Reduce) // Can also be Call -> openSymChoice "[]" in generic procs
  returnStmt.testKind(nnkReturnStmt, Reduce)
  if not (prologue[0].eqIdent"prologue" and forLoop[0].eqIdent"forLoop" and merge[0][0].eqIdent"merge"):
    printReduceExample()
    error "A reduction should have 4 sections named: prologue, forLoop, merge and a return statement"
  prologue[1].testKind(nnkStmtList, Reduce)
  forLoop[1].testKind(nnkStmtList, Reduce)
  merge[1].testKind(nnkStmtList, Reduce)


  # // Can also be Call -> openSymChoice "[]" in generic procs
  # doAssert remoteAccum[1][0].eqIdent"Flowvar" and remoteAccum[1][1].repr == retTy.repr

  result = (prologue[1], forLoop[1], merge[1],
            remoteAccum[0], retTy,
            returnStmt, finalAccum)

proc parallelReduceImpl*(tp: NimNode{nkSym}, workerContext, schedule, wrapper, loopParams, stride, body: NimNode): NimNode =
  ## Parallel reduce loop
  ## Syntax:
  ##
  ##   parallelFor i in 0 ..< 100:
  ##     reduceInto(globalSum: int64):
  ##       prologue:
  ##         ## Initialize before the loop
  ##         var localSum = 0
  ##       forLoop:
  ##         ## Compute the partial reductions
  ##         localSum += i
  ##       merge(remoteSum: Flowvar[int64]):
  ##         ## Merge our local reduction with reduction from remote threads
  ##         localSum += sync(remoteSum)
  ##       return localSum
  ##
  ##   # Await our result
  ##   let sum = sync(globalSum)
  ##
  ## The first element from the iterator (i) in the example is not available in the prologue.
  ## Depending on multithreaded scheduling it may start at 0 or halfway or close to completion.
  ## The accumulator set in the prologue should be set at the neutral element for your fold operation:
  ## - 0 for addition, 1 for multiplication, +Inf for min, -Inf for max, ...
  ##
  ## In the forLoop section the iterator i is available, the number of iterations is undefined.
  ## The runtime chooses dynamically how many iterations are done to maximize throughput.
  ## - This requires your operation to be associative, i.e. (a+b)+c = a+(b+c).
  ## - It does not require your operation to be commutative (a+b = b+a is not needed).
  ## - In particular floating-point addition is NOT associative due to rounding errors.
  ##   and result may differ between runs.
  ##   For inputs usually in [-1,1]
  ##   the floating point addition error is within 1e-8 (float32) or 1e-15 (float64).
  ##   For inputs beyond 1e^9 please evaluate the acceptable precision.
  ##   Note: that the main benefits of "-ffast-math" is considering floating-point addition
  ##         associative
  ##
  ## In the merge section, a tuple (identifier: Flowvar[MyType]) for a partial reduction from a remote core must be passed.
  ## The merge section may be executed multiple times if a loop was split between many threads.
  ## The local partial reduction must be returned.
  ##
  ## Variables from the external scope needs to be explicitly captured.
  ## For example, to compute the variance of a seq in parallel
  ##
  ##    var s = newSeqWith(1000, rand(100.0))
  ##    let mean = mean(s)
  ##
  ##    let ps = cast[ptr UncheckedArray[float64]](s)
  ##
  ##    parallelFor i in 0 ..< s.len:
  ##      captures: {ps, mean}
  ##      reduceInto(globalVariance: float64):
  ##        prologue:
  ##          var localVariance = 0.0
  ##        fold:
  ##          localVariance += (ps[i] - mean)^2
  ##        merge(remoteVariance: Flowvar[float64]):
  ##          localVariance += sync(remoteVariance)
  ##        return localVariance
  ##
  ##    # Await our result
  ##    let variance = sync(globalVariance)
  ##
  ## Performance note:
  ##   For trivial floating points operations like addition/sum reduction:
  ##   before parallelizing reductions on multiple cores
  ##   you might try to parallelize it on a single core by
  ##   creating multiple accumulators (between 2 and 4)
  ##   and unrolling the accumulation loop by that amount.
  ##
  ##   The compiler is unable to do that (without -ffast-math)
  ##   as floating point addition is NOT associative and changing
  ##   order will change the result due to floating point rounding errors.
  ##
  ##   The performance improvement is dramatic (2x-3x) as at a low-level
  ##   there is no data dependency between each accumulators and
  ##   the CPU can now use instruction-level parallelism instead
  ##   of suffer from data dependency latency (3 or 4 cycles)
  ##   https://software.intel.com/sites/landingpage/IntrinsicsGuide/#techs=SSE&expand=158
  ##   The reduction becomes memory-bound instead of CPU-latency-bound.

  result = newStmtList()

  # Loop parameters
  # --------------------------------------------------------
  let (idx, start, stop) = extractLP(loopParams)

  # Extract captured variables
  # --------------------------------------------------------
  var captured, capturedTy: NimNode
  if body[0].kind == nnkCall and body[0][0].eqIdent"captures":
    (captured, capturedTy) = extractCaptures(body, 0)

  let withCaptures = capturedTy.len > 0

  let CapturedTy = ident"CapturedTy" # workaround for GC-safe check
  if withCaptures:
    result.add quote do:
      type `CapturedTy` = `capturedTy`

  # Extract the reduction configuration
  # --------------------------------------------------------
  let (prologue, forLoop, merge,
      remoteAccum, retTy,
      returnStmt, finalAccum) = extractReductionConfig(body, withCaptures)

  # Package the body in a proc
  # --------------------------------------------------------
  let parReduceName = ident"ctt_tpParReduceSection"
  let env = ident("ctt_tpParReduceEnv_") # typed pointer to env
  result.add packageParallelFor(
                parReduceName, wrapper,
                # prologue, loopBody, epilogue,
                prologue, forLoop, merge,
                # remoteAccum, return statement
                remoteAccum, returnStmt,
                idx, env,
                captured, capturedTy,
                retTy)

  # Create the task function (that calls the proc that packages the loop body)
  # --------------------------------------------------------
  let tpParReduce_fn = ident("ctt_tpParReduceFn_")
  var fnCall = newCall(parReduceName)
  if withCaptures:
    fnCall.add(env)

  # We store the following in task.env:
  #
  # | ptr Task | result | arg₀ | arg₁ | ... | argₙ

  result.add quote do:
    proc `tpParReduce_fn`(env: pointer) {.nimcall, gcsafe.} =
      let taskSelfReference = cast[ptr ptr Task](env)
      when bool(`withCaptures`):
        let offset = cast[ByteAddress](env) +% sizeof((ptr Task, `retTy`))
        let `env` = cast[ptr `capturedTy`](offset)
      let res = `fnCall`
      readyWith(taskSelfReference[], res)

  # Create the task
  # --------------------------------------------------------
  result.addLoopTask(
    workerContext, schedule,
    tpParReduce_fn, start, stop, stride, captured,
    finalAccum, retTy)