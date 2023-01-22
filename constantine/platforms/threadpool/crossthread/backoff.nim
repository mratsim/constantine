# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/atomics,
  ../primitives/futex

# We implement 2 datastructures to put threads to sleep:
# 1. An event notifier to put an awaiting thread to sleep when the task they require is worked on by another thread
# 2. An eventcount to put an idle thread to sleep

{.push raises:[], checks:off.}

# ############################################################
#
#                      Event Notifier
#
# ############################################################

# Formal verification at: https://github.com/mratsim/weave/blob/7682784/formal_verification/event_notifiers.tla#L76-L109

type
  EventNotifier* = object
    ## Multi Producers, Single Consumer event notification
    ## This is can be seen as a wait-free condition variable for producers
    ## that avoids them spending time in expensive kernel land due to mutexes.
    # ---- Consumer specific ----
    ticket{.align: 64.}: uint8  # A ticket for the consumer to sleep in a phase
    # ---- Contention ---- no real need for padding as cache line should be reloaded in case of contention anyway
    futex: Futex                # A Futex (atomic int32 that can put thread to sleep)
    phase: Atomic[uint8]        # A binary timestamp, toggles between 0 and 1 (but there is no atomic "not")
    signaled: Atomic[bool]      # Signaling condition

func initialize*(en: var EventNotifier) {.inline.} =
  en.futex.initialize()
  en.ticket = 0
  en.phase.store(0, moRelaxed)
  en.signaled.store(false, moRelaxed)

func `=destroy`*(en: var EventNotifier) {.inline.} =
  en.futex.teardown()

func `=`*(dst: var EventNotifier, src: EventNotifier) {.error: "An event notifier cannot be copied".}
func `=sink`*(dst: var EventNotifier, src: EventNotifier) {.error: "An event notifier cannot be moved".}

func prepareToPark*(en: var EventNotifier) {.inline.} =
  ## The consumer intends to sleep soon.
  ## This must be called before the formal notification
  ## via a channel.
  if not en.signaled.load(moRelaxed):
    en.ticket = en.phase.load(moRelaxed)

proc park*(en: var EventNotifier) {.inline.} =
  ## Wait until we are signaled of an event
  ## Thread is parked and does not consume CPU resources
  ## This may wakeup spuriously.
  if not en.signaled.load(moRelaxed):
    if en.ticket == en.phase.load(moRelaxed):
      en.futex.wait(0)
  en.signaled.store(false, moRelaxed)
  en.futex.initialize()

proc notify*(en: var EventNotifier) {.inline.} =
  ## Signal a thread that it can be unparked

  if en.signaled.load(moRelaxed):
    # Another producer is signaling
    return
  en.signaled.store(true, moRelease)
  discard en.phase.fetchXor(1, moRelaxed)
  en.futex.store(1, moRelease)
  en.futex.wake()

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

    state: Atomic[uint32]
    # State is actually the equivalent of a bitfield
    # type State = object
    #   waiters {.bitsize: 16.}: uint16
    #   when sizeof(pointer) == 4:
    #     epoch {.bitsize: 16.}: uint16
    #   else:
    #     epoch {.bitsize: 48.}: uint48
    #
    # of size, the native integer size
    # and so can be used for atomic operations on 32-bit or 64-bit platforms.
    # but there is no native fetchAdd for bitfield
    futex: Futex
    # Technically we could use the futex as the state.
    # When you wait on a Futex, it waits only if the value of the futex
    # matches with a reference value.
    # But our reference value will be the epoch of notifications
    # and it is non-trivial to zero-out the waiters bits.
    # - One way could be to split a 64-bit number in 2
    #   and cast the epoch part to Futex but that would only work on 64-bit CPU.
    # - Another more hacky way would be to pad with a zero-out uint16 before and after the Futex
    #   and depending on big or little endian provide a shifted address as Futex.

  ParkingTicket* = object
    epoch: uint32

const # bitfield
  # Low 16 bits are waiters, up to 2¹⁶ = 65536 threads are supported
  # High 16 or 48 bits are epochs.
  # We can deal with the ABA problem o:
  # - up to 65536 wake requests on 32-bit
  # - up to 281 474 976 710 656 wake requests on 64-bit
  # Epoch rolling over to 0 are not a problem, they won't change the low 16 bits
  kEpochShift = 16
  kAddEpoch = 1 shl kEpochShift
  kWaiterMask = kAddEpoch - 1
  kEpochMask {.used.} = not kWaiterMask
  kAddWaiter = 1
  kSubWaiter = 1

func initialize*(ec: var EventCount) {.inline.} =
  ec.state.store(0, moRelaxed)
  ec.futex.initialize()

func `=destroy`*(ec: var EventCount) {.inline.} =
  ec.futex.teardown()

proc sleepy*(ec: var Eventcount): ParkingTicket {.inline.} =
  ## To be called before checking if the condition to not sleep is met.
  ## Returns a ticket to be used when committing to sleep
  let prevState = ec.state.fetchAdd(kAddWaiter, moAcquireRelease)
  result.epoch = prevState shr kEpochShift

proc sleep*(ec: var Eventcount, ticket: ParkingTicket) {.inline.} =
  ## Put a thread to sleep until notified.
  ## If the ticket becomes invalid (a notfication has been received)
  ## by the time sleep is called, the thread won't enter sleep
  while ec.state.load(moAcquire) shr kEpochShift == ticket.epoch:
    ec.futex.wait(ticket.epoch) # We don't use the futex internal value

  let prev {.used.} = ec.state.fetchSub(kSubWaiter, moRelaxed)

proc cancelSleep*(ec: var Eventcount) {.inline.} =
  ## Cancel a sleep that was scheduled.
  let prev {.used.} = ec.state.fetchSub(kSubWaiter, moRelaxed)

proc wake*(ec: var EventCount) {.inline.} =
  ## Wake a thread if at least 1 is parked
  let prev = ec.state.fetchAdd(kAddEpoch, moAcquireRelease)
  if (prev and kWaiterMask) != 0:
    ec.futex.wake()

proc wakeAll*(ec: var EventCount) {.inline.} =
  ## Wake all threads if at least 1 is parked
  let prev = ec.state.fetchAdd(kAddEpoch, moAcquireRelease)
  if (prev and kWaiterMask) != 0:
    ec.futex.wakeAll()

proc getNumWaiters*(ec: var EventCount): uint32 {.inline.} =
  ## Get the number of parked threads
  ec.state.load(moRelaxed) and kWaiterMask

{.pop.} # {.push raises:[], checks:off.}