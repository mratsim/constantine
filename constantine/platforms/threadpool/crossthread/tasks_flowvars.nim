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
    # Intrusive metadata
    # ------------------
    parent*: ptr Task # When a task is awaiting, a thread can quickly prioritize the direct child of a task

    thiefID*: Atomic[int32] # ID of the worker that stole and run the task. For leapfrogging.

    # Result sync
    # ------------------
    hasFuture*: bool         # Ownership: if a task has a future, the future deallocates it. Otherwise the worker thread does.
    completed*: Atomic[bool]
    waiter*: Atomic[ptr EventNotifier]

    # Execution
    # ------------------
    fn*: proc (param: pointer) {.nimcall, gcsafe, raises: [].}
    # destroy*: proc (param: pointer) {.nimcall, gcsafe.} # Constantine only deals with plain old data
    data*{.align:sizeof(int).}: UncheckedArray[byte]

  Flowvar*[T] = object
    task: ptr Task

const SentinelThief* = 0xFACADE'i32

proc new*(
       T: typedesc[Task],
       parent: ptr Task,
       fn: proc (param: pointer) {.nimcall, gcsafe.}): ptr Task {.inline.} =

  const size = sizeof(T)

  result = allocHeapUnchecked(T, size)
  result.parent = parent
  result.thiefID.store(SentinelThief, moRelaxed)
  result.hasFuture = false
  result.completed.store(false, moRelaxed)
  result.waiter.store(nil, moRelaxed)
  result.fn = fn

proc new*(
       T: typedesc[Task],
       parent: ptr Task,
       fn: proc (param: pointer) {.nimcall, gcsafe, raises: [].},
       params: auto): ptr Task {.inline.} =

  const size = sizeof(T) + # size without Unchecked
               sizeof(params)

  result = allocHeapUnchecked(T, size)
  result.parent = parent
  result.thiefID.store(SentinelThief, moRelaxed)
  result.hasFuture = false
  result.completed.store(false, moRelaxed)
  result.waiter.store(nil, moRelaxed)
  result.fn = fn
  cast[ptr[type params]](result.data)[] = params

# proc `=copy`*[T](dst: var Flowvar[T], src: Flowvar[T]) {.error: "Futures/Flowvars cannot be copied".}

proc newFlowVar*(T: typedesc, task: ptr Task): Flowvar[T] {.inline.} =
  result.task = task
  result.task.hasFuture = true

  # Task with future references themselves so that readyWith can be called
  # within the constructed
  #   proc async_fn(param: pointer) {.nimcall.}
  # that can only access data
  cast[ptr ptr Task](task.data.addr)[] = task

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
  cast[ptr (ptr Task, T)](task.data.addr)[1] = childResult
  task.completed.store(true, moRelease)

proc sync*[T](fv: sink Flowvar[T]): T {.inline, gcsafe.} =
  ## Blocks the current thread until the flowvar is available
  ## and returned.
  ## The thread is not idle and will complete pending tasks.
  mixin completeFuture
  completeFuture(fv, result)
  cleanup(fv)
