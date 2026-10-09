# taskpools
# Copyright (c) 2021-2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## Regression tests for a scheduler lost wakeup.

{.push raises: [], gcsafe.}

import
  std/[atomics, unittest],
  constantine/threadpool

const
  sweepRounds = 400_000
  senderBatch = 2
    ## Two is the whole race: the first push finds the deque empty and notifies,
    ## the second peeks while the first is still queued and must decide again.
  pollBatch = 2

type
  Entry = object
    ready {.align: 64.}: Atomic[bool]
    value: Atomic[int]

var
  tp: Threadpool
  entries: array[senderBatch, Entry]

proc senderTask(i: int): bool =
  entries[i].value.store(i * 2 + 1, moRelease)
  entries[i].ready.store(true, moRelease)
  true

proc pollTask(i: int): int =
  i * 3 + 1

proc runSenderBatch() =
  ## withSenderParallel: spawn a batch, wait on a side channel, sync at the end.
  for i in 0 ..< senderBatch:
    entries[i].ready.store(false, moRelease)
    entries[i].value.store(0, moRelease)

  var futs: array[senderBatch, Flowvar[bool]]
  # Both land in the spawner's own deque; only an empty -> non-empty transition
  # notifies anybody.
  for i in 0 ..< senderBatch:
    futs[i] = tp.spawn senderTask(i)

  # Deliberately not `sync`: waiting here keeps the spawner out of the
  # scheduler, so it never drains the deque it just filled. If the second task
  # was stranded this spins forever, which is the intended signal.
  for i in 0 ..< senderBatch:
    while not entries[i].ready.load(moAcquire):
      cpuRelax()
    doAssert entries[i].value.load(moAcquire) == i * 2 + 1

  # Only now, in the equivalent of the `finally`.
  for i in 0 ..< senderBatch:
    doAssert sync(futs[i])

proc allReady(futs: var array[pollBatch, Flowvar[int]]): bool =
  for i in 0 ..< pollBatch:
    if not futs[i].isReady():
      return false
  true

proc runPollBatch() =
  ## aristo computeKeyImpl: spawn a batch, poll isReady, sync once ready.
  var futs: array[pollBatch, Flowvar[int]]
  for i in 0 ..< pollBatch:
    futs[i] = tp.spawn pollTask(i)

  while not allReady(futs):
    cpuRelax()

  for i in 0 ..< pollBatch:
    doAssert sync(futs[i]) == i * 3 + 1

suite "Spawn then wait without re-entering the scheduler":
  test "send and poll":
    tp = Threadpool.new(2)
    for r in 0 ..< sweepRounds:
      runSenderBatch()
      runPollBatch()
    tp.syncAll()
    tp.shutdown()
