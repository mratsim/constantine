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

# OS primitives
# ------------------------------------------------------------------------



const
  NR_Futex = 202

  FUTEX_WAIT_PRIVATE = 128
  FUTEX_WAKE_PRIVATE = 129

proc syscall(sysno: clong): cint {.importc, header:"<unistd.h>", varargs.}

proc sysFutex(
       futexAddr: pointer, operation: uint32, expected: uint32 or int32,
       timeout: pointer = nil, val2: pointer = nil, val3: cint = 0): cint {.inline.} =
  ## See https://web.archive.org/web/20230208151430/http://locklessinc.com/articles/futex_cheat_sheet/
  ## and https://www.akkadia.org/drepper/futex.pdf
  syscall(NR_Futex, futexAddr, operation, expected, timeout, val2, val3)

# Futex API
# ------------------------------------------------------------------------

type
  Futex* = object
    value: Atomic[uint32]

proc initialize*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)

proc teardown*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)

proc load*(futex: var Futex, order: MemoryOrder): uint32 {.inline.} =
  futex.value.load(order)

proc store*(futex: var Futex, value: uint32, order: MemoryOrder) {.inline.} =
  futex.value.store(value, order)

proc increment*(futex: var Futex, value: uint32, order: MemoryOrder): uint32 {.inline.} =
  ## Increment a futex value, returns the previous one.
  futex.value.fetchAdd(value, order)

proc wait*(futex: var Futex, expected: uint32) {.inline.} =
  ## Suspend a thread if the value of the futex is the same as expected.

  # Returns 0 in case of a successful suspend
  # If value are different, it returns EWOULDBLOCK
  # We discard as this is not needed and simplifies compat with Windows futex
  discard sysFutex(futex.value.addr, FutexWaitPrivate, expected)

proc wake*(futex: var Futex) {.inline.} =
  ## Wake one thread (from the same process)

  # Returns the number of actually woken threads
  # or a Posix error code (if negative)
  # We discard as this is not needed and simplifies compat with Windows futex
  discard sysFutex(futex.value.addr, FutexWakePrivate, 1)

proc wakeAll*(futex: var Futex) {.inline.} =
  ## Wake all threads (from the same process)

  # Returns the number of actually woken threads
  # or a Posix error code (if negative)
  # We discard as this is not needed and simplifies compat with Windows futex
  discard sysFutex(futex.value.addr, FutexWakePrivate, high(int32))