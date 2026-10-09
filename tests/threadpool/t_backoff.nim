# taskpools
# Copyright (c) 2021-2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [], gcsafe.}

import
  std/[atomics, os, unittest],
  constantine/threadpool/crossthread/backoff

# Tests for the EventCount (the lock-free condition-variable equivalent in
# backoff.nim). The parking protocol is:
#
#   while not condition:
#     ticket = ec.sleepy()      # announce intent to sleep (pre-wait)
#     if condition:
#       ec.cancelSleep()        # bail out, undo the pre-wait
#       break
#     ec.sleep(ticket)          # commit and park until wake() bumps the epoch
#
# A wake() between sleepy() and sleep() bumps the epoch, invalidating the
# ticket so sleep() returns without parking. That is how lost wakeups are
# avoided, and we test it directly (single-threaded, deterministic).

const
  observeWindowMs = 100
  maxParkedSpins = 10_000

type
  ParkState = object
    ec: EventCount
    reached: Atomic[bool]
    condition: Atomic[bool]
    spins: Atomic[int]         # outer-loop iterations while unsignalled
    woke: Atomic[bool]

  WakeAllState = object
    ec: EventCount
    condition: Atomic[bool]
    woke: Atomic[int]

proc spinUntilBool(a: var Atomic[bool], expected: bool) =
  while a.load(moAcquire) != expected:
    discard

proc parker(s: ptr ParkState) {.thread.} =
  s.reached.store(true, moRelease)
  while not s.condition.load(moAcquire):
    let ticket = s.ec.sleepy()
    if s.condition.load(moAcquire):
      s.ec.cancelSleep()
      break
    s.ec.sleep(ticket)
    discard s.spins.fetchAdd(1, moRelaxed)
  s.woke.store(true, moRelease)

proc multiParker(s: ptr WakeAllState) {.thread.} =
  while not s.condition.load(moAcquire):
    let ticket = s.ec.sleepy()
    if s.condition.load(moAcquire):
      s.ec.cancelSleep()
      break
    s.ec.sleep(ticket)
  discard s.woke.fetchAdd(1, moRelease)

suite "EventCount":
  test "sleepy() then cancelSleep() leaves no waiters":
    var ec: EventCount
    ec.initialize()

    check ec.getNumWaiters().preSleep == 0
    check ec.getNumWaiters().committedSleep == 0
    discard ec.sleepy()
    check ec.getNumWaiters().preSleep == 1
    check ec.getNumWaiters().committedSleep == 0
    ec.cancelSleep()
    check ec.getNumWaiters().preSleep == 0
    check ec.getNumWaiters().committedSleep == 0

  test "sleep() does not park when the ticket is stale":
    # wake() between sleepy() and sleep() bumps the epoch; sleep() must observe
    # the change and return immediately instead of blocking forever.
    var ec: EventCount
    ec.initialize()

    let ticket = ec.sleepy()
    ec.wake()                       # invalidates the ticket's epoch
    ec.sleep(ticket)                # would hang if it parked on the stale epoch

    check ec.getNumWaiters().preSleep == 0
    check ec.getNumWaiters().committedSleep == 0

  test "sleep() parks the thread until wake()":
    var s: ParkState
    s.ec.initialize()

    var thr: Thread[ptr ParkState]
    createThread(thr, parker, addr s)

    # This is racy but if the futex does not
    # wait and return immediately, it should register
    # more than maxParkedSpins in observeWindowMs.
    spinUntilBool(s.reached, true)
    sleep(observeWindowMs)
    check s.spins.load(moAcquire) < maxParkedSpins
    check not s.woke.load(moAcquire)

    s.condition.store(true, moRelease)
    s.ec.wake()
    joinThread(thr)

    check s.woke.load(moAcquire)
    check s.ec.getNumWaiters().preSleep == 0
    check s.ec.getNumWaiters().committedSleep == 0

  test "wakeAll() releases every parked waiter":
    const numWaiters = 4
    var s: WakeAllState
    s.ec.initialize()

    var threads: array[numWaiters, Thread[ptr WakeAllState]]
    for t in mitems(threads):
      createThread(t, multiParker, addr s)

    while s.ec.getNumWaiters().committedSleep != numWaiters:
      discard

    s.condition.store(true, moRelease)
    s.ec.wakeAll()
    joinThreads(threads)

    check s.woke.load(moAcquire) == numWaiters
    check s.ec.getNumWaiters().preSleep == 0
    check s.ec.getNumWaiters().committedSleep == 0

  test "supports more than 256 committed waiters":
    const numWaiters = 257
    var s: WakeAllState
    s.ec.initialize()

    var threads = newSeq[Thread[ptr WakeAllState]](numWaiters)
    for t in mitems(threads):
      createThread(t, multiParker, addr s)

    while s.ec.getNumWaiters().committedSleep != numWaiters:
      discard

    s.condition.store(true, moRelease)
    s.ec.wakeAll()
    joinThreads(threads)

    check s.woke.load(moAcquire) == numWaiters
    check s.ec.getNumWaiters().preSleep == 0
    check s.ec.getNumWaiters().committedSleep == 0
