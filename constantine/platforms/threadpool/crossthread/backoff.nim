# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/atomics,
  ../primitives/futexes

{.push raises:[], checks:off.}

# ############################################################
#
#                      Eventcount
#
# ############################################################

type
  Eventcount* = object
    ## The lock-free equivalent of a condition variable.
    ##
    ## Usage, if a thread needs to be parked until a condition is true
    ##       and signaled by another thread:
    ## ```Nim
    ## if condition:
    ##   return
    ##
    ## while true:
    ##   ticket = ec.sleepy()
    ##   if condition:
    ##     ec.cancelSleep()
    ##     break
    ##   else:
    ##     ec.sleep()
    ## ```
    waitset: Atomic[uint32]
    # type waitset = object
    #   preSleep {.bitsize: 16.}: uint32
    #   committedSleep {.bitsize: 16.}: uint32
    #
    # We need precise committed sleep count for the `syncAll` barrier because a `preSleep` waiter
    # may steal a task and create more work.
    events: Futex

  ParkingTicket* = object
    epoch: uint32

const # bitfield setup
  #   Low 16 bits are waiters, up to 2¹⁶ = 65536 threads are supported
  #   Next 16 bits are pre-waiters, planning to wait but not committed.
  #
  # OS limitations:
  # - Windows 10 supports up to 256 cores (https://www.microsoft.com/en-us/microsoft-365/blog/2017/12/15/windows-10-pro-workstations-power-advanced-workloads/)
  # - Linux CPUSET supports up to 1024 threads (https://man7.org/linux/man-pages/man3/CPU_SET.3.html)
  #
  # Hardware limitations:
  # - Xeon Platinum 8490H, 60C/120T per socket
  #   - up to 8 sockets: 960 threads

  kPreWaitShift = 8'u32
  kPreWait      = 1'u32 shl kPreWaitShift
  kWait         = 1'u32
  kCommitToWait = kWait - kPreWait
  kWaitMask     = kPreWait-1
  kPreWaitMask  = not kWaitMask

func initialize*(ec: var EventCount) {.inline.} =
  ec.waitset.store(0, moRelaxed)
  ec.events.initialize()

func `=destroy`*(ec: var EventCount) {.inline.} =
  ec.events.teardown()

proc sleepy*(ec: var Eventcount): ParkingTicket {.noInit, inline.} =
  ## To be called before checking if the condition to not sleep is met.
  ## Returns a ticket to be used when committing to sleep
  discard ec.waitset.fetchAdd(kPreWait, moRelease)
  result.epoch = ec.events.load(moAcquire)

proc sleep*(ec: var Eventcount, ticket: ParkingTicket) {.inline.} =
  ## Put a thread to sleep until notified.
  ## If the ticket becomes invalid (a notification has been received)
  ## by the time sleep is called, the thread won't enter sleep
  discard ec.waitset.fetchAdd(kCommitToWait, moRelease)

  while ec.events.load(moAcquire) == ticket.epoch:
    ec.events.wait(ticket.epoch)

  discard ec.waitset.fetchSub(kWait, moRelease)

proc cancelSleep*(ec: var Eventcount) {.inline.} =
  ## Cancel a sleep that was scheduled.
  discard ec.waitset.fetchSub(kPreWait, moRelease)

proc wake*(ec: var EventCount) {.inline.} =
  ## Prevent an idle thread from sleeping
  ## or wait a sleeping one if there wasn't any idle
  discard ec.events.increment(1, moRelease)
  let waiters = ec.waitset.load(moAcquire)
  if (waiters and kPreWaitMask) != 0:
    # Some threads are in prewait and will see the event count change
    # no need to do an expensive syscall
    return
  if waiters != 0:
    ec.events.wake()

proc wakeAll*(ec: var EventCount) {.inline.} =
  ## Wake all threads if at least 1 is parked
  discard ec.events.increment(1, moRelease)
  let waiters = ec.waitset.load(moAcquire)
  if (waiters and kWaitMask) != 0:
    ec.events.wakeAll()

proc getNumWaiters*(ec: var EventCount): tuple[preSleep, committedSleep: int32] {.noInit, inline.} =
  ## Get the number of idle threads:
  ## (preSleep, committedSleep)
  let waiters = ec.waitset.load(moAcquire)
  result.preSleep = cast[int32]((waiters and kPreWaitMask) shr kPreWaitShift)
  result.committedSleep = cast[int32](waiters and kWaitMask)
