# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

proc c_printf(fmt: cstring): cint {.sideeffect, importc: "printf", header: "<stdio.h>", varargs, discardable.}
func c_snprintf(dst: cstring, maxLen: csize_t, format: cstring): cint {.importc:"snprintf", header: "<stdio.h>", varargs.}
  ## dst is really a `var` parameter, but Nim var are lowered to pointer hence unsuitable here.
  ## Note: The "format" parameter and followup arguments MUST NOT be forgotten
  ##       to not be exposed to the "format string attacks"

func c_fscanf(f: File, format: cstring): cint{.importc:"fscanf", header: "<stdio.h>", varargs.}
  ## Note: The "format" parameter and followup arguments MUST NOT be forgotten
  ##       to not be exposed to the "format string attacks"

proc c_fopen(filename, mode: cstring): File {.importc: "fopen", header: "<stdio.h>".}
proc c_fclose(f: File): cint {.importc: "fclose", header: "<stdio.h>".}

proc queryNumPhysicalCoresLinux*(): cint =
  ## Detect the number of physical cores on Linux.
  ## This uses several syscalls to read from sysfs
  ## and might not be compatible with restrictions in trusted enclaves
  ## or hardened Linux installations (https://github.com/Kicksecure/security-misc/blob/master/usr/libexec/security-misc/hide-hardware-info)
  ##
  ## This can only handle up to 64 cores (logical or physical)
  ## CPU-based solutions using CPUID-like instructions should be preferred.
  {.warning: "queryNumPhysicalCoresLinux: Only up to 64 cores can be handled on Linux at the moment.".}
  result = 0

  var logiCoresBitField = culonglong 0
  var pathBuf: array[64, char]
  var path = cast[cstring](pathBuf[0].addr)

  var i = cint 0
  while true:
    if i == 64:
      c_printf("[Constantine's Threadpool] The Linux topology detection fallback only supports up to 64 cores (hardware or software)\n")
      return -1

    if ((logiCoresBitField shr i) and 1) != 0:
      # Core is already in the bitfield, it's an Simultaneous Multithreading siblings.
      i += 1
      continue

    let charsRead = c_snprintf(path, csize_t sizeof(pathBuf), "/sys/devices/system/cpu/cpu%u/topology/thread_siblings", i)
    if charsRead notin {0 .. pathBuf.len-1}:
      # Error if negative or overflow if charReads over pathBuf.len + '\n'
      return -1

    let f = c_fopen(path, "r")
    if f.isNil():
      # Core does not exist, we reached the end
      return result
    else:
      # We found a physical core
      result += 1


    var siblingsBitField = culonglong 0
    let numMatches = f.c_fscanf("%llx", siblingsBitField.addr)

    if numMatches != 1:
      c_printf("[Constantine's Threadpool] Error reading from '%s'\n", path)

    # Merge the siblings of current core with the all logicalCores
    logiCoresBitField = logiCoresBitField or siblingsBitField

    i += 1
    discard c_fclose(f)

proc queryAvailableThreadsLinux*(): cint {.inline.} =
  proc get_nprocs(): cint {.importc, sideeffect, header: "<sys/sysinfo.h>", noconv.}

  # TODO: we might want no dependency on glibc extensions for POSIX
  # See BZ #28865 for files:
  # - /sys/devices/system/cpu/online
  # - /proc/stat enumeration
  # - sched_getaffinity
  get_nprocs()