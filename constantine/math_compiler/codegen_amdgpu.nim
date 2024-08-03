# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abis/amdgpu_abi {.all.},
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
