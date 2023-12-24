# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

proc c_printf(fmt: cstring): cint {.sideeffect, importc: "printf", header: "<stdio.h>", varargs, discardable, tags:[WriteIOEffect].}
proc strerror(errnum: cint): cstring {.importc, header:"<string.h>", noconv.}
proc sysctlbyname(name: cstring, oldp: pointer, oldlenp: ptr csize_t, newp: pointer, newlen: csize_t): int {.importc, header:"<sys/sysctl.h>", noconv.}

var errno {.importc, header: "<errno.h>".}: cint

proc detectNumPhysicalCoresFreeBSD*(): int32 =

  var size = csize_t sizeof(result)

  let ko = sysctlbyname("kern.smp.cores", result.addr, size.addr, nil, 0) != 0
  if ko:
    c_printf("[Constantine's Threadpool] sysctlbyname(\"kern.smp.cores\") failure: %s\n", strerror(errno))
    result = -1
  elif result <= 0:
    c_printf("[Constantine's Threadpool] sysctlbyname(\"kern.smp.cores\") invalid value: %d\n", result)
    result = -1
