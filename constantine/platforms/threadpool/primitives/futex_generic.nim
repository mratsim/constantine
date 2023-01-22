# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/[locks, atomics]

type Futex* = object
  value: Atomic[uint32]
  lock: Lock
  cond: Cond

proc initialize*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)
  futex.lock.initLock()
  futex.cond.initCond()

proc teardown*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)
  futex.lock.deinitLock()
  futex.cond.deinitCond()

proc load*(futex: var Futex, order: MemoryOrder): uint32 {.inline.} =
  futex.value.load(order)

proc loadMut*(futex: var Futex): var Atomic[uint32] {.inline.} =
  futex.value

proc store*(futex: var Futex, value: uint32, order: MemoryOrder) {.inline.} =
  futex.value.store(value, order)

proc wait*(futex: var Futex, refVal: uint32) {.inline.} =
  ## Suspend a thread if the value of the futex is the same as refVal.
  if futex.value.load(moSequentiallyConsistent) == refVal:
    futex.cond.wait(futex.lock)

proc wake*(futex: var Futex) {.inline.} =
  ## Wake one thread (from the same process)
  futex.cond.signal()

type Errno = cint
proc pthread_cond_broadcast(cond: var Cond): Errno {.header:"<pthread.h>".}
  ## Nim only signal one thread in locks
  ## We need to unblock all

proc broadcast(cond: var Cond) {.inline.}=
  discard pthread_cond_broadcast(cond)

proc wakeAll*(futex: var Futex) {.inline.} =
  ## Wake all threads (from the same process)
  futex.cond.broadcast()