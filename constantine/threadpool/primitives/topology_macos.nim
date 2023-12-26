# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distribute

proc c_printf(fmt: cstring): cint {.sideeffect, importc: "printf", header: "<stdio.h>", varargs, discardable, tags:[WriteIOEffect].}
proc strerror(errnum: cint): cstring {.importc, header:"<string.h>", noconv.}
proc sysctlbyname(name: cstring, oldp: pointer, oldlenp: ptr csize_t, newp: pointer, newlen: csize_t): int {.importc, header:"<sys/sysctl.h>", noconv.}

var errno {.importc, header: "<errno.h>".}: cint

proc queryNumPhysicalCoresMacOS*(): cint {.inline.} =
  # Note:
  # - hw.physicalcpu     is the number of cores available in current power management mode
  # - hw.physicalcpu_max is the max number of cores available this boot.
  # i.e. if we may start compute from low power mode with few CPUs "available".

  var size = csize_t sizeof(result)

  let ko = sysctlbyname("hw.physicalcpu_max", result.addr, size.addr, nil, 0) != 0
  if ko:
    c_printf("[Constantine's Threadpool] sysctlbyname(\"hw.physicalcpu_max\") failure: %s\n", strerror(errno))
    result = -1
  elif result <= 0:
    c_printf("[Constantine's Threadpool] sysctlbyname(\"hw.physicalcpu_max\") invalid value: %d\n", result)
    result = -1

proc queryAvailableThreadsMacOS*(): cint {.inline.} =
  var size = csize_t sizeof(result)

  let ko = sysctlbyname("hw.availcpu", result.addr, size.addr, nil, 0) != 0
  if ko:
    c_printf("[Constantine's Threadpool] sysctlbyname(\"hw.availcpu\") failure: %s\n", strerror(errno))
    result = -1
  elif result <= 0:
    c_printf("[Constantine's Threadpool] sysctlbyname(\"hw.availcpu\") invalid value: %d\n", result)
    result = -1