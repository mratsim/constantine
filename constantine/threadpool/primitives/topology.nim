# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#                                                            #
#                     CPU Topology                           #
#                                                            #
# ############################################################

# This module is a replacement of std/cpuinfo. It addresses the following limitations:
# - stringent runtime dependency constraints: https://github.com/mratsim/constantine/issues/291
# - countProcessors() is part of Nim RTL (runtime library) which is not really needed
# - it returns the number of logical cores but HyperThreading is not beneficial when
#   2 sibling cores are competing for rare resources:
#   - memory bandwidth to load elliptic curve points, they evict each other data from cache.
#   - execution ports, MULX, ADOX, ADCX have only few ports and a single logical core uses all

# We distinguish the following layers of CPU topology:
# - Sockets / NUMA Domain
# - Hybrid / Heterogenous Core types
# - Physical Cores
# - Logical Cores
#
# We're interested in exposing the number of physical cores:
# - Dealing with socket affinity of core affinity is very complex,
#   it is workload dependent, probably worth it only on HPC supercomputers.
# - Heterogenous arch like Big.Little on ARM or Performance/Efficiency core on x86
#   made that nigh impossible, and the hardware "Thread Director" has its own agenda.
# - Some OSes just don't expose affinity controls.
# - We assume the OS does the right thing™ regarding scheduling
#    depending on overall load and power limitations.
#
# Regarding logical cores, our computational workload is bottlenecked
# by execution ports and memory bandwidth
# and so does not benefit from Simultaneous Multi-Threading.

# Documentation:
# - x86 Intel:       https://software.intel.com/content/www/us/en/develop/articles/intel-64-architecture-processor-topology-enumeration.html
# - x86 AMD & Intel: https://wiki.osdev.org/Detecting_CPU_Topology_(80x86)
# - Alder Lake:      https://www.intel.com/content/www/us/en/developer/articles/guide/12th-gen-intel-core-processor-gamedev-guide.html
#                    https://github.com/GameTechDev/HybridDetect
# - Windows:         https://devblogs.microsoft.com/oldnewthing/20131028-00/?p=2823
# - Linux:           https://www.kernel.org/doc/Documentation/admin-guide/cputopology.rst
#                    https://lkml.org/lkml/2019/2/26/41
#
# Design considerations
#   MacOS, FreeBSD, Windows provide the number of physical cores through their kernel API.
#   Other OS including Linux, BSDs, Solaris do not.
#
#   On Linux, we avoid reading from /proc/cpuinfo
#   - AFAIK the ouptput can vary a lot depending on topology
#     So a parser needs to make several assumptions and attract edge cases.
#   - They also need file descriptors / syscalls
#     which are painful to support (if not unsupported) in trusted enclaves like SGX
#   - Hardened Linux installation might restrict reading from /proc/cpuinfo or sysfs.
#     https://github.com/Kicksecure/security-misc/blob/master/usr/libexec/security-misc/hide-hardware-info
#
#   For non-x86 (i.e. enclave support is not in scope), reading sysfs is a more stable option.
#
#   We also offer a proc to also read from CPUSETs if a program as been restricted to
#   a certain amount of cores.
#   It's unsure how to deal with docker and Kubernetes quotas.
#
#   As a compute library, we assume that by default the full hardware should be used.
#   Furthermore, predictability helps misuse resistance.
#
#   It's also recommended that applications supply a MYAPP_NUM_THREADS env variable to control
#   the threadpool.

# Naming:
# - "query" when going through the OS
# - "detect" when going through the CPU

import ../../zoo_exports

when defined(bsd) or defined(ios) or defined(macos) or defined(macosx):
  import ./topology_bsd
elif defined(windows):
  # The following can handle Windows x86 and Windows ARM
  import ./topology_windows
elif defined(linux):
  import ./topology_linux
else:
  {.error: "Unsupported OS: " & hostOS.}

# TODO: x86 OS-independent reads
# if defined(amd64) or defined(i386):
#   import ./topology_x86

proc getNumCoresPhysical*(): cint =
  when defined(ios) or defined(macos) or defined(macosx):
    queryNumPhysicalCoresMacOS()
  elif defined(freebsd):
    queryNumPhysicalCoresFreeBSD()
  elif defined(windows):
    queryNumPhysicalCoresWindows()

  # TODO
  # elif defined(amd64) or defined(i386):

  elif defined(linux):
    queryNumPhysicalCoresLinux()

  else:
    {.error: "Unsupported CPU/OS configuration: " & hostCPU & "/" & hostOS.}

proc getNumThreadsOS*(): cint {.libExport:"ctt_cpu_get_num_threads_os".} =
  ## Query the number of threads available at the OS-level
  ## to run computations.
  ##
  ## This takes into account cores disabled at the OS-level, for example in a VM.
  ## However this doesn't detect restrictions based on time quotas often used for Docker
  ## or taskset / cpuset restrictions from cgroups.
  ##
  ## For Simultaneous-Multithreading (SMT often call HyperThreading),
  ## this returns the number of available logical cores.

  when defined(bsd) or defined(ios) or defined(macos) or defined(macosx):
    queryAvailableThreadsBSD()
  elif defined(windows):
    queryAvailableThreadsWindows()
  elif defined(linux):
    queryAvailableThreadsLinux()
  else:
    {.error: "Unsupported CPU/OS configuration: " & hostCPU & "/" & hostOS.}