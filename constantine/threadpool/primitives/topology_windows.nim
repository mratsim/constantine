# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

const ANYSIZE_ARRAY = 1

type
  WinBool = int32
    ## WinBool uses opposite convention as posix, != 0 meaning success.

  KAFFINITY = csize_t

  PROCESSOR_CACHE_TYPE = enum
    CacheUnified, CacheInstruction, CacheData, CacheTrace

  LOGICAL_PROCESSOR_RELATIONSHIP = enum
    RelationProcessorCore, RelationNumaNode, RelationCache,
    RelationProcessorPackage, RelationGroup, RelationProcessorDie,
    RelationNumaNodeEx, RelationProcessorModule, RelationAll = 0xffff

  INNER_C_UNION_logical_relationship_22 {.bycopy, union.} = object
    Processor: PROCESSOR_RELATIONSHIP
    NumaNode: NUMA_NODE_RELATIONSHIP
    Cache: CACHE_RELATIONSHIP
    Group: GROUP_RELATIONSHIP

  INNER_C_UNION_logical_relationship_32 {.bycopy, union.} = object
    GroupMask: GROUP_AFFINITY
    GroupMasks: array[ANYSIZE_ARRAY, GROUP_AFFINITY]

  INNER_C_UNION_logical_relationship_54 {.bycopy, union.} = object
    GroupMask: GROUP_AFFINITY
    GroupMasks: array[ANYSIZE_ARRAY, GROUP_AFFINITY]

  PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX = ptr SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX
  SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX {.bycopy.} = object
    Relationship: LOGICAL_PROCESSOR_RELATIONSHIP
    Size: int32
    DUMMYUNIONNAME: INNER_C_UNION_logical_relationship_22

  NUMA_NODE_RELATIONSHIP {.bycopy.} = object
    NodeNumber: int32
    Reserved: array[18, byte]
    GroupCount: int16
    DUMMYUNIONNAME: INNER_C_UNION_logical_relationship_32

  PROCESSOR_RELATIONSHIP {.bycopy.} = object
    Flags: byte
    EfficiencyClass: byte
    Reserved: array[20, byte]
    GroupCount: int16
    GroupMask: array[ANYSIZE_ARRAY, GROUP_AFFINITY]

  CACHE_RELATIONSHIP {.bycopy.} = object
    Level: byte
    Associativity: byte
    LineSize: int16
    CacheSize: int32
    Type: PROCESSOR_CACHE_TYPE
    Reserved: array[18, byte]
    GroupCount: int16
    DUMMYUNIONNAME: INNER_C_UNION_logical_relationship_54

  GROUP_AFFINITY {.bycopy.} = object
    Mask: KAFFINITY
    Group: int16
    Reserved: array[3, int16]

  GROUP_RELATIONSHIP {.bycopy.} = object
    MaximumGroupCount: int16
    ActiveGroupCount: int16
    Reserved: array[20, byte]
    GroupInfo: array[ANYSIZE_ARRAY, PROCESSOR_GROUP_INFO]

  PROCESSOR_GROUP_INFO {.bycopy.} = object
    MaximumProcessorCount: byte
    ActiveProcessorCount: byte
    Reserved: array[38, byte]
    ActiveProcessorMask: KAFFINITY

# --------------------------------------------------------------------------------------------

proc c_printf(fmt: cstring): cint {.sideeffect, importc: "printf", header: "<stdio.h>", varargs, discardable, tags:[WriteIOEffect].}
proc alloca(size: int): pointer {.header: "<malloc.h>".}
proc GetLogicalProcessorInformationEx(
        rel: LOGICAL_PROCESSOR_RELATIONSHIP,
        dst: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX,
        dstLen: var int32): WinBool {.importc, stdcall, dynlib: "kernel32".}
proc getLastError(): int32 {.importc: "GetLastError", stdcall, dynlib: "kernel32", sideEffect.}

let ERROR_INSUFFICIENT_BUFFER {.importc, header: "<windows.h>".}: int32

func `+%>`(p: ptr or pointer, offset: SomeInteger): type(p) {.inline, noInit.}=
  ## Pointer increment by `offset` *bytes* (not elements)
  cast[typeof(p)](cast[ByteAddress](p) +% offset)

proc queryNumPhysicalCoresWindows*(): int32 {.inline.} =

  result = 1
  var info: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX
  var size: int32

  if GetLogicalProcessorInformationEx(RelationAll, info, size) == 0:
    let lastError = getLastError()
    if lastError == ERROR_INSUFFICIENT_BUFFER:
      info = cast[typeof info](alloca(int size))
    else:
      c_printf("[Constantine's Threadpool] GetLogicalProcessorInformationEx failure: %d. Cannot query size of CPU information.\n", last_error)
      result = -1
      return

  if GetLogicalProcessorInformationEx(RelationAll, info, size) == 0:
    let lastError = getLastError()
    c_printf("[Constantine's Threadpool] GetLogicalProcessorInformationEx failure: %d. Cannot retrieve CPU information.\n", last_error)
    result = -1
    return

  var count = 0'i32
  var offset = 0
  while offset < size:
    let pInfo = info +%> offset
    if pInfo.Relationship == RelationProcessorCore:
      count += 1
    offset += pInfo.Size

  if count != 0:
    result = count
  else:
    c_printf("[Constantine's Threadpool] Found 0 physical cores)")
    result = -1

# --------------------------------------------------------------------------------------------

type
  SystemInfo = object
    u1: uint32
    dwPageSize: uint32
    lpMinimumApplicationAddress: pointer
    lpMaximumApplicationAddress: pointer
    dwActiveProcessorMask: ptr uint32
    dwNumberOfProcessors: uint32
    dwProcessorType: uint32
    dwAllocationGranularity: uint32
    wProcessorLevel: uint16
    wProcessorRevision: uint16

proc getSystemInfo(lpSystemInfo: var SystemInfo) {.stdcall, sideeffect, dynlib: "kernel32", importc: "GetSystemInfo".}

proc queryAvailableThreadsWindows*(): cint {.inline.} =
  var sysinfo: SystemInfo
  sysinfo.getSystemInfo()
  return cast[cint](sysinfo.dwNumberOfProcessors)