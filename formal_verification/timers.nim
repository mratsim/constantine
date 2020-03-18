when defined(i386) or defined(amd64):
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
  when not defined(vcc):
    when defined(amd64):
      proc getTicks*(): int64 {.inline.} =
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
    else:
      proc getTicks*(): int64 {.inline.} =
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
    proc rdtsc(): int64 {.sideeffect, importc: "__rdtsc", header: "<intrin.h>".}
    proc lfence() {.importc: "__mm_lfence", header: "<intrin.h>".}

    proc getTicks*(): int64 {.inline.} =
      lfence()
      return rdtsc()
else:
  {.error: "getticks is not supported on this CPU architecture".}
