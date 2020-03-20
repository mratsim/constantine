# Cpu Name
# -------------------------------------------------------

{.passC:"-std=gnu99".} # TODO may conflict with milagro "-std=c99"

proc cpuID(eaxi, ecxi: int32): tuple[eax, ebx, ecx, edx: int32] =
  when defined(vcc):
    proc cpuidVcc(cpuInfo: ptr int32; functionID: int32)
      {.importc: "__cpuidex", header: "intrin.h".}
    cpuidVcc(addr result.eax, eaxi, ecxi)
  else:
    var (eaxr, ebxr, ecxr, edxr) = (0'i32, 0'i32, 0'i32, 0'i32)
    asm """
      cpuid
      :"=a"(`eaxr`), "=b"(`ebxr`), "=c"(`ecxr`), "=d"(`edxr`)
      :"a"(`eaxi`), "c"(`ecxi`)"""
    (eaxr, ebxr, ecxr, edxr)

proc cpuName*(): string =
  var leaves {.global.} = cast[array[48, char]]([
    cpuID(eaxi = 0x80000002'i32, ecxi = 0),
    cpuID(eaxi = 0x80000003'i32, ecxi = 0),
    cpuID(eaxi = 0x80000004'i32, ecxi = 0)])
  result = $cast[cstring](addr leaves[0])

# Counting cycles
# -------------------------------------------------------

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
