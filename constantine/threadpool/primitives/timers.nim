# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Timers
# ----------------------------------------------------------------------------------
#
# While for benchmarking we can enclose our microbenchmark target between clocks utilities
# for timing the inner part of complex code, the issue become the overhead introduced.
# In particular, since the kernel maintains the system time, syscall overhead.
# As shown in https://gms.tf/on-the-costs-of-syscalls.html
# something like clock_gettime_mono_raw can take from 20ns to 760ns.
# Furthermore real syscalls will pollute the cache, which isn't a problem
# when benchmarking steal code (since there is no work) but is when benchmarking loop splitting a tight loop.
#
# Ideally we would use the RDTSC instruction, it takes 5.5 cycles
#   https://www.intel.com/content/www/us/en/docs/intrinsics-guide/index.html#text=rdtsc&expand=5578&ig_expand=5803
#   https://www.intel.com/content/dam/www/public/us/en/documents/white-papers/ia-32-ia-64-benchmark-code-execution-paper.pdf
# and has a latency of 42 cycles (i.e. 2 RDTSCs back-to-back will take 42 cycles, preventing accurate measurement of something that costs less).
# But converting timestamp counter (TSC) to time is very tricky business, and would require a lot of code for accuracy
# - https://stackoverflow.com/a/42190816
# - https://github.com/torvalds/linux/blob/master/arch/x86/kernel/tsc.c
# - https://github.com/torvalds/linux/blob/master/tools/power/x86/turbostat/turbostat.c
# especially when even within the same CPU family you have quirks:
# - https://lore.kernel.org/lkml/ff6dcea166e8ff8f2f6a03c17beab2cb436aa779.1513920414.git.len.brown@intel.com/
#    "while SKX servers use a 25 MHz crystal, SKX workstations (with same model #) use a 24 MHz crystal.
#     This results in a -4.0% time drift rate on SKX workstations."
#    "While SKX servers do have a 25  MHz crystal, but they too have a problem.
#     All SKX subject the crystal to an EMI reduction circuit that
#     reduces its actual frequency by (approximately) -0.25%.
#     This results in -1 second per 10 minute time drift
#     as compared to network time."
#
# So with either use the monotonic clock, hoping it uses vDSO instead of a full syscall, so overhead is just ~20ns (60 cycles on 3GHz CPU)
# or we use RDTSC, getting the TSC frequency can be done by installing the `turbostat` package.
#
# We choose the monotonic clockfor portability and to not deal
# with TSC on x86 (and possibly other architectures). Due to this, timers aren't meaningful
# on scheduler overhead workloads like fibonacci or DFS as we would be measuring the clock.

type Ticks = distinct int64

when defined(linux):
  # https://github.com/torvalds/linux/blob/v6.2/include/uapi/linux/time.h
  type
    Timespec {.pure, final, importc: "struct timespec", header: "<time.h>".} = object
      tv_sec: clong   ## Seconds.
      tv_nsec: clong  ## Nanoseconds.

  const CLOCK_MONOTONIC = cint 1
  const SecondsInNanoseconds = 1_000_000_000

  proc clock_gettime(clockKind: cint, dst: var Timespec): cint {.sideeffect, discardable, importc, header: "<time.h>".}
    ## Returns the clock kind value in dst
    ## Returns 0 on success or -1 on failure

  proc getTicks(): Ticks {.inline.} =
    var ts {.noInit.}: Timespec
    clock_gettime(CLOCK_MONOTONIC, ts)
    return Ticks(ts.tv_sec.int64 * SecondsInNanoseconds + ts.tv_nsec.int64)

  func elapsedNs(start, stop: Ticks): int64 {.inline.} =
    ## Returns the elapsed time in nano-seconds from ticks
    stop.int64 - start.int64

elif defined(macosx):
  type
    MachTimebaseInfoData {.pure, final, importc: "mach_timebase_info_data_t", header: "<mach/mach_time.h>".} = object
      numer, denom: int32

  proc mach_absolute_time(): Ticks {.sideeffect, importc, header: "<mach/mach.h>".}
  proc mach_timebase_info(info: var MachTimebaseInfoData) {.importc, header: "<mach/mach_time.h>".}

  ## initialize MTI once at program startup
  var mti: MachTimebaseInfoData
  mach_timebase_info(mti)
  let mti_f64_num = float64(mti.numer)
  let mti_f64_den = float64(mti_denom)

  proc getTicks(): Ticks {.inline.} =
    ## On OSX, Ticks to nanoseconds is done via multiplying by MachTimeBasedInfo fraction
    return mach_absolute_time()

  proc elapsedNs(start, stop: Ticks): int64 {.inline.} =
    ## Returns the elapsed time in nano-seconds from ticks
    # Integer division is slow ~ 55 cycles at least.
    # Also division is imprecise but we don't really care about the error there
    # only the relative magnitude between various timers.
    # Otherwise we can use 128-bit precision or continued fractions: https://stackoverflow.com/questions/23378063/how-can-i-use-mach-absolute-time-without-overflowing
    int64(float64(stop.int64 - start.int64) * mti_f64_num / mti_f64_den)

elif defined(windows):
  proc QueryPerformanceCounter(res: var Ticks) {.importc: "QueryPerformanceCounter", stdcall, dynlib: "kernel32".}
  proc QueryPerformanceFrequency(res: var uint64) {.importc: "QueryPerformanceFrequency", stdcall, dynlib: "kernel32".}

  # initialize performance frequency once at startup
  # https://learn.microsoft.com/en-us/windows/win32/api/profileapi/nf-profileapi-queryperformancefrequency
  var perfFreq: uint64
  QueryPerformanceFrequency(perfFreq)
  let nsRatio = 1e9'f64 / float64(perfFreq)

  proc getTicks(): Ticks {.inline.} =
    QueryPerformanceCounter(result)

  proc elapsedNs(start, stop: Ticks): int64 {.inline.} =
    # Because 10⁹ is so large, multiplying by it first then dividing will accumulate a lot of FP errors
    int64(float64(stop.int64 - start.int64) * nsRatio)

else:
  {.error: "Timers are not implemented for this OS".}

type
  Timer* = object
    ## A timer, resolution in nanoseconds
    startTicks: Ticks
    elapsedNS: int64

  TimerUnit* = enum
    kMicroseconds
    kMilliseconds
    kSeconds

func reset*(timer: var Timer) {.inline.} =
  timer.startTicks = Ticks(0)
  timer.elapsedNS = 0

proc start*(timer: var Timer) {.inline.} =
  timer.startTicks = getTicks()

proc stop*(timer: var Timer) {.inline.} =
  let stop = getTicks()
  timer.elapsedNS += elapsedNs(timer.startTicks, stop)

func getElapsedTime*(timer: Timer, kind: TimerUnit): float64 {.inline.} =
  case kind
  of kMicroseconds:
    return timer.elapsedNS.float64 * 1e-3
  of kMilliseconds:
    return timer.elapsedNS.float64 * 1e-6
  of kSeconds:
    return timer.elapsedNS.float64 * 1e-9

func getElapsedCumulatedTime*(timers: varargs[Timer], kind: TimerUnit): float64 {.inline.} =
  for timer in timers:
    result += timer.getElapsedTime(kind)