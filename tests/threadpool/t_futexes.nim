# taskpools
# Copyright (c) 2021-2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [], gcsafe.}

import
  std/[atomics, os, unittest],
  constantine/threadpool/primitives/futexes

const
  observeWindowMs = 100
  maxParkedSpins = 10_000

type
  WaitState = object
    futex: Futex
    reachedWait: Atomic[bool]  # waiter has entered its wait loop
    spins: Atomic[int]         # times wait() returned while still unsignalled
    woke: Atomic[bool]         # waiter observed the signal and left the loop

  WakeAllState = object
    futex: Futex
    ready: Atomic[int]         # count of waiters that entered their wait loop
    woke: Atomic[int]          # count of waiters released after the signal

proc spinUntil[T](a: var Atomic[T], expected: T) =
  while a.load(moAcquire) != expected:
    discard

proc waiter(s: ptr WaitState) {.thread.} =
  s.reachedWait.store(true, moRelease)
  while s.futex.load(moAcquire) == 0:
    s.futex.wait(0)
    discard s.spins.fetchAdd(1, moRelaxed)
  s.woke.store(true, moRelease)

proc wakeAllWaiter(s: ptr WakeAllState) {.thread.} =
  discard s.ready.fetchAdd(1, moRelease)
  while s.futex.load(moAcquire) == 0:
    s.futex.wait(0)
  discard s.woke.fetchAdd(1, moRelease)

suite "Futex":
  test "wait() parks the thread until wake()":
    var s: WaitState
    s.futex.initialize()

    var thr: Thread[ptr WaitState]
    createThread(thr, waiter, addr s)

    # This is racy but if the futex does not
    # wait and return immediately, it should register
    # more than maxParkedSpins in observeWindowMs.
    spinUntil(s.reachedWait, true)
    sleep(observeWindowMs)
    check s.spins.load(moAcquire) < maxParkedSpins
    check not s.woke.load(moAcquire)

    s.futex.store(1, moRelease)
    s.futex.wake()
    joinThread(thr)
    check s.woke.load(moAcquire)

    s.futex.teardown()

  test "wait() returns immediately when value != expected":
    var futex: Futex
    futex.initialize()
    futex.store(1, moRelease)
    futex.wait(0)  # won't hang because value != expected
    futex.teardown()

  test "wakeAll() releases every parked waiter":
    const numWaiters = 4
    var s: WakeAllState
    s.futex.initialize()

    var threads: array[numWaiters, Thread[ptr WakeAllState]]
    for t in mitems(threads):
      createThread(t, wakeAllWaiter, addr s)

    spinUntil(s.ready, numWaiters)
    s.futex.store(1, moRelease)
    s.futex.wakeAll()
    joinThreads(threads)

    check s.woke.load(moAcquire) == numWaiters
    s.futex.teardown()
