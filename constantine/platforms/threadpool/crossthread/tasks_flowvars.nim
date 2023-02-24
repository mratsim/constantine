# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/atomics,
  ../instrumentation,
  ../../allocs,
  ./backoff

# Tasks have an efficient design so that a single heap allocation
# is required per `spawn`.
# This greatly reduce overhead and potential memory fragmentation for long-running applications.
#
# This is done by tasks:
# - being an intrusive linked lists
# - integrating the channel to send results
#
# Flowvar is the public type created when spawning a task.
# and can be synced to receive the task result.
# Flowvars are also called future interchangeably.
# (The name future is already used for IO scheduling)

type
  Task* = object
    # Synchronization
    # ------------------
    parent*: ptr Task        # When a task is awaiting, a thread can quickly prioritize the direct child of a task
    thiefID*: Atomic[int32]  # ID of the worker that stole and run the task. For leapfrogging.
    hasFuture*: bool         # Ownership: if a task has a future, the future deallocates it. Otherwise the worker thread does.
    completed*: Atomic[bool]
    waiter*: Atomic[ptr EventNotifier]

    # Data parallelism
    # ------------------
    isFirstIter*: bool       # Awaitable for-loops return true for first iter. Loops are split before first iter.
    envSize*: int32          # This is used for splittable loop
    loopStart*: int
    loopStop*: int
    loopStride*: int
    loopStepsLeft*: int
    reductionDAG*: ptr ReductionDagNode # For parallel loop reduction, merge with other range result

    # Execution
    # ------------------
    fn*: proc (env: pointer) {.nimcall, gcsafe, raises: [].}
    # destroy*: proc (env: pointer) {.nimcall, gcsafe.} # Constantine only deals with plain old env
    env*{.align:sizeof(int).}: UncheckedArray[byte]

  Flowvar*[T] = object
    task: ptr Task

  ReductionDagNode* = object
    ## In a parallel reduction, when a loop a split the worker
    ## keeps track of the tasks to gather results from in a private task-local linked-list.
    ## Those forms a global computation directed acyclic graph
    ## with the initial parallel reduction task as root.
    # Note: While this requires an extra allocation per split
    #       the alternative, making an intrusive linked-list of reduction tasks
    #       require synchronization between threads.
    task*: ptr Task
    next*: ptr ReductionDagNode

# Tasks
# -------------------------------------------------------------------------

const SentinelThief* = 0xFACADE'i32

proc newSpawn*(
       T: typedesc[Task],
       parent: ptr Task,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].}
     ): ptr Task {.inline.} =

  const size = sizeof(T)

  result = allocHeapUnchecked(T, size)
  result.parent = parent
  result.thiefID.store(SentinelThief, moRelaxed)
  result.hasFuture = false
  result.completed.store(false, moRelaxed)
  result.waiter.store(nil, moRelaxed)
  result.fn = fn

proc newSpawn*(
       T: typedesc[Task],
       parent: ptr Task,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].},
       env: auto): ptr Task {.inline.} =

  const size = sizeof(T) + # size without Unchecked
               sizeof(env)

  result = allocHeapUnchecked(T, size)
  result.parent = parent
  result.thiefID.store(SentinelThief, moRelaxed)
  result.hasFuture = false
  result.completed.store(false, moRelaxed)
  result.waiter.store(nil, moRelaxed)
  result.fn = fn
  cast[ptr[type env]](result.env)[] = env

func ceilDiv_vartime*(a, b: auto): auto {.inline.} =
  ## ceil division, to be used only on length or at compile-time
  ## ceil(a / b)
  (a + b - 1) div b

proc newLoop*(
       T: typedesc[Task],
       parent: ptr Task,
       start, stop, stride: int,
       isFirstIter: bool,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].}
      ): ptr Task =
  const size = sizeof(T)
  preCondition: start < stop

  result = allocHeapUnchecked(T, size)
  result.parent = parent
  result.thiefID.store(SentinelThief, moRelaxed)
  result.hasFuture = false
  result.completed.store(false, moRelaxed)
  result.waiter.store(nil, moRelaxed)
  result.fn = fn
  result.envSize = 0

  result.isFirstIter = isFirstIter
  result.loopStart = start
  result.loopStop = stop
  result.loopStride = stride
  result.loopStepsLeft = ceilDiv_vartime(stop-start, stride)
  result.reductionDAG = nil

proc newLoop*(
       T: typedesc[Task],
       parent: ptr Task,
       start, stop, stride: int,
       isFirstIter: bool,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].},
       env: auto): ptr Task =

  const size = sizeof(T) + # size without Unchecked
               sizeof(env)
  preCondition: start < stop

  result = allocHeapUnchecked(T, size)
  result.parent = parent
  result.thiefID.store(SentinelThief, moRelaxed)
  result.hasFuture = false
  result.completed.store(false, moRelaxed)
  result.waiter.store(nil, moRelaxed)
  result.fn = fn
  result.envSize = int32(sizeof(env))
  cast[ptr[type env]](result.env)[] = env

  result.isFirstIter = isFirstIter
  result.loopStart = start
  result.loopStop = stop
  result.loopStride = stride
  result.loopStepsLeft = ceilDiv_vartime(stop-start, stride)
  result.reductionDAG = nil

# Flowvars
# -------------------------------------------------------------------------

# proc `=copy`*[T](dst: var Flowvar[T], src: Flowvar[T]) {.error: "Futures/Flowvars cannot be copied".}

proc newFlowVar*(T: typedesc, task: ptr Task): Flowvar[T] {.inline.} =
  result.task = task
  result.task.hasFuture = true

  # Task with future references themselves so that readyWith can be called
  # within the constructed
  #   proc threadpoolSpawn_fn(env: pointer) {.nimcall.}
  # that can only access env
  cast[ptr ptr Task](task.env.addr)[] = task

proc cleanup*(fv: var Flowvar) {.inline.} =
  fv.task.freeHeap()
  fv.task = nil

func isSpawned*(fv: Flowvar): bool {.inline.} =
  ## Returns true if a flowvar is spawned
  ## This may be useful for recursive algorithms that
  ## may or may not spawn a flowvar depending on a condition.
  ## This is similar to Option or Maybe types
  return not fv.task.isNil

func isReady*[T](fv: Flowvar[T]): bool {.inline.} =
  ## Returns true if the result of a Flowvar is ready.
  ## In that case `sync` will not block.
  ## Otherwise the current will block to help on all the pending tasks
  ## until the Flowvar is ready.
  fv.task.completed.load(moAcquire)

func readyWith*[T](task: ptr Task, childResult: T) {.inline.} =
  ## Send the Flowvar result from the child thread processing the task
  ## to its parent thread.
  precondition: not task.completed.load(moAcquire)
  cast[ptr (ptr Task, T)](task.env.addr)[1] = childResult
  task.completed.store(true, moRelease)

proc sync*[T](fv: sink Flowvar[T]): T {.noInit, inline, gcsafe.} =
  ## Blocks the current thread until the flowvar is available
  ## and returned.
  ## The thread is not idle and will complete pending tasks.
  mixin completeFuture
  completeFuture(fv, result)
  cleanup(fv)

# ReductionDagNodes
# -------------------------------------------------------------------------

proc newReductionDagNode*(task: ptr Task, next: ptr ReductionDagNode): ptr ReductionDagNode {.inline.} =
  result = allocHeap(ReductionDagNode)
  result.next = next
  result.task = task