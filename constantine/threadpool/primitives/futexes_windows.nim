# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# An implementation of futex using Windows primitives

import std/atomics, winlean

# OS primitives
# ------------------------------------------------------------------------

# Contrary to the documentation, the futex related primitives are NOT in kernel32.dll
# but in API-MS-Win-Core-Synch-l1-2-0.dll ¯\_(ツ)_/¯
proc WaitOnAddress(
        Address: pointer, CompareAddress: pointer,
        AddressSize: csize_t, dwMilliseconds: DWORD
       ): WINBOOL {.importc, stdcall, dynlib: "API-MS-Win-Core-Synch-l1-2-0.dll".}
  # The Address should be volatile

proc WakeByAddressSingle(Address: pointer) {.importc, stdcall, dynlib: "API-MS-Win-Core-Synch-l1-2-0.dll".}
proc WakeByAddressAll(Address: pointer) {.importc, stdcall, dynlib: "API-MS-Win-Core-Synch-l1-2-0.dll".}

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

  # Returns TRUE if the wait succeeds or FALSE if not.
  # getLastError() will contain the error information, for example
  # if it failed due to a timeout.
  # We discard as this is not needed and simplifies compat with Linux futex
  discard WaitOnAddress(futex.value.addr, expected.unsafeAddr, csize_t sizeof(expected), INFINITE)

proc wake*(futex: var Futex) {.inline.} =
  ## Wake one thread (from the same process)
  WakeByAddressSingle(futex.value.addr)

proc wakeAll*(futex: var Futex) {.inline.} =
  ## Wake all threads (from the same process)
  WakeByAddressAll(futex.value.addr)
