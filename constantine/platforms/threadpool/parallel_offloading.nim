# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ./crossthread/tasks_flowvars,
  ../ast_rebuilder

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

proc needTempStorage(argTy: NimNode): bool =
  case argTy.kind
  of nnkVarTy:
    error("It is unsafe to capture a `var` parameter and pass it to another thread. Its memory location could be invalidated if the spawning proc returns before the worker thread finishes.")
  of nnkStaticTy:
    return false
  of nnkBracketExpr:
    if argTy[0].typeKind == ntyTypeDesc:
      return false
    else:
      return true
  of nnkCharLit..nnkNilLit:
    return false
  else:
    return true

proc spawnVoid(funcCall: NimNode, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  ## Spawn a function that can be scheduled on another thread
  ## without return value.
  result = newStmtList()

  let fn = funcCall[0]
  let fnName = $fn
  let withArgs = args.len > 0
  let tpSpawn_closure = ident("ctt_tpSpawnVoidClosure_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("ctt_tpSpawnVoidEnv_")   # typed pointer to env

  # Closure unpacker
  var envParams = nnkTupleConstr.newTree()
  var envParamsTy = nnkTupleConstr.newTree()
  var envOffset = 0

  for i in 0 ..< args.len:
    if argsTy[i].needTempStorage():
      envParamsTy.add argsTy[i]
      envParams.add args[i]
      fnCall.add nnkBracketExpr.newTree(env, newLit envOffset)
      envOffset += 1
    else:
      fnCall.add args[i]

  # Create the async call
  result.add quote do:
    proc `tpSpawn_closure`(env: pointer) {.nimcall, gcsafe, raises: [].} =
      when bool(`withArgs`):
        let `env` = cast[ptr `envParamsTy`](env)
      `fnCall`

  # Schedule
  let task = ident"ctt_tpSpawnVoidTask_"
  let scheduleBlock = newCall(schedule, workerContext, task)

  # Create the task
  result.add quote do:
    block enq_deq_task:
      when bool(`withArgs`):
        let `task` = Task.newSpawn(
          parent = `workerContext`.currentTask,
          scopedBarrier = `workerContext`.currentScope,
          fn = `tpSpawn_closure`,
          env = `envParams`)
      else:
        let `task` = Task.newSpawn(
          parent = `workerContext`.currentTask,
          scopedBarrier = `workerContext`.currentScope,
          fn = `tpSpawn_closure`)
      `scheduleBlock`

proc spawnVoidAwaitable(funcCall: NimNode, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  ## Spawn a function that can be scheduled on another thread
  ## with a dummy awaitable return value
  result = newStmtList()

  let fn = funcCall[0]
  let fnName = $fn
  let tpSpawn_closure = ident("ctt_tpSpawnVoidAwaitableClosure_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("ctt_tpSpawnVoidAwaitableEnv_")   # typed pointer to env

  # tasks have no return value.
  # 1. The start of the task `env` buffer will store the return value for the flowvar and awaiter/sync
  # 2. We create a wrapper tpSpawn_closure without return value that send the return value in the channel
  # 3. We package that wrapper function in a task

  # We store the following in task.env:
  #
  # | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  let fut = ident"ctt_tpSpawnVoidAwaitableFut_"
  let taskSelfReference = ident"ctt_taskSelfReference"

  # Closure unpacker
  # env stores | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  # so arguments starts at env[2] in the wrapping funcCall functions
  var envParams = nnkTupleConstr.newTree()
  var envParamsTy = nnkTupleConstr.newTree()
  envParams.add taskSelfReference
  envParamsTy.add nnkPtrTy.newTree(bindSym"Task")
  envParams.add newLit(false)
  envParamsTy.add getType(bool)
  var envOffset = 2

  for i in 0 ..< args.len:
    if argsTy[i].needTempStorage():
      envParamsTy.add argsTy[i]
      envParams.add args[i]
      fnCall.add nnkBracketExpr.newTree(env, newLit envOffset)
      envOffset += 1
    else:
      fnCall.add args[i]

  result.add quote do:
    proc `tpSpawn_closure`(env: pointer) {.nimcall, gcsafe, raises: [].} =
      let `env` = cast[ptr `envParamsTy`](env)
      `fnCall`
      readyWith(`env`[0], true)

  # Schedule
  let task = ident"ctt_tpSpawnVoidAwaitableTask_"
  let scheduleBlock = newCall(schedule, workerContext, task)

  # Create the task
  result.add quote do:
    block enq_deq_task:
      let `taskSelfReference` = cast[ptr Task](0xDEADBEEF)

      let `task` = Task.newSpawn(
        parent = `workerContext`.currentTask,
        scopedBarrier = `workerContext`.currentScope,
        fn = `tpSpawn_closure`,
        env = `envParams`)
      let `fut` = newFlowVar(bool, `task`)
      `scheduleBlock`
      # Return the future
      `fut`

proc spawnRet(funcCall: NimNode, retTy, args, argsTy: NimNode, workerContext, schedule: NimNode): NimNode =
  ## Spawn a function that can be scheduled on another thread
  ## with an awaitable future return value.
  result = newStmtList()

  let fn = funcCall[0]
  let fnName = $fn
  let tpSpawn_closure = ident("ctt_tpSpawnRetClosure_" & fnName)
  var fnCall = newCall(fn)
  let env = ident("ctt_tpSpawnRetEnv_")   # typed pointer to env

  # tasks have no return value.
  # 1. The start of the task `env` buffer will store the return value for the flowvar and awaiter/sync
  # 2. We create a wrapper tpSpawn_closure without return value that send the return value in the channel
  # 3. We package that wrapper function in a task

  # We store the following in task.env:
  #
  # | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  let fut = ident"ctt_tpSpawnRetFut_"
  let taskSelfReference = ident"ctt_taskSelfReference"
  let retVal = ident"ctt_retVal"

  # Closure unpacker
  # env stores | ptr Task | result | arg₀ | arg₁ | ... | argₙ
  # so arguments starts at env[2] in the wrapping funcCall functions
  var envParams = nnkTupleConstr.newTree()
  var envParamsTy = nnkTupleConstr.newTree()
  envParams.add taskSelfReference
  envParamsTy.add nnkPtrTy.newTree(bindSym"Task")
  envParams.add retVal
  envParamsTy.add retTy
  var envOffset = 2

  for i in 0 ..< args.len:
    if argsTy[i].needTempStorage():
      envParamsTy.add argsTy[i]
      envParams.add args[i]
      fnCall.add nnkBracketExpr.newTree(env, newLit envOffset)
      envOffset += 1
    else:
      fnCall.add args[i]

  result.add quote do:
    proc `tpSpawn_closure`(env: pointer) {.nimcall, gcsafe, raises: [].} =
      let `env` = cast[ptr `envParamsTy`](env)
      let res = `fnCall`
      readyWith(`env`[0], res)

  # Schedule
  let retTy = ident($retTy) # Regenerate fresh ident, retTy has been tagged as a function call param
  let task = ident"ctt_tpSpawnRetTask_"
  let scheduleBlock = newCall(schedule, workerContext, task)

  # Create the task
  result.add quote do:
    block enq_deq_task:
      let `taskSelfReference` = cast[ptr Task](0xDEADBEEF)
      let `retVal` = default(`retTy`)

      let `task` = Task.newSpawn(
        parent = `workerContext`.currentTask,
        scopedBarrier = `workerContext`.currentScope,
        fn = `tpSpawn_closure`,
        env = `envParams`)
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
  var argsTy = nnkTupleConstr.newTree()
  var args = nnkTupleConstr.newTree()
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

proc spawnAwaitableImpl*(tp: NimNode{nkSym}, funcCall: NimNode, workerContext, schedule: NimNode): NimNode =
  funcCall.expectKind(nnkCall)

  # Get the return type if any
  let retTy = funcCall[0].getImpl[3][0]
  let needFuture = retTy.kind != nnkEmpty
  if needFuture:
    error "spawnAwaitable can only be used with procedures without returned values"

  # Get a serialized type and data for all function arguments
  # We use adhoc tuple
  var argsTy = nnkTupleConstr.newTree()
  var args = nnkTupleConstr.newTree()
  for i in 1 ..< funcCall.len:
    argsTy.add getTypeInst(funcCall[i])
    args.add funcCall[i]

  # Package in a task
  result = spawnVoidAwaitable(funcCall, args, argsTy, workerContext, schedule)

  # Wrap in a block for namespacing
  result = nnkBlockStmt.newTree(newEmptyNode(), result)

# ############################################################
#                                                            #
#                   Data parallelism                         #
#                                                            #
# ############################################################

# Error messages generation
# --------------------------------------------------------------------------------------------------
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
        epilogue:
          ## Local task cleanup like memory allocated in prologue
          ## and returning the local accumulator
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

# Parallel Loop Domain Specific Language Descriptor
# --------------------------------------------------------------------------------------------------

type
  LoopKind = enum
    kForLoop
    kReduction
    kStaged

  LoopDescriptor = object
    ## A loop descriptor fully described a parallel loop
    ## before final code generation
    ##
    ## Fields are ordered by depth of the call stack:
    ## - Users defines the loop boundaries and captures
    ## - a closure with signature `proc MyFunctionName(env: pointer)`
    ##   is generated
    ## - it gets packaged in a task
    ## - on task execution, the inner proc is reconstructed
    ## - That inner proc may have various sections depending on the loop kind

    kind: LoopKind

    # Loop bounds
    # -----------
    indexVariable: NimNode
    start: NimNode
    stopEx: NimNode
    stride: NimNode

    # Closure generation
    # ------------------
    envName: NimNode
    closureName: NimNode
    closureDef: NimNode
    capturedVars: NimNode
    capturedTypes: NimNode

    # Task packaging and scheduling
    # -----------------------------
    taskName: NimNode
    taskCreation: NimNode
    workerContext: NimNode
    scheduleFn: NimNode

    # Parallel loop stages
    # --------------------
    # There are 3 calls level for loops:
    # - closure(env: pointer) {.nimcall, gcsafe, raises: [].}
    # - loopFn(args: ptr (argsTy₀, argsTy₁, ..., argsTyₙ)): returnType {.inline, nimcall, gcsafe, raises: [].}
    #     let (args₀, args₁, ..., argsₙ) = args[]
    #     loopTemplate(indexVar, prologue, loopBody, ...)
    # - loopTemplate(indexVar, prologue, loopBody, ...: untyped)
    #
    # The last 2 levels are inline in the closure.
    # - The closure deals with removing type erasure from an untyped environment and updating the future once the task is finished
    # - The loopFn reinstalls the captured values
    # - The loopTemplate reimplements the sections as well as runtime interaction
    #   for loop splitting checks and merging reduction accumulators with splitted tasks.
    #
    # A side-benefit of the loopFn is that it allows borrow-checking:
    # - error if we capture a `var parameter`
    # - error if we forget to capture a runtime variable (compile-time constants do not have to be captured)
    loopFnName: NimNode   # inner function called by the closure once environment is retyped
    loopTemplate: NimNode # inner function implementation, defined in threadpool.nim
    prologue: NimNode
    forLoop: NimNode
    epilogue: NimNode

    # Futures - awaitable loops and reductions
    # ----------------------------------------
    globalAwaitable: NimNode
    remoteTaskAwaitable: NimNode
    awaitableType: NimNode
    mergeLocalWithRemote: NimNode

# Parsing parallel loop DSL
# --------------------------------------------------------------------------------------------------

proc checkLoopBounds(loopBounds: NimNode) =
  ## Checks loop parameters
  ## --------------------------------------------------------
  ## loopBounds should have the form "i in 0..<10"
  loopBounds.expectKind(nnkInfix)
  assert loopBounds[0].eqIdent"in"
  loopBounds[1].expectKind(nnkIdent)
  loopBounds[2].expectKind(nnkInfix) # 0 ..< 10 / 0 .. 10, for now we don't support slice objects
  assert loopBounds[2][0].eqIdent".." or loopBounds[2][0].eqIdent"..<"

proc parseLoopBounds(ld: var LoopDescriptor, loopBounds: NimNode) =
  ## Extract the index, start and stop of the loop
  ## Strides must be dealt with separately
  let loopBounds = rebuildUntypedAst(loopBounds, dropRootStmtList = true)
  checkLoopBounds(loopBounds)
  ld.indexVariable = loopBounds[1]
  ld.start = loopBounds[2][1]
  ld.stopEx = loopBounds[2][2]
  # We use exclusive bounds
  if loopBounds[2][0].eqIdent"..":
    ld.stopEx = newCall(ident"succ", ld.stopEx)

proc parseCaptures(ld: var LoopDescriptor, body: NimNode) =
  ## Extract captured variables from the for-loop body.
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
  for i in 0 ..< body.len:
    if body[i].kind == nnkCall and body[i][0].eqIdent"captures":
      ld.capturedVars = nnkPar.newTree()
      ld.capturedTypes = nnkPar.newTree()

      body[i][1].expectKind(nnkStmtList)
      body[i][1][0].expectKind(nnkCurly)
      for j in 0 ..< body[i][1][0].len:
        ld.capturedVars.add body[i][1][0][j]
        ld.capturedTypes.add newCall(ident"typeof", body[i][1][0][j])

      # Remove the captures section
      body[i] = nnkDiscardStmt.newTree(body[i].toStrLit)
      return

proc extractSection(ldField: var NimNode, body: NimNode, sectionName: string) =
  body.expectKind(nnkStmtList)
  for i in 0 ..< body.len:
    if body[i].kind == nnkCall and body[i][0].eqIdent(sectionName):
      body[i][1].expectKind(nnkStmtList)
      ldField = body[i][1]
      # Remove the section
      body[i] = nnkDiscardStmt.newTree(body[i].toStrLit)
      return

# Code generation
# --------------------------------------------------------------------------------------------------

proc generateClosure(ld: LoopDescriptor): NimNode =

  let env = ld.envName
  let capturedTypes = ld.capturedTypes
  let withCaptures = ld.capturedTypes.len > 0

  let closureName = ld.closureName
  var loopFnCall = newCall(ld.loopFnName)
  if withCaptures:
    loopFnCall.add(env)

  case ld.kind
  of kForLoop:
    result = quote do:
      proc `closureName`(env: pointer) {.nimcall, gcsafe, raises: [].} =
        when bool(`withCaptures`):
          let `env` = cast[ptr `capturedTypes`](env)
        `loopFnCall`
  of kReduction:
    let retTy = ld.awaitableType

    result = quote do:
      proc `closureName`(env: pointer) {.nimcall, gcsafe, raises: [].} =
        let taskSelfReference = cast[ptr ptr Task](env)
        when bool(`withCaptures`):
          let offset = cast[ByteAddress](env) +% sizeof((ptr Task, `retTy`))
          let `env` = cast[ptr `capturedTypes`](offset)
        let res = `loopFnCall`
        readyWith(taskSelfReference[], res)
  else:
    error "Not Implemented"

proc generateAndScheduleLoopTask(ld: LoopDescriptor): NimNode =
  result = newStmtList()

  var withCaptures = false
  if not ld.capturedVars.isNil:
    withCaptures = true

  # TODO: awaitable for loop

  # Dependencies
  # ---------------------------------------------------
  var scheduleBlock: NimNode
  let task = ident"ctt_tpLoopTask_"
  # TODO: Dataflow parallelism / precise task dependencies
  scheduleBlock = newCall(ld.scheduleFn, ld.workerContext, task)

  # ---------------------------------------------------
  let
    (start, stopEx, stride) = (ld.start, ld.stopEx, ld.stride)
    workerContext = ld.workerContext
    (closureName, capturedVars) = (ld.closureName, ld.capturedVars)
    (globalAwaitable, awaitableType) = (ld.globalAwaitable, ld.awaitableType)
  if ld.awaitableType.isNil():
    result = quote do:
      block enq_deq_task: # block for namespacing
        let start  = `start`      # Ensure single evaluation / side-effect
        let stopEx = `stopEx`
        if stopEx-start != 0:
          when bool(`withCaptures`):
            let `task` = Task.newLoop(
              parent = `workerContext`.currentTask,
              scopedBarrier = `workerContext`.currentScope,
              start, stopEx, `stride`,
              isFirstIter = true,
              fn = `closureName`,
              env = `capturedVars`)
          else:
            let `task` = Task.newLoop(
              parent = `workerContext`.currentTask,
              scopedBarrier = `workerContext`.currentScope,
              start, stopEx, `stride`,
              isFirstIter = true,
              fn = `closureName`)
          `scheduleBlock`
  else:
    result = quote do:
      var `globalAwaitable`: FlowVar[`awaitableType`]
      block enq_deq_task: # Block for name spacing
        let start  = `start`      # Ensure single evaluation / side-effect
        let stopEx = `stopEx`
        if stopEx-start != 0:
          let taskSelfReference = cast[ptr Task](0xDEADBEEF)
          var retValBuffer = default(`awaitableType`)

          when bool(`withCaptures`):
            let `task` = Task.newLoop(
              parent = `workerContext`.currentTask,
              scopedBarrier = `workerContext`.currentScope,
              start, stopEx, `stride`,
              isFirstIter = true,
              fn = `closureName`,
              env = (taskSelfReference, retValBuffer, `capturedVars`))
          else:
            let `task` = Task.newLoop(
              parent = `workerContext`.currentTask,
              scopedBarrier = `workerContext`.currentScope,
              start, stopEx, `stride`,
              isFirstIter = true,
              fn = `closureName`,
              env = (taskSelfReference, retValBuffer))
          `globalAwaitable` = newFlowVar(`awaitableType`, `task`)
          `scheduleBlock`

proc generateParallelLoop(ld: LoopDescriptor): NimNode =
  # Package a parallel for loop into a proc
  # Returns the statements that implements it.
  let pragmas = nnkPragma.newTree(
                  ident"nimcall", ident"gcsafe", ident"inline",
                  nnkExprColonExpr.newTree(ident"raises", nnkBracket.newTree())) # raises: []

  var params: seq[NimNode]
  if ld.awaitableType.isNil:
    params.add newEmptyNode()
  else:
    params.add ld.awaitableType

  var procBody = newStmtList()

  if ld.capturedVars.len > 0:
    params.add newIdentDefs(ld.envName, nnkPtrTy.newTree(ld.capturedTypes))

    let derefEnv = nnkBracketExpr.newTree(ld.envName)
    if ld.capturedVars.len > 1:
      # Unpack the variables captured from the environment
      # let (a, b, c) = env[]
      var unpacker = nnkVarTuple.newTree()
      ld.capturedVars.copyChildrenTo(unpacker)
      unpacker.add newEmptyNode()
      unpacker.add derefEnv

      procBody.add nnkLetSection.newTree(unpacker)
    else:
      procBody.add newLetStmt(ld.capturedVars[0], derefEnv)

  case ld.kind
  of kForLoop:
    procBody.add newCall(ld.loopTemplate, ld.indexVariable, ld.forLoop)
  of kReduction:
    procBody.add newCall(
      ld.loopTemplate, ld.indexVariable,
      ld.prologue, ld.forLoop, ld.mergeLocalWithRemote, ld.epilogue,
      ld.remoteTaskAwaitable, ld.awaitableType)
  else:
    error " Unimplemented"

  result = newProc(
    name = ld.loopFnName,
    params = params,
    body = procBody,
    pragmas = pragmas)

# Parallel for
# --------------------------------------------------------------------------------------------------

proc parallelForImpl*(workerContext, scheduleFn, loopTemplate, loopBounds, body: NimNode): NimNode =
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
  var ld = LoopDescriptor(kind: kForLoop, workerContext: workerContext, scheduleFn: scheduleFn)

  # Parse the loop Domain-Specific Language
  # --------------------------------------------------------
  body.expectKind(nnkStmtList)
  ld.parseLoopBounds(loopBounds)
  ld.stride.extractSection(body, "stride")
  if ld.stride.isNil:
    ld.stride = newLit(1)
  ld.parseCaptures(body)
  ld.forLoop = body

  # Code generation
  # --------------------------------------------------------
  ld.loopTemplate = loopTemplate
  ld.loopFnName   = ident("ctt_tpParForImpl_")
  ld.envName      = ident("ctt_tpParForEnv_")
  result.add ld.generateParallelLoop()

  ld.closureName  = ident("ctt_tpParForClosure_")
  result.add ld.generateClosure()

  ld.taskName     = ident("ctt_tpParForTask_")
  result.add ld.generateAndScheduleLoopTask()

# Parallel reductions
# --------------------------------------------------------------------------------------------------

proc parseReductionSection(body: NimNode):
       tuple[globalAwaitable, awaitableType, reductionBody: NimNode] =
  for i in 0 ..< body.len:
    # parallelFor i in 0 .. n:
    #   reduceInto(globalSum: int64):
    #     prologue:
    #       var localSum = 0'i64
    #
    #   StmtList
    #     Call
    #       ObjConstr
    #         Ident "reduceInto"
    #         ExprColonExpr
    #           Ident "globalSum"
    #           Ident "int64"
    #       StmtList
    #         Call
    #           Ident "prologue"
    #           StmtList
    #             VarSection
    #               IdentDefs
    #                 Ident "localSum"
    #                 Empty
    #                 Int64Lit 0
    if body[i].kind == nnkCall and
         body[i][0].kind == nnkObjConstr and
         body[i][0][0].eqident"reduceInto":
      body[i][0][1].testKind(nnkExprColonExpr, Reduce)
      body[i][1].testKind(nnkStmtList, Reduce)

      if body[i][1].len != 4:
        printReduceExample()
        error "A reduction should have 4 sections named:\n" &
              "  prologue, forLoop, merge and epilogue statements\n"
        #      (globalAwaitable, awaitableType, reductionBody)
      return (body[i][0][1][0], body[i][0][1][1], body[i][1])

  printReduceExample()
  error "Missing section \"reduceInto(globalAwaitable: awaitableType):\""

proc extractRemoteTaskMerge(ld: var LoopDescriptor, body: NimNode) =
  for i in 0 ..< body.len:
    if body[i].kind == nnkCall and
         body[i][0].kind == nnkObjConstr and
         body[i][0][0].eqident"merge":
      body[i][0][1].testKind(nnkExprColonExpr, Reduce)
      body[i][1].testKind(nnkStmtList, Reduce)

      ld.remoteTaskAwaitable = body[i][0][1][0]
      ld.mergeLocalWithRemote = body[i][1]
      return

  printReduceExample()
  error "Missing section \"merge(remoteThreadAccumulator: Flowvar[accumulatorType]):\""

proc parallelReduceImpl*(workerContext, scheduleFn, loopTemplate, loopBounds, body: NimNode): NimNode =
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
  var ld = LoopDescriptor(kind: kReduction, workerContext: workerContext, scheduleFn: scheduleFn)

  # Parse the loop Domain-Specific Language
  # --------------------------------------------------------
  body.testKind(nnkStmtList, Reduce)
  ld.parseLoopBounds(loopBounds)
  ld.stride.extractSection(body, "stride")
  if ld.stride.isNil:
    ld.stride = newLit(1)
  ld.parseCaptures(body)

  var reductionBody: NimNode
  (ld.globalAwaitable, ld.awaitableType, reductionBody) = parseReductionSection(body)
  ld.extractRemoteTaskMerge(reductionBody)

  ld.prologue.extractSection(reductionBody, "prologue")
  ld.forLoop.extractSection(reductionBody, "forLoop")
  ld.epilogue.extractSection(reductionBody, "epilogue")

  # Code generation
  # --------------------------------------------------------
  ld.loopTemplate = loopTemplate
  ld.loopFnName   = ident("ctt_tpParReduceImpl_")
  ld.envName      = ident("ctt_tpParReduceEnv_")
  result.add ld.generateParallelLoop()

  ld.closureName  = ident("ctt_tpParReduceClosure_")
  result.add ld.generateClosure()

  ld.taskName     = ident("ctt_tpParReduceTask_")
  result.add ld.generateAndScheduleLoopTask()

# ############################################################
#                                                            #
#                Parallel For Dispatchers                    #
#                                                            #
# ############################################################

proc hasReduceSection*(body: NimNode): bool =
  for i in 0 ..< body.len:
    if body[i].kind == nnkCall:
      for j in 0 ..< body[i].len:
        if body[i][j].kind == nnkObjConstr and body[i][j][0].eqIdent"reduceInto":
          return true
  return false
