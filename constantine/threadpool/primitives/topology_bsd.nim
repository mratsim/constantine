# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Kernel API
# ---------------------------------------------------
# Many sysctl entries are given a dynamic ID (OID_AUTO)
# like kern.smp.cores on FreeBSD: https://github.com/freebsd/freebsd-src/blob/release/14.0.0/sys/kern/subr_smp.c#L107-L109
# or hw.physicalcpu_max on MacOS (no source)
# while others are not available through sysctlbyname
# like hw.availcpu on MacOS
proc sysctl(mib: openArray[cint], oldp: pointer, oldlenp: var csize_t, newp: openArray[byte]): cint {.sideeffect, importc, header:"<sys/sysctl.h>", noconv.}
proc sysctlbyname(name: cstring, oldp: pointer, oldlenp: var csize_t, newp: openArray[byte]): cint {.sideeffect, importc, header:"<sys/sysctl.h>", noconv.}

# Error handling
# ---------------------------------------------------
proc c_printf(fmt: cstring): cint {.sideeffect, importc: "printf", header: "<stdio.h>", varargs, discardable, tags:[WriteIOEffect].}
proc strerror(errnum: cint): cstring {.importc, header:"<string.h>", noconv.}
var errno {.importc, header: "<errno.h>".}: cint

# Topology queries
# ---------------------------------------------------
template queryBsdKernel(arg: untyped): cint =
  block:
    var r: cint
    var size = csize_t sizeof(r)
    when arg is string:
      const argDesc = arg
      let ko = sysctlbyname(arg, r.addr, size, []) != 0
    else:
      const argDesc = astToStr(arg)
      let ko = sysctl(arg, r.addr, size, []) != 0

    if ko:
      c_printf("[Constantine's Threadpool] sysctl(\"%s\") failure: %s\n", argDesc, strerror(errno))
      r = -1
    elif r <= 0:
      c_printf("[Constantine's Threadpool] sysctl(\"%s\") invalid value: %d\n", argDesc, r)
      r = -1
    r

proc queryNumPhysicalCoresFreeBSD*(): cint {.inline.} =
  queryBsdKernel"kern.smp.cores"

proc queryNumPhysicalCoresMacOS*(): cint {.inline.} =
  # Note:
  # - hw.physicalcpu     is the number of cores available in current power management mode
  # - hw.physicalcpu_max is the max number of cores available this boot.
  # i.e. if we may start compute from low power mode with few CPUs "available".
  queryBsdKernel"hw.physicalcpu_max"

when defined(ios) or defined(macos) or defined(macosx):
  let CTL_HW {.importc, header:"<sys/sysctl.h>".}: cint
  let HW_AVAILCPU {.importc, header:"<sys/sysctl.h>".}: cint
elif defined(freebsd):
  discard
elif defined(netbsd) or defined(openbsd):
  let CTL_HW {.importc, header:"<sys/sysctl.h>".}: cint
  let HW_NCPUONLINE {.importc, header:"<sys/sysctl.h>".}: cint
else:
  let SC_NPROCESSORS_ONLN {.importc: "_SC_NPROCESSORS_ONLN", header: "<unistd.h>".}: cint
  proc sysconf(name: cint): cint {.importc, header: "<unistd.h>", noconv.}

proc queryAvailableThreadsBSD*(): cint {.inline.} =
  when defined(ios) or defined(macos) or defined(macosx):
    queryBsdKernel([CTL_HW, HW_AVAILCPU])
  elif defined(freebsd):
    # For some reason, sysconf(SC_NPROCESSORS_ONLN) uses HW_NCPUS
    # - https://github.com/freebsd/freebsd-src/blob/release/14.0.0/lib/libc/gen/sysconf.c#L583-L589
    # instead of its builtin CPU online facility:
    # - https://github.com/freebsd/freebsd-src/blob/release/14.0.0/sys/kern/subr_smp.c#L99-L101
    queryBsdKernel"kern.smp.cpus"
  elif defined(netbsd) or defined(openbsd):
    # - OpenBSD and NetBSD have HW_NCPUONLINE
    #   https://github.com/openbsd/src/blob/master/lib/libc/gen/sysconf.c#L467-L470
    #   https://github.com/NetBSD/src/blob/trunk/lib/libc/gen/sysconf.c#L372-L375
    queryBsdKernel([CTL_HW, HW_NCPUONLINE])
  else: # libc dependency and more recent BSDs required
    sysconf(SC_NPROCESSORS_ONLN)
