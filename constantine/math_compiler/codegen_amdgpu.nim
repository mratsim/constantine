# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abis/amdgpu_abi {.all.},
  constantine/platforms/abis/amdcomgr_abi,
  constantine/platforms/abis/c_abi,
  constantine/platforms/llvm/llvm,
  constantine/platforms/primitives,
  ./ir

export
  amdgpu_abi,
  Flag, flag, wrapOpenArrayLenType

# ############################################################
#
#                     AMD GPUs API
#
# ############################################################

# Hip Runtime API
# ------------------------------------------------------------

template check*(status: HipError) =
  ## Check the status code of a Hip operation
  ## Exit program with error if failure

  let code = status # ensure that the input expression is evaluated once only
  if code != hipSuccess:
    writeStackTrace()
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    quit 1

func hipModuleGetFunction*(kernel: var HipFunction, module: HipModule, fnName: openArray[char]): HipError {.inline.}=
  hipModuleGetFunction(kernel, module, fnName[0].unsafeAddr)

proc getGcnArchName*(deviceID: int32): string =
  var prop: HipDeviceProp
  check hipGetDeviceProperties(prop, deviceID)

  for c in prop.gcnArchName:
    if c != '\0':
      result.add c

proc hipDeviceInit*(deviceID = 0'i32): HipDevice =

  check hipInit(deviceID.uint32)

  var devCount: int32
  check hipGetDeviceCount(devCount)
  if devCount == 0:
    echo "hipDeviceInit error: no devices supporting AMD ROCm/HIP"
    quit 1

  var hipDevice: HipDevice
  check hipDeviceGet(hipDevice, deviceID)
  var name = newString(128)
  check hipDeviceGetName(name[0].addr, name.len.int32, hipDevice)
  echo "Using HIP Device [", deviceID, "]: ", cstring(name)
  echo "AMD GCN ARCH: ", deviceID.getGcnArchName()

  return hipDevice

# ############################################################
#
#                      Code generation
#
# ############################################################

template check*(status: ComgrStatus) =
  ## Check the status code of a Comgr operation
  ## Exit program with error if failure

  let code = status # ensure that the input expression is evaluated once only
  if code != AMD_COMGR_STATUS_SUCCESS:
    writeStackTrace()
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    quit 1


proc linkAmdGpu*(reloc_obj: seq[byte], gcnArchName: string): seq[byte] {.noInline.} =
  ## Link a relocatable object code
  ## into an executable that can be used through hipModuleLoadData
  var roc: ComgrData
  check amd_comgr_create_data(AMD_COMGR_DATA_KIND_RELOCATABLE, roc)
  defer: check amd_comgr_release_data(roc)

  var ai: ComgrActionInfo
  check amd_comgr_create_action_info(ai)
  defer: check amd_comgr_destroy_action_info(ai)

  var ds: ComgrDataset
  check amd_comgr_create_data_set(ds)
  defer: check amd_comgr_destroy_data_set(ds)

  var dsOut: ComgrDataset
  check amd_comgr_create_data_set(dsOut)
  defer: check amd_comgr_destroy_data_set(dsOut)

  check roc.amd_comgr_set_data(reloc_obj.len.csize_t(), reloc_obj[0].addr)
  check roc.amd_comgr_set_data_name("linkAmdGpu-input.o")
  check ds.amd_comgr_data_set_add(roc)

  check ai.amd_comgr_action_info_set_isa_name(
    cstring("amdgcn-amd-amdhsa--" & gcnArchName)
  )

  check amd_comgr_do_action(
    AMD_COMGR_ACTION_LINK_RELOCATABLE_TO_EXECUTABLE,
    info = ai,
    input = ds,
    output = dsOut)

  # Extract the executable
  # ------------------------------------------------

  var exe: ComgrData
  check amd_comgr_create_data(AMD_COMGR_DATA_KIND_EXECUTABLE, exe)
  defer: check amd_comgr_release_data(exe)

  check amd_comgr_action_data_get_data(
    dsOut, AMD_COMGR_DATA_KIND_EXECUTABLE,
    index = 0, exe)

  # Query the required buffer size
  var size: csize_t
  check amd_comgr_get_data(
    exe, size, nil)

  # Size includes nul char
  # But we use seq[byte] not a string, so Nim doesn't auto-inster a \0
  # Hence allocation size is exact.
  result.setLen(int size)

  check amd_comgr_get_data(
    exe, size, result[0].addr)


# ############################################################
#
#                      Code execution
#
# ############################################################
