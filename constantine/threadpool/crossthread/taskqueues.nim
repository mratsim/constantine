# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# This file implements a single-producer multi-consumer
# task queue for work-stealing schedulers.
#
# Papers:
# - Dynamic Circular Work-Stealing Deque
#   David Chase, Yossi Lev, 1993
#   https://www.dre.vanderbilt.edu/~schmidt/PDF/work-stealing-dequeue.pdf
#
# - Correct and Efficient Work-Stealing for Weak Memory Models
#   Nhat Minh Lê, Antoniu Pop, Albert Cohen, Francesco Zappa Nardelli, 2013
#   https://fzn.fr/readings/ppopp13.pdf
#
# The task queue implements the following push, pop, steal
#
#    front                                              back
#                 ---------------------------------
#  steal()     <- |         |          |          | <- push()
#                 | Task 0  |  Task 1  |  Task 2  | -> pop()
#  any thread     |         |          |          |    owner-only
#                 ---------------------------------
#
# To reduce contention, stealing is done on the opposite end from push/pop
# so that there is a race only for the very last task.

{.push raises: [], checks: off.} # No exceptions in a multithreading datastructure

import
  std/atomics,
  constantine/platforms/allocs,
  ../instrumentation,
  ./tasks_flowvars

type
  Buf = object
    ## Backend buffer of a Taskqueue
    ## `capacity` MUST be a power of 2
    prevRetired: ptr Buf # intrusive linked list. Used for garbage collection

    capacity: int
    rawBuffer: UncheckedArray[Atomic[ptr Task]]

  Taskqueue* = object
    ## This implements a lock-free, growable, work-stealing task queue.
    ## The owning thread enqueues and dequeues at the back
    ## Foreign threads steal at the front.
    ##
    ## There is no memory reclamation scheme for simplicity
    front {.align: 64.}: Atomic[int]  # Consumers - steal
    back: Atomic[int]                 # Producer  - push/pop
    buf: Atomic[ptr Buf]
    garbage: ptr Buf

proc peek*(tq: var Taskqueue): int =
  ## Estimates the number of items pending in the channel
  ## In a SPMC setting
  ## - If called by the producer the true number might be less
  ##   due to consumers removing items concurrently.
  ## - If called by a consumer the true number is undefined
  ##   as other consumers also remove items concurrently and
  ##   the producer removes them concurrently.
  ##
  ## If the producer peeks and the Chase-Lev Deque returns 0,
  ## the queue is empty.
  ##
  ## This is a non-locking operation.
  let # Handle race conditions
    b = tq.back.load(moRelaxed)  # Only the producer peeks in the threadpool so moRelaxed is enough
    f = tq.front.load(moAcquire)

  if b >= f:
    return b-f
  else:
    return 0

func isPowerOfTwo(n: int): bool {.used, inline.} =
  (n and (n - 1)) == 0 and (n != 0)

proc newBuf(capacity: int): ptr Buf =
  # Tasks have a destructor
  # static:
  #   doAssert supportsCopyMem(T), $T & " must be a (POD) plain-old-data type: no seq, string, ref."

  preCondition: capacity.isPowerOfTwo()

  result = allocHeapUnchecked(Buf, 1*sizeof(pointer) + 2*sizeof(int) + sizeof(pointer)*capacity)

  result.prevRetired = nil
  result.capacity = capacity
  result.rawBuffer.addr.zeroMem(sizeof(pointer)*capacity)

proc `[]=`(buf: var Buf, index: int, item: ptr Task) {.inline.} =
  buf.rawBuffer[index and (buf.capacity-1)].store(item, moRelaxed)

proc `[]`(buf: var Buf, index: int): ptr Task {.inline.} =
  result = buf.rawBuffer[index and (buf.capacity-1)].load(moRelaxed)

proc grow(tq: var Taskqueue, buf: var ptr Buf, newCapacity, front, back: int) {.inline.} =
  ## Double the buffer size
  ## back is the last item index
  ##
  ## To handle race-conditions the current "front", "back" and "buf"
  ## have to be saved before calling this procedure.
  ## It reads and writes the "tq.buf" and "tq.garbage"

  # Read -> Copy -> Update
  var tmp = newBuf(newCapacity)
  for i in front ..< back:
    tmp[][i] = buf[][i]

  buf.prevRetired = tq.garbage
  tq.garbage = buf
  # publish globally
  tq.buf.store(tmp, moRelaxed)
  # publish locally
  swap(buf, tmp)

proc garbageCollect(tq: var Taskqueue) {.inline.} =
  var node = tq.garbage
  while node != nil:
    let tmp = node.prevRetired
    freeHeap(node)
    node = tmp
  tq.garbage = nil

# Public API
# ---------------------------------------------------

proc init*(tq: var Taskqueue, initialCapacity: int) =
  zeroMem(tq.addr, tq.sizeof())
  tq.buf.store(newBuf(initialCapacity), moRelaxed)

proc teardown*(tq: var Taskqueue) =
  tq.garbageCollect()
  freeHeap(tq.buf.load(moRelaxed))

proc push*(tq: var Taskqueue, item: ptr Task) =
  ## Enqueue an item at the back
  ## As the task queue takes ownership of it. The item must not be used afterwards.
  ## This is intended for the producer only.

  let # Handle race conditions
    b = tq.back.load(moRelaxed)
    f = tq.front.load(moAcquire)
  var buf = tq.buf.load(moRelaxed)

  if b-f > buf.capacity - 1:
    # Full queue
    tq.grow(buf, buf.capacity*2, f, b)

  if not tq.garbage.isNil and f == b:
    # Empty queue, no thieves can have a pointer to an old retired buffer
    tq.garbageCollect()

  buf[][b] = item
  fence(moRelease)
  tq.back.store(b+1, moRelaxed)

proc pop*(tq: var Taskqueue): ptr Task =
  ## Dequeue an item at the back. Takes ownership of the item
  ## This is intended for the producer only.

  let # Handle race conditions
    b = tq.back.load(moRelaxed) - 1
    buf = tq.buf.load(moRelaxed)

  tq.back.store(b, moRelaxed)
  fence(moSequentiallyConsistent)
  var f = tq.front.load(moRelaxed)

  if f <= b:
    # Non-empty queue.
    result = buf[][b]
    if f == b:
      # Single last element in queue.
      if not compareExchange(tq.front, f, f+1, moSequentiallyConsistent, moRelaxed):
        # Failed race.
        result = nil
      tq.back.store(b+1, moRelaxed)
      if not tq.garbage.isNil:
          # Empty queue, no thieves can have a pointer to an old retired buffer
          tq.garbageCollect()
  else:
    # Empty queue.
    result = nil
    tq.back.store(b+1, moRelaxed)
    if not tq.garbage.isNil:
        # Empty queue, no thieves can have a pointer to an old retired buffer
        tq.garbageCollect()

proc steal*(thiefID: int32, tq: var Taskqueue): ptr Task =
  ## Dequeue an item at the front. Takes ownership of the item
  ## This is intended for consumers.
  var f = tq.front.load(moAcquire)
  fence(moSequentiallyConsistent)
  let b = tq.back.load(moAcquire)
  result = nil

  if f < b:
    # Non-empty queue.
    let a = tq.buf.load(moConsume)
    result = a[][f]
    if not compareExchange(tq.front, f, f+1, moSequentiallyConsistent, moRelaxed):
      # Failed race.
      return nil
    result.setThief(thiefID)
