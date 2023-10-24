# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when defined(amd64): # TODO defined(i386) but it seems like RDTSC call is misconfigured
  from ../isa/cpuinfo_x86 import cpuName_x86

  const SupportsCPUName* = true
  const SupportsGetTicks* = true

  template cpuName*: untyped = cpuName_x86()

  # From Linux
  #
  # The RDTSC instruction is not ordered relative to memory
  # access.  The Intel SDM and the AMD APM are both vague on this
  # point, but empirically an RDTSC instruction can be
  # speculatively executed before prior loads.  An RDTSC
  # immediately after an appropriate barrier appears to be
  # ordered as a normal load, that is, it provides the same
  # ordering guarantees as reading from a global memory location
  # that some other imaginary CPU is updating continuously with a
  # time stamp.
  #
  # From Intel SDM
  # https://www.intel.com/content/dam/www/public/us/en/documents/white-papers/ia-32-ia-64-benchmark-code-execution-paper.pdf

  proc getTicks*(): int64 {.inline.} =
    when defined(vcc):
      proc rdtsc(): int64 {.sideeffect, importc: "__rdtsc", header: "<intrin.h>".}
      proc lfence() {.importc: "__mm_lfence", header: "<intrin.h>".}

      lfence()
      return rdtsc()

    else:
      when defined(amd64):
        var lo, hi: int64
        # TODO: Provide a compile-time flag for RDTSCP support
        #       and use it instead of lfence + RDTSC
        {.emit: """asm volatile(
          "lfence\n"
          "rdtsc\n"
          : "=a"(`lo`), "=d"(`hi`)
          :
          : "memory"
        );""".}
        return (hi shl 32) or lo
      else: # 32-bit x86
        # TODO: Provide a compile-time flag for RDTSCP support
        #       and use it instead of lfence + RDTSC
        {.emit: """asm volatile(
          "lfence\n"
          "rdtsc\n"
          : "=a"(`result`)
          :
          : "memory"
        );""".}

else:
  const SupportsCPUName* = false
  const SupportsGetTicks* = false

  # TODO cycle counting on ARM
  #
  # - see writeup: http://zhiyisun.github.io/2016/03/02/How-to-Use-Performance-Monitor-Unit-(PMU)-of-64-bit-ARMv8-A-in-Linux.html
  #
  # Otherwise Google or FFTW approach might work but might require perf_counter privilege (`kernel.perf_event_paranoid=0` ?)
  # - https://github.com/google/benchmark/blob/0ab2c290/src/cycleclock.h#L127-L151
  # - https://github.com/FFTW/fftw3/blob/ef15637f/kernel/cycle.h#L518-L564
  # - https://github.com/vesperix/FFTW-for-ARMv7/blob/22ec5c0b/kernel/cycle.h#L404-L457


# Prevent compiler optimizing benchmark away
# -----------------------------------------------
# This doesn't always work unfortunately ...

proc volatilize(x: ptr byte) {.codegenDecl: "$# $#(char const volatile *x)", inline.} =
  discard

template preventOptimAway*[T](x: var T) =
  volatilize(cast[ptr byte](unsafeAddr x))

template preventOptimAway*[T](x: T) =
  volatilize(cast[ptr byte](x))
