# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/atomics

# OS primitives
# ------------------------------------------------------------------------

# Darwin futexes.
# They are used in libc++ so likely to be very stable.
# A new API appeared in OSX Big Sur (Jan 2021) ulock_wait2 and macOS pthread_cond_t has been migrated to it
# - https://github.com/apple/darwin-xnu/commit/d4061fb0260b3ed486147341b72468f836ed6c8f#diff-08f993cc40af475663274687b7c326cc6c3031e0db3ac8de7b24624610616be6
#
# The old API is ulock_wait
# - https://opensource.apple.com/source/xnu/xnu-7195.81.3/bsd/kern/sys_ulock.c.auto.html
# - https://opensource.apple.com/source/xnu/xnu-7195.81.3/bsd/sys/ulock.h.auto.html

{.push hint[XDeclaredButNotUsed]: off.}

const UL_COMPARE_AND_WAIT            = 1
const UL_UNFAIR_LOCK                 = 2
const UL_COMPARE_AND_WAIT_SHARED     = 3
const UL_UNFAIR_LOCK64_SHARED        = 4
const UL_COMPARE_AND_WAIT64          = 5
const UL_COMPARE_AND_WAIT64_SHARED   = 6
# obsolete names
const UL_OSSPINLOCK                  = UL_COMPARE_AND_WAIT
const UL_HANDOFFLOCK                 = UL_UNFAIR_LOCK
#  These operation code are only implemented in (DEVELOPMENT || DEBUG) kernels
const UL_DEBUG_SIMULATE_COPYIN_FAULT = 253
const UL_DEBUG_HASH_DUMP_ALL         = 254
const UL_DEBUG_HASH_DUMP_PID         = 255

# operation bits [15, 8] contain the flags for __ulock_wake
#
const ULF_WAKE_ALL                   =  0x00000100
const ULF_WAKE_THREAD                =  0x00000200
const ULF_WAKE_ALLOW_NON_OWNER       =  0x00000400

# operation bits [23, 16] contain the flags for __ulock_wait
#
# @const ULF_WAIT_WORKQ_DATA_CONTENTION
# The waiter is contending on this lock for synchronization around global data.
# This causes the workqueue subsystem to not create new threads to offset for
# waiters on this lock.
#
# @const ULF_WAIT_CANCEL_POINT
# This wait is a cancelation point
#
# @const ULF_WAIT_ADAPTIVE_SPIN
# Use adaptive spinning when the thread that currently holds the unfair lock
# is on core.
const ULF_WAIT_WORKQ_DATA_CONTENTION = 0x00010000
const ULF_WAIT_CANCEL_POINT          = 0x00020000
const ULF_WAIT_ADAPTIVE_SPIN         = 0x00040000

# operation bits [31, 24] contain the generic flags
const ULF_NO_ERRNO                   = 0x01000000

# masks
const UL_OPCODE_MASK                 = 0x000000FF
const UL_FLAGS_MASK                  = 0xFFFFFF00
const ULF_GENERIC_MASK               = 0xFFFF0000

const ULF_WAIT_MASK     = ULF_NO_ERRNO or
                          ULF_WAIT_WORKQ_DATA_CONTENTION or
                          ULF_WAIT_CANCEL_POINT or
                          ULF_WAIT_ADAPTIVE_SPIN

const ULF_WAKE_MASK     = ULF_NO_ERRNO or
                          ULF_WAKE_ALL or
                          ULF_WAKE_THREAD or
                          ULF_WAKE_ALLOW_NON_OWNER

proc ulock_wait(operation: uint32, address: pointer, expected: uint64, timeout: uint32): cint {.importc:"__ulock_wait", noconv.}
proc ulock_wait2(operation: uint32, address: pointer, expected: uint64, timeout, value2: uint64): cint {.importc:"__ulock_wait2", noconv.}
proc ulock_wake(operation: uint32, address: pointer, wake_value: uint64): cint {.importc:"__ulock_wake", noconv.}

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
  discard ulock_wait(UL_UNFAIR_LOCK64_SHARED or ULF_NO_ERRNO, futex.value.addr, uint64 expected, 0)

proc wake*(futex: var Futex) {.inline.} =
  ## Wake one thread (from the same process)
  discard ulock_wake(ULF_WAKE_THREAD or ULF_NO_ERRNO, futex.value.addr, 0)

proc wakeAll*(futex: var Futex) {.inline.} =
  ## Wake all threads (from the same process)
  discard ulock_wake(ULF_WAKE_ALL or ULF_NO_ERRNO, futex.value.addr, 0)