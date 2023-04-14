# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/atomics,
  ./scoped_barriers,
  ../instrumentation,
  ../../allocs,
  ../primitives/futexes

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

const NotALoop* = -1

type
  TaskState = object
    ## This state allows synchronization between:
    ## - a waiter that may sleep if no work and task is incomplete
    ## - a thief that completes the task
    ## - a waiter that frees task memory
    ## - a waiter that will pick up the task continuation
    ##
    ## Supports up to 2¹⁵ = 32768 threads
    completed: Futex
    synchro: Atomic[uint32]
    # type synchro = object
    #   canBeFreed {.bitsize:  1.}: uint32 - Transfer ownership from thief to waiter
    #   pad        {.bitsize:  1.}: uint32
    #   waiterID   {.bitsize: 15.}: uint32 - ID of the waiter blocked on the task completion.
    #   thiefID    {.bitsize: 15.}: uint32 - ID of the worker that stole and run the task. For leapfrogging.

  Task* = object
    # Synchronization
    # ------------------
    state: TaskState
    parent*: ptr Task  # Latency: When a task is awaited, a thread can quickly prioritize its direct children.
    scopedBarrier*: ptr ScopedBarrier
    hasFuture*: bool   # Ownership: if a task has a future, the future deallocates it. Otherwise the worker thread does.

    # Data parallelism
    # ------------------
    isFirstIter*: bool # Load-Balancing: New loops are split before first iter. Split loops are run once before reconsidering split.
    envSize*: int32    # Metadata: In splittable loops we need to copy the `env` upon splitting
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
    # Flowvar is a public object, but we don't want
    # end-user to access the underlying task, so keep the field private.
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

# Task State
# -------------------------------------------------------------------------

# Tasks have the following lifecycle:
# - A task creator that schedule a task on its queue
# - A task runner, task creator or thief, that runs the task
# - Once the task is finished:
#   - if the task has no future, the task runner frees the task
#   - if the task has a future,
#     - the task runner can immediately pick up new work
#     - the awaiting thread frees the task
#     - the awaiting thread might be sleeping and need to be woken up.
#
# There is a delicate dance as we are need to prevent 2 issues:
#
# 1. A deadlock:        if the waiter is never woken up after the thief completes the task
# 2. A use-after-free:  if the thief tries to access the task after the waiter frees it.
#
# To solve 1, we need to set a `completed` flag, then check again if the waiter parked before.
# To solve 2, we either need to ensure that after the `completed` flag is set, the task runner
#             doesn't access the task anymore which is impossible due to 1;
#             or we have the waiter spinlock on another flag `canBeFreed`.

const # bitfield setup
  kCanBeFreedShift = 31
  kCanBeFreed      = 1'u32 shl kCanBeFreedShift
  kCanBeFreedMask  = kCanBeFreed   # 0x80000000

  kWaiterShift     = 15
  kThiefMask       = (1'u32 shl kWaiterShift) - 1 # 0x00007FFF
  kWaiterMask      = kThiefMask shl kWaiterShift  # 0x3FFF8000

  SentinelWaiter = high(uint32) and kWaiterMask
  SentinelThief* = high(uint32) and kThiefMask

proc initSynchroState*(task: ptr Task) {.inline.} =
  task.state.completed.store(0, moRelaxed)
  task.state.synchro.store(SentinelWaiter or SentinelThief, moRelaxed)

# Flowvar synchronization
# -----------------------

proc isGcReady*(task: ptr Task): bool {.inline.} =
  ## Check if task can be freed by the waiter if it was stolen
  (task.state.synchro.load(moAcquire) and kCanBeFreedMask) != 0

proc setGcReady*(task: ptr Task) {.inline.} =
  ## Thief transfers full task ownership to waiter
  discard task.state.synchro.fetchAdd(kCanBeFreed, moRelease)

proc isCompleted*(task: ptr Task): bool {.inline.} =
  ## Check task completion
  task.state.completed.load(moAcquire) != 0

proc setCompleted*(task: ptr Task) {.inline.} =
  ## Set a task to `complete`
  ## Wake a waiter thread if there is one
  task.state.completed.store(1, moRelaxed)
  fence(moSequentiallyConsistent)
  let waiter = task.state.synchro.load(moRelaxed)
  if (waiter and kWaiterMask) != SentinelWaiter:
    task.state.completed.wake()

proc sleepUntilComplete*(task: ptr Task, waiterID: int32) {.inline.} =
  ## Sleep while waiting for task completion
  let waiter = (cast[uint32](waiterID) shl kWaiterShift) - SentinelWaiter
  discard task.state.synchro.fetchAdd(waiter, moRelaxed)
  fence(moAcquire)
  while task.state.completed.load(moRelaxed) == 0:
    task.state.completed.wait(0)

# Leapfrogging synchronization
# ----------------------------

proc getThief*(task: ptr Task): uint32 {.inline.} =
  task.state.synchro.load(moAcquire) and kThiefMask

proc setThief*(task: ptr Task, thiefID: int32) {.inline.} =
  let thief = cast[uint32](thiefID) - SentinelThief
  discard task.state.synchro.fetchAdd(thief, moRelease)

# Tasks
# -------------------------------------------------------------------------

proc newSpawn*(
       T: typedesc[Task],
       parent: ptr Task,
       scopedBarrier: ptr ScopedBarrier,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].}
     ): ptr Task {.inline.} =

  const size = sizeof(T)

  scopedBarrier.registerDescendant()

  result = allocHeapUnchecked(T, size)
  result.initSynchroState()
  result.parent = parent
  result.scopedBarrier = scopedBarrier
  result.hasFuture = false
  result.fn = fn

  when defined(TP_Metrics):
    result.loopStepsLeft = NotALoop

proc newSpawn*(
       T: typedesc[Task],
       parent: ptr Task,
       scopedBarrier: ptr ScopedBarrier,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].},
       env: auto): ptr Task {.inline.} =

  const size = sizeof(T) + # size without Unchecked
               sizeof(env)

  scopedBarrier.registerDescendant()

  result = allocHeapUnchecked(T, size)
  result.initSynchroState()
  result.parent = parent
  result.scopedBarrier = scopedBarrier
  result.hasFuture = false
  result.fn = fn
  cast[ptr[type env]](result.env)[] = env

  when defined(TP_Metrics):
    result.loopStepsLeft = NotALoop

func ceilDiv_vartime(a, b: auto): auto {.inline.} =
  (a + b - 1) div b

proc newLoop*(
       T: typedesc[Task],
       parent: ptr Task,
       scopedBarrier: ptr ScopedBarrier,
       start, stop, stride: int,
       isFirstIter: bool,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].}
      ): ptr Task =
  const size = sizeof(T)
  preCondition: start < stop

  scopedBarrier.registerDescendant()

  result = allocHeapUnchecked(T, size)
  result.initSynchroState()
  result.parent = parent
  result.scopedBarrier = scopedBarrier
  result.hasFuture = false
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
       scopedBarrier: ptr ScopedBarrier,
       start, stop, stride: int,
       isFirstIter: bool,
       fn: proc (env: pointer) {.nimcall, gcsafe, raises: [].},
       env: auto): ptr Task =

  const size = sizeof(T) + # size without Unchecked
               sizeof(env)
  preCondition: start < stop

  scopedBarrier.registerDescendant()

  result = allocHeapUnchecked(T, size)
  result.initSynchroState()
  result.parent = parent
  result.scopedBarrier = scopedBarrier
  result.hasFuture = false
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
  while not fv.task.isGcReady():
    cpuRelax()
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
  fv.task.isCompleted()

func readyWith*[T](task: ptr Task, childResult: T) {.inline.} =
  ## Send the Flowvar result from the child thread processing the task
  ## to its parent thread.
  cast[ptr (ptr Task, T)](task.env.addr)[1] = childResult

func copyResult*[T](dst: var T, fv: FlowVar[T]) {.inline.} =
  ## Copy the result of a ready Flowvar to `dst`
  dst = cast[ptr (ptr Task, T)](fv.task.env.addr)[1]

func getTask*[T](fv: FlowVar[T]): ptr Task {.inline.} =
  ## Copy the result of a ready Flowvar to `dst`
  fv.task

# ReductionDagNodes
# -------------------------------------------------------------------------

proc newReductionDagNode*(task: ptr Task, next: ptr ReductionDagNode): ptr ReductionDagNode {.inline.} =
  result = allocHeap(ReductionDagNode)
  result.next = next
  result.task = task
