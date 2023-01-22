# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# An implementation of futex using Windows primitives

import std/atomics, winlean
export MemoryOrder

type
  Futex* = object
    value: Atomic[uint32]

# Contrary to the documentation, the futex related primitives are NOT in kernel32.dll
# but in api-ms-win-core-synch-l1-2-0.dll ¯\_(ツ)_/¯

proc initialize*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)

proc teardown*(futex: var Futex) {.inline.} =
  futex.value.store(0, moRelaxed)

proc WaitOnAddress(
        Address: pointer, CompareAddress: pointer,
        AddressSize: csize_t, dwMilliseconds: DWORD
       ): WINBOOL {.importc, stdcall, dynlib: "api-ms-win-core-synch-l1-2-0".}
  # The Address should be volatile

proc WakeByAddressSingle(Address: pointer) {.importc, stdcall, dynlib: "api-ms-win-core-synch-l1-2-0".}
proc WakeByAddressAll(Address: pointer) {.importc, stdcall, dynlib: "api-ms-win-core-synch-l1-2-0".}

proc load*(futex: var Futex, order: MemoryOrder): uint32 {.inline.} =
  futex.value.load(order)

proc loadMut*(futex: var Futex): var Atomic[uint32] {.inline.} =
  futex.value

proc store*(futex: var Futex, value: uint32, order: MemoryOrder) {.inline.} =
  futex.value.store(value, order)

proc wait*(futex: var Futex, refVal: uint32) {.inline.} =
  ## Suspend a thread if the value of the futex is the same as refVal.

  # Returns TRUE if the wait succeeds or FALSE if not.
  # getLastError() will contain the error information, for example
  # if it failed due to a timeout.
  # We discard as this is not needed and simplifies compat with Linux futex
  discard WaitOnAddress(futex.value.addr, refVal.unsafeAddr, csize_t sizeof(refVal), INFINITE)

proc wake*(futex: var Futex) {.inline.} =
  ## Wake one thread (from the same process)
  WakeByAddressSingle(futex.value.addr)

proc wakeAll*(futex: var Futex) {.inline.} =
  ## Wake all threads (from the same process)
  WakeByAddressAll(futex.value.addr)