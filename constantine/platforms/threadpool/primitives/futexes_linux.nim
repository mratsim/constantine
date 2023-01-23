# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# A wrapper for linux futex.
# Condition variables do not always wake on signal which can deadlock the runtime
# so we need to roll up our sleeves and use the low-level futex API.

import std/atomics
export MemoryOrder

type
  Futex* = object
    value: Atomic[uint32]
  FutexOp = distinct cint

var NR_Futex {.importc: "__NR_futex", header: "<sys/syscall.h>".}: cint
var FutexWaitPrivate {.importc:"FUTEX_WAIT_PRIVATE", header: "<linux/futex.h>".}: FutexOp
var FutexWakePrivate {.importc:"FUTEX_WAKE_PRIVATE", header: "<linux/futex.h>".}: FutexOp

proc syscall(sysno: clong): cint {.header:"<unistd.h>", varargs.}

proc sysFutex(
       futex: var Futex, op: FutexOp, val1: cuint or cint,
       timeout: pointer = nil, val2: pointer = nil, val3: cint = 0): cint {.inline.} =
  syscall(NR_Futex, futex.value.addr, op, val1, timeout, val2, val3)

proc initialize*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)

proc teardown*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)

proc load*(futex: var Futex, order: MemoryOrder): uint32 {.inline.} =
  futex.value.load(order)

proc loadMut*(futex: var Futex): var Atomic[uint32] {.inline.} =
  futex.value

proc store*(futex: var Futex, value: uint32, order: MemoryOrder) {.inline.} =
  futex.value.store(value, order)

proc wait*(futex: var Futex, refVal: uint32) {.inline.} =
  ## Suspend a thread if the value of the futex is the same as refVal.

  # Returns 0 in case of a successful suspend
  # If value are different, it returns EWOULDBLOCK
  # We discard as this is not needed and simplifies compat with Windows futex
  discard sysFutex(futex, FutexWaitPrivate, refVal)

proc wake*(futex: var Futex) {.inline.} =
  ## Wake one thread (from the same process)

  # Returns the number of actually woken threads
  # or a Posix error code (if negative)
  # We discard as this is not needed and simplifies compat with Windows futex
  discard sysFutex(futex, FutexWakePrivate, 1)

proc wakeAll*(futex: var Futex) {.inline.} =
  ## Wake all threads (from the same process)

  # Returns the number of actually woken threads
  # or a Posix error code (if negative)
  # We discard as this is not needed and simplifies compat with Windows futex
  discard sysFutex(futex, FutexWakePrivate, high(int32))