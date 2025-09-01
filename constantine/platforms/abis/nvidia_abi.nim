# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#               Bindings to Nvidia GPUs libraries
#
# ############################################################

import ./c_abi

# ############################################################
#
#                         Cuda
#
# ############################################################

const libCuda = "(libcuda.so|cuda.lib)" # Windows uses static linking for Cuda programs

# Cuda offers 2 APIs:
# - cuda.h               the driver API
# - cuda_runtime.h       the runtime API
#
# https://docs.nvidia.com/cuda/cuda-runtime-api/driver-vs-runtime-api.html
#
# We need to use the lower-level driver API for JIT modules loading and reloading


## Sigh. Due to the `incompatible-pointer-types` now standard in GCC / Clang, we need to
## define a real `const char*` type for e.g. `cuGetErrorString`. Otherwise we get errors.
type
  cstringConstImpl* {.importc: "const char*".} = cstring
  constChar* = distinct cstringConstImpl


type
  CUresult* {.size: sizeof(cint).} = enum
    ##  The API call returned with no errors. In the case of query calls, this
    ##  also means that the operation being queried is complete (see
    ##  ::cuEventQuery() and ::cuStreamQuery()).
    CUDA_SUCCESS = 0
    ##  This indicates that one or more of the parameters passed to the API call
    ##  is not within an acceptable range of values.
    CUDA_ERROR_INVALID_VALUE = 1
    ##  The API call failed because it was unable to allocate enough memory to
    ##  perform the requested operation.
    CUDA_ERROR_OUT_OF_MEMORY = 2
    ##  This indicates that the CUDA driver has not been initialized with
    ##  ::cuInit() or that initialization has failed.
    CUDA_ERROR_NOT_INITIALIZED = 3
    ##  This indicates that the CUDA driver is in the process of shutting down.
    CUDA_ERROR_DEINITIALIZED = 4
    ##  This indicates profiler is not initialized for this run. This can
    ##  happen when the application is running with external profiling tools
    ##  like visual profiler.
    CUDA_ERROR_PROFILER_DISABLED = 5
    ##  to attempt to enable/disable the profiling via ::cuProfilerStart or
    ##  ::cuProfilerStop without initialization.
    CUDA_ERROR_PROFILER_NOT_INITIALIZED = 6
    ##  to call cuProfilerStart() when profiling is already enabled.
    CUDA_ERROR_PROFILER_ALREADY_STARTED = 7
    ##  to call cuProfilerStop() when profiling is already disabled.
    CUDA_ERROR_PROFILER_ALREADY_STOPPED = 8
    ##  This indicates that the CUDA driver that the application has loaded is a
    ##  stub library. Applications that run with the stub rather than a real
    ##  driver loaded will result in CUDA API returning this error.
    CUDA_ERROR_STUB_LIBRARY = 34
    ##  This indicates that requested CUDA device is unavailable at the current
    ##  time. Devices are often unavailable due to use of
    ##  ::CU_COMPUTEMODE_EXCLUSIVE_PROCESS or ::CU_COMPUTEMODE_PROHIBITED.
    CUDA_ERROR_DEVICE_UNAVAILABLE = 46
    ##  This indicates that no CUDA-capable devices were detected by the installed
    ##  CUDA driver.
    CUDA_ERROR_NO_DEVICE = 100
    ##  This indicates that the device ordinal supplied by the user does not
    ##  correspond to a valid CUDA device or that the action requested is
    ##  invalid for the specified device.
    CUDA_ERROR_INVALID_DEVICE = 101
    ##  This error indicates that the Grid license is not applied.
    CUDA_ERROR_DEVICE_NOT_LICENSED = 102
    ##  This indicates that the device kernel image is invalid. This can also
    ##  indicate an invalid CUDA module.
    CUDA_ERROR_INVALID_IMAGE = 200
    ##  This most frequently indicates that there is no context bound to the
    ##  current thread. This can also be returned if the context passed to an
    ##  API call is not a valid handle (such as a context that has had
    ##  ::cuCtxDestroy() invoked on it). This can also be returned if a user
    ##  mixes different API versions (i.e. 3010 context with 3020 API calls).
    ##  See ::cuCtxGetApiVersion() for more details.
    CUDA_ERROR_INVALID_CONTEXT = 201
    ##  This indicated that the context being supplied as a parameter to the
    ##  API call was already the active context.
    ##  error to attempt to push the active context via ::cuCtxPushCurrent().
    CUDA_ERROR_CONTEXT_ALREADY_CURRENT = 202
    ##  This indicates that a map or register operation has failed.
    CUDA_ERROR_MAP_FAILED = 205
    ##  This indicates that an unmap or unregister operation has failed.
    CUDA_ERROR_UNMAP_FAILED = 206
    ##  This indicates that the specified array is currently mapped and thus
    ##  cannot be destroyed.
    CUDA_ERROR_ARRAY_IS_MAPPED = 207
    ##  This indicates that the resource is already mapped.
    CUDA_ERROR_ALREADY_MAPPED = 208
    ##  This indicates that there is no kernel image available that is suitable
    ##  for the device. This can occur when a user specifies code generation
    ##  options for a particular CUDA source file that do not include the
    ##  corresponding device configuration.
    CUDA_ERROR_NO_BINARY_FOR_GPU = 209
    ##  This indicates that a resource has already been acquired.
    CUDA_ERROR_ALREADY_ACQUIRED = 210
    ##  This indicates that a resource is not mapped.
    CUDA_ERROR_NOT_MAPPED = 211
    ##  This indicates that a mapped resource is not available for access as an
    ##  array.
    CUDA_ERROR_NOT_MAPPED_AS_ARRAY = 212
    ##  This indicates that a mapped resource is not available for access as a
    ##  pointer.
    CUDA_ERROR_NOT_MAPPED_AS_POINTER = 213
    ##  This indicates that an uncorrectable ECC error was detected during
    ##  execution.
    CUDA_ERROR_ECC_UNCORRECTABLE = 214
    ##  This indicates that the ::CUlimit passed to the API call is not
    ##  supported by the active device.
    CUDA_ERROR_UNSUPPORTED_LIMIT = 215
    ##  This indicates that the ::CUcontext passed to the API call can
    ##  only be bound to a single CPU thread at a time but is already
    ##  bound to a CPU thread.
    CUDA_ERROR_CONTEXT_ALREADY_IN_USE = 216
    ##  This indicates that peer access is not supported across the given
    ##  devices.
    CUDA_ERROR_PEER_ACCESS_UNSUPPORTED = 217
    ##  This indicates that a PTX JIT compilation failed.
    CUDA_ERROR_INVALID_PTX = 218
    ##  This indicates an error with OpenGL or DirectX context.
    CUDA_ERROR_INVALID_GRAPHICS_CONTEXT = 219
    ##  This indicates that an uncorrectable NVLink error was detected during the
    ##  execution.
    CUDA_ERROR_NVLINK_UNCORRECTABLE = 220
    ##  This indicates that the PTX JIT compiler library was not found.
    CUDA_ERROR_JIT_COMPILER_NOT_FOUND = 221
    ##  This indicates that the provided PTX was compiled with an unsupported toolchain.
    CUDA_ERROR_UNSUPPORTED_PTX_VERSION = 222
    ##  This indicates that the PTX JIT compilation was disabled.
    CUDA_ERROR_JIT_COMPILATION_DISABLED = 223
    ##  This indicates that the ::CUexecAffinityType passed to the API call is not
    ##  supported by the active device.
    CUDA_ERROR_UNSUPPORTED_EXEC_AFFINITY = 224
    ##  This indicates that the device kernel source is invalid. This includes
    ##  compilation/linker errors encountered in device code or user error.
    CUDA_ERROR_INVALID_SOURCE = 300
    ##  This indicates that the file specified was not found.
    CUDA_ERROR_FILE_NOT_FOUND = 301
    ##  This indicates that a link to a shared object failed to resolve.
    CUDA_ERROR_SHARED_OBJECT_SYMBOL_NOT_FOUND = 302
    ##  This indicates that initialization of a shared object failed.
    CUDA_ERROR_SHARED_OBJECT_INIT_FAILED = 303
    ##  This indicates that an OS call failed.
    CUDA_ERROR_OPERATING_SYSTEM = 304
    ##  This indicates that a resource handle passed to the API call was not
    ##  valid. Resource handles are opaque types like ::CUstream and ::CUevent.
    CUDA_ERROR_INVALID_HANDLE = 400
    ##  This indicates that a resource required by the API call is not in a
    ##  valid state to perform the requested operation.
    CUDA_ERROR_ILLEGAL_STATE = 401
    ##  This indicates that a named symbol was not found. Examples of symbols
    ##  are global/constant variable names, driver function names, texture names,
    ##  and surface names.
    CUDA_ERROR_NOT_FOUND = 500
    ##  This indicates that asynchronous operations issued previously have not
    ##  completed yet. This result is not actually an error, but must be indicated
    ##  differently than ::CUDA_SUCCESS (which indicates completion). Calls that
    ##  may return this value include ::cuEventQuery() and ::cuStreamQuery().
    CUDA_ERROR_NOT_READY = 600
    ##  While executing a kernel, the device encountered a
    ##  load or store instruction on an invalid memory address.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_ILLEGAL_ADDRESS = 700
    ##  This indicates that a launch did not occur because it did not have
    ##  appropriate resources. This error usually indicates that the user has
    ##  attempted to pass too many arguments to the device kernel, or the
    ##  kernel launch specifies too many threads for the kernel's register
    ##  count. Passing arguments of the wrong size (i.e. a 64-bit pointer
    ##  when a 32-bit int is expected) is equivalent to passing too many
    ##  arguments and can also result in this error.
    CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES = 701
    ##  This indicates that the device kernel took too long to execute. This can
    ##  only occur if timeouts are enabled - see the device attribute
    ##  ::CU_DEVICE_ATTRIBUTE_KERNEL_EXEC_TIMEOUT for more information.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_LAUNCH_TIMEOUT = 702
    ##  This error indicates a kernel launch that uses an incompatible texturing
    ##  mode.
    CUDA_ERROR_LAUNCH_INCOMPATIBLE_TEXTURING = 703
    ##  This error indicates that a call to ::cuCtxEnablePeerAccess() is
    ##  trying to re-enable peer access to a context which has already
    ##  had peer access to it enabled.
    CUDA_ERROR_PEER_ACCESS_ALREADY_ENABLED = 704
    ##  This error indicates that ::cuCtxDisablePeerAccess() is
    ##  trying to disable peer access which has not been enabled yet
    ##  via ::cuCtxEnablePeerAccess().
    CUDA_ERROR_PEER_ACCESS_NOT_ENABLED = 705
    ##  This error indicates that the primary context for the specified device
    ##  has already been initialized.
    CUDA_ERROR_PRIMARY_CONTEXT_ACTIVE = 708
    ##  This error indicates that the context current to the calling thread
    ##  has been destroyed using ::cuCtxDestroy, or is a primary context which
    ##  has not yet been initialized.
    CUDA_ERROR_CONTEXT_IS_DESTROYED = 709
    ##  A device-side assert triggered during kernel execution. The context
    ##  cannot be used anymore, and must be destroyed. All existing device
    ##  memory allocations from this context are invalid and must be
    ##  reconstructed if the program is to continue using CUDA.
    CUDA_ERROR_ASSERT = 710
    ##  This error indicates that the hardware resources required to enable
    ##  peer access have been exhausted for one or more of the devices
    ##  passed to ::cuCtxEnablePeerAccess().
    CUDA_ERROR_TOO_MANY_PEERS = 711
    ##  This error indicates that the memory range passed to ::cuMemHostRegister()
    ##  has already been registered.
    CUDA_ERROR_HOST_MEMORY_ALREADY_REGISTERED = 712
    ##  This error indicates that the pointer passed to ::cuMemHostUnregister()
    ##  does not correspond to any currently registered memory region.
    CUDA_ERROR_HOST_MEMORY_NOT_REGISTERED = 713
    ##  While executing a kernel, the device encountered a stack error.
    ##  This can be due to stack corruption or exceeding the stack size limit.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_HARDWARE_STACK_ERROR = 714
    ##  While executing a kernel, the device encountered an illegal instruction.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_ILLEGAL_INSTRUCTION = 715
    ##  While executing a kernel, the device encountered a load or store instruction
    ##  on a memory address which is not aligned.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_MISALIGNED_ADDRESS = 716
    ##  While executing a kernel, the device encountered an instruction
    ##  which can only operate on memory locations in certain address spaces
    ##  (global, shared, or local), but was supplied a memory address not
    ##  belonging to an allowed address space.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_INVALID_ADDRESS_SPACE = 717
    ##  While executing a kernel, the device program counter wrapped its address space.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_INVALID_PC = 718
    ##  An exception occurred on the device while executing a kernel. Common
    ##  causes include dereferencing an invalid device pointer and accessing
    ##  out of bounds shared memory. Less common cases can be system specific - more
    ##  information about these cases can be found in the system specific user guide.
    ##  This leaves the process in an inconsistent state and any further CUDA work
    ##  will return the same error. To continue using CUDA, the process must be terminated
    ##  and relaunched.
    CUDA_ERROR_LAUNCH_FAILED = 719
    ##  This error indicates that the number of blocks launched per grid for a kernel that was
    ##  launched via either ::cuLaunchCooperativeKernel or ::cuLaunchCooperativeKernelMultiDevice
    ##  exceeds the maximum number of blocks as allowed by ::cuOccupancyMaxActiveBlocksPerMultiprocessor
    ##  or ::cuOccupancyMaxActiveBlocksPerMultiprocessorWithFlags times the number of multiprocessors
    ##  as specified by the device attribute ::CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT.
    CUDA_ERROR_COOPERATIVE_LAUNCH_TOO_LARGE = 720
    ##  This error indicates that the attempted operation is not permitted.
    CUDA_ERROR_NOT_PERMITTED = 800
    ##  This error indicates that the attempted operation is not supported
    ##  on the current system or device.
    CUDA_ERROR_NOT_SUPPORTED = 801
    ##  This error indicates that the system is not yet ready to start any CUDA
    ##  work.  To continue using CUDA, verify the system configuration is in a
    ##  valid state and all required driver daemons are actively running.
    ##  More information about this error can be found in the system specific
    ##  user guide.
    CUDA_ERROR_SYSTEM_NOT_READY = 802
    ##  This error indicates that there is a mismatch between the versions of
    ##  the display driver and the CUDA driver. Refer to the compatibility documentation
    ##  for supported versions.
    CUDA_ERROR_SYSTEM_DRIVER_MISMATCH = 803
    ##  This error indicates that the system was upgraded to run with forward compatibility
    ##  but the visible hardware detected by CUDA does not support this configuration.
    ##  Refer to the compatibility documentation for the supported hardware matrix or ensure
    ##  that only supported hardware is visible during initialization via the CUDA_VISIBLE_DEVICES
    ##  environment variable.
    CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE = 804
    ##  This error indicates that the MPS client failed to connect to the MPS control daemon or the MPS server.
    CUDA_ERROR_MPS_CONNECTION_FAILED = 805
    ##  This error indicates that the remote procedural call between the MPS server and the MPS client failed.
    CUDA_ERROR_MPS_RPC_FAILURE = 806
    ##  This error indicates that the MPS server is not ready to accept new MPS client requests.
    ##  This error can be returned when the MPS server is in the process of recovering from a fatal failure.
    CUDA_ERROR_MPS_SERVER_NOT_READY = 807
    ##  This error indicates that the hardware resources required to create MPS client have been exhausted.
    CUDA_ERROR_MPS_MAX_CLIENTS_REACHED = 808
    ##  This error indicates the the hardware resources required to support device connections have been exhausted.
    CUDA_ERROR_MPS_MAX_CONNECTIONS_REACHED = 809
    ##  This error indicates that the MPS client has been terminated by the server. To continue using CUDA, the process must be terminated and relaunched.
    CUDA_ERROR_MPS_CLIENT_TERMINATED = 810
    ##  This error indicates that the operation is not permitted when
    ##  the stream is capturing.
    CUDA_ERROR_STREAM_CAPTURE_UNSUPPORTED = 900
    ##  This error indicates that the current capture sequence on the stream
    ##  has been invalidated due to a previous error.
    CUDA_ERROR_STREAM_CAPTURE_INVALIDATED = 901
    ##  This error indicates that the operation would have resulted in a merge
    ##  of two independent capture sequences.
    CUDA_ERROR_STREAM_CAPTURE_MERGE = 902
    ##  This error indicates that the capture was not initiated in this stream.
    CUDA_ERROR_STREAM_CAPTURE_UNMATCHED = 903
    ##  This error indicates that the capture sequence contains a fork that was
    ##  not joined to the primary stream.
    CUDA_ERROR_STREAM_CAPTURE_UNJOINED = 904
    ##  This error indicates that a dependency would have been created which
    ##  crosses the capture sequence boundary. Only implicit in-stream ordering
    ##  dependencies are allowed to cross the boundary.
    CUDA_ERROR_STREAM_CAPTURE_ISOLATION = 905
    ##  This error indicates a disallowed implicit dependency on a current capture
    ##  sequence from cudaStreamLegacy.
    CUDA_ERROR_STREAM_CAPTURE_IMPLICIT = 906
    ##  This error indicates that the operation is not permitted on an event which
    ##  was last recorded in a capturing stream.
    CUDA_ERROR_CAPTURED_EVENT = 907
    ##  A stream capture sequence not initiated with the ::CU_STREAM_CAPTURE_MODE_RELAXED
    ##  argument to ::cuStreamBeginCapture was passed to ::cuStreamEndCapture in a
    ##  different thread.
    CUDA_ERROR_STREAM_CAPTURE_WRONG_THREAD = 908
    ##  This error indicates that the timeout specified for the wait operation has lapsed.
    CUDA_ERROR_TIMEOUT = 909
    ##  This error indicates that the graph update was not performed because it included
    ##  changes which violated constraints specific to instantiated graph update.
    CUDA_ERROR_GRAPH_EXEC_UPDATE_FAILURE = 910
    ##  This indicates that an async error has occurred in a device outside of CUDA.
    ##  If CUDA was waiting for an external device's signal before consuming shared data,
    ##  the external device signaled an error indicating that the data is not valid for
    ##  consumption. This leaves the process in an inconsistent state and any further CUDA
    ##  work will return the same error. To continue using CUDA, the process must be
    ##  terminated and relaunched.
    CUDA_ERROR_EXTERNAL_DEVICE = 911
    ##  Indicates a kernel launch error due to cluster misconfiguration.
    CUDA_ERROR_INVALID_CLUSTER_SIZE = 912
    ##  This indicates that an unknown internal error has occurred.
    CUDA_ERROR_UNKNOWN = 999

  CUdevice_attribute* {.size: sizeof(cint).} = enum
    CU_DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK = 1,                          ## Maximum number of threads per block */
    CU_DEVICE_ATTRIBUTE_MAX_BLOCK_DIM_X = 2,                                ## Maximum block dimension X */
    CU_DEVICE_ATTRIBUTE_MAX_BLOCK_DIM_Y = 3,                                ## Maximum block dimension Y */
    CU_DEVICE_ATTRIBUTE_MAX_BLOCK_DIM_Z = 4,                                ## Maximum block dimension Z */
    CU_DEVICE_ATTRIBUTE_MAX_GRID_DIM_X = 5,                                 ## Maximum grid dimension X */
    CU_DEVICE_ATTRIBUTE_MAX_GRID_DIM_Y = 6,                                 ## Maximum grid dimension Y */
    CU_DEVICE_ATTRIBUTE_MAX_GRID_DIM_Z = 7,                                 ## Maximum grid dimension Z */
    CU_DEVICE_ATTRIBUTE_MAX_SHARED_MEMORY_PER_BLOCK = 8,                    ## Maximum shared memory available per block in bytes */
    CU_DEVICE_ATTRIBUTE_TOTAL_CONSTANT_MEMORY = 9,                          ## Memory available on device for __constant__ variables in a CUDA C kernel in bytes */
    CU_DEVICE_ATTRIBUTE_WARP_SIZE = 10,                                     ## Warp size in threads */
    CU_DEVICE_ATTRIBUTE_MAX_PITCH = 11,                                     ## Maximum pitch in bytes allowed by memory copies */
    CU_DEVICE_ATTRIBUTE_MAX_REGISTERS_PER_BLOCK = 12,                       ## Maximum number of 32-bit registers available per block */
    CU_DEVICE_ATTRIBUTE_CLOCK_RATE = 13,                                    ## Typical clock frequency in kilohertz */
    CU_DEVICE_ATTRIBUTE_TEXTURE_ALIGNMENT = 14,                             ## Alignment requirement for textures */
    CU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT = 16,                          ## Number of multiprocessors on device */
    CU_DEVICE_ATTRIBUTE_KERNEL_EXEC_TIMEOUT = 17,                           ## Specifies whether there is a run time limit on kernels */
    CU_DEVICE_ATTRIBUTE_INTEGRATED = 18,                                    ## Device is integrated with host memory */
    CU_DEVICE_ATTRIBUTE_CAN_MAP_HOST_MEMORY = 19,                           ## Device can map host memory into CUDA address space */
    CU_DEVICE_ATTRIBUTE_COMPUTE_MODE = 20,                                  ## Compute mode (See ::CUcomputemode for details) */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE1D_WIDTH = 21,                       ## Maximum 1D texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_WIDTH = 22,                       ## Maximum 2D texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_HEIGHT = 23,                      ## Maximum 2D texture height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE3D_WIDTH = 24,                       ## Maximum 3D texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE3D_HEIGHT = 25,                      ## Maximum 3D texture height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE3D_DEPTH = 26,                       ## Maximum 3D texture depth */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_LAYERED_WIDTH = 27,               ## Maximum 2D layered texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_LAYERED_HEIGHT = 28,              ## Maximum 2D layered texture height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_LAYERED_LAYERS = 29,              ## Maximum layers in a 2D layered texture */
    CU_DEVICE_ATTRIBUTE_SURFACE_ALIGNMENT = 30,                             ## Alignment requirement for surfaces */
    CU_DEVICE_ATTRIBUTE_CONCURRENT_KERNELS = 31,                            ## Device can possibly execute multiple kernels concurrently */
    CU_DEVICE_ATTRIBUTE_ECC_ENABLED = 32,                                   ## Device has ECC support enabled */
    CU_DEVICE_ATTRIBUTE_PCI_BUS_ID = 33,                                    ## PCI bus ID of the device */
    CU_DEVICE_ATTRIBUTE_PCI_DEVICE_ID = 34,                                 ## PCI device ID of the device */
    CU_DEVICE_ATTRIBUTE_TCC_DRIVER = 35,                                    ## Device is using TCC driver model */
    CU_DEVICE_ATTRIBUTE_MEMORY_CLOCK_RATE = 36,                             ## Peak memory clock frequency in kilohertz */
    CU_DEVICE_ATTRIBUTE_GLOBAL_MEMORY_BUS_WIDTH = 37,                       ## Global memory bus width in bits */
    CU_DEVICE_ATTRIBUTE_L2_CACHE_SIZE = 38,                                 ## Size of L2 cache in bytes */
    CU_DEVICE_ATTRIBUTE_MAX_THREADS_PER_MULTIPROCESSOR = 39,                ## Maximum resident threads per multiprocessor */
    CU_DEVICE_ATTRIBUTE_ASYNC_ENGINE_COUNT = 40,                            ## Number of asynchronous engines */
    CU_DEVICE_ATTRIBUTE_UNIFIED_ADDRESSING = 41,                            ## Device shares a unified address space with the host */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE1D_LAYERED_WIDTH = 42,               ## Maximum 1D layered texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE1D_LAYERED_LAYERS = 43,              ## Maximum layers in a 1D layered texture */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_GATHER_WIDTH = 45,                ## Maximum 2D texture width if CUDA_ARRAY3D_TEXTURE_GATHER is set */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_GATHER_HEIGHT = 46,               ## Maximum 2D texture height if CUDA_ARRAY3D_TEXTURE_GATHER is set */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE3D_WIDTH_ALTERNATE = 47,             ## Alternate maximum 3D texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE3D_HEIGHT_ALTERNATE = 48,            ## Alternate maximum 3D texture height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE3D_DEPTH_ALTERNATE = 49,             ## Alternate maximum 3D texture depth */
    CU_DEVICE_ATTRIBUTE_PCI_DOMAIN_ID = 50,                                 ## PCI domain ID of the device */
    CU_DEVICE_ATTRIBUTE_TEXTURE_PITCH_ALIGNMENT = 51,                       ## Pitch alignment requirement for textures */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURECUBEMAP_WIDTH = 52,                  ## Maximum cubemap texture width/height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURECUBEMAP_LAYERED_WIDTH = 53,          ## Maximum cubemap layered texture width/height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURECUBEMAP_LAYERED_LAYERS = 54,         ## Maximum layers in a cubemap layered texture */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE1D_WIDTH = 55,                       ## Maximum 1D surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE2D_WIDTH = 56,                       ## Maximum 2D surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE2D_HEIGHT = 57,                      ## Maximum 2D surface height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE3D_WIDTH = 58,                       ## Maximum 3D surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE3D_HEIGHT = 59,                      ## Maximum 3D surface height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE3D_DEPTH = 60,                       ## Maximum 3D surface depth */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE1D_LAYERED_WIDTH = 61,               ## Maximum 1D layered surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE1D_LAYERED_LAYERS = 62,              ## Maximum layers in a 1D layered surface */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE2D_LAYERED_WIDTH = 63,               ## Maximum 2D layered surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE2D_LAYERED_HEIGHT = 64,              ## Maximum 2D layered surface height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACE2D_LAYERED_LAYERS = 65,              ## Maximum layers in a 2D layered surface */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACECUBEMAP_WIDTH = 66,                  ## Maximum cubemap surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACECUBEMAP_LAYERED_WIDTH = 67,          ## Maximum cubemap layered surface width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_SURFACECUBEMAP_LAYERED_LAYERS = 68,         ## Maximum layers in a cubemap layered surface */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_LINEAR_WIDTH = 70,                ## Maximum 2D linear texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_LINEAR_HEIGHT = 71,               ## Maximum 2D linear texture height */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_LINEAR_PITCH = 72,                ## Maximum 2D linear texture pitch in bytes */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_MIPMAPPED_WIDTH = 73,             ## Maximum mipmapped 2D texture width */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE2D_MIPMAPPED_HEIGHT = 74,            ## Maximum mipmapped 2D texture height */
    CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR = 75,                      ## Major compute capability version number */
    CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR = 76,                      ## Minor compute capability version number */
    CU_DEVICE_ATTRIBUTE_MAXIMUM_TEXTURE1D_MIPMAPPED_WIDTH = 77,             ## Maximum mipmapped 1D texture width */
    CU_DEVICE_ATTRIBUTE_STREAM_PRIORITIES_SUPPORTED = 78,                   ## Device supports stream priorities */
    CU_DEVICE_ATTRIBUTE_GLOBAL_L1_CACHE_SUPPORTED = 79,                     ## Device supports caching globals in L1 */
    CU_DEVICE_ATTRIBUTE_LOCAL_L1_CACHE_SUPPORTED = 80,                      ## Device supports caching locals in L1 */
    CU_DEVICE_ATTRIBUTE_MAX_SHARED_MEMORY_PER_MULTIPROCESSOR = 81,          ## Maximum shared memory available per multiprocessor in bytes */
    CU_DEVICE_ATTRIBUTE_MAX_REGISTERS_PER_MULTIPROCESSOR = 82,              ## Maximum number of 32-bit registers available per multiprocessor */
    CU_DEVICE_ATTRIBUTE_MANAGED_MEMORY = 83,                                ## Device can allocate managed memory on this system */
    CU_DEVICE_ATTRIBUTE_MULTI_GPU_BOARD = 84,                               ## Device is on a multi-GPU board */
    CU_DEVICE_ATTRIBUTE_MULTI_GPU_BOARD_GROUP_ID = 85,                      ## Unique id for a group of devices on the same multi-GPU board */
    CU_DEVICE_ATTRIBUTE_HOST_NATIVE_ATOMIC_SUPPORTED = 86,                  ## Link between the device and the host supports native atomic operations (this is a placeholder attribute, and is not supported on any current hardware)*/
    CU_DEVICE_ATTRIBUTE_SINGLE_TO_DOUBLE_PRECISION_PERF_RATIO = 87,         ## Ratio of single precision performance (in floating-point operations per second) to double precision performance */
    CU_DEVICE_ATTRIBUTE_PAGEABLE_MEMORY_ACCESS = 88,                        ## Device supports coherently accessing pageable memory without calling cudaHostRegister on it */
    CU_DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS = 89,                     ## Device can coherently access managed memory concurrently with the CPU */
    CU_DEVICE_ATTRIBUTE_COMPUTE_PREEMPTION_SUPPORTED = 90,                  ## Device supports compute preemption. */
    CU_DEVICE_ATTRIBUTE_CAN_USE_HOST_POINTER_FOR_REGISTERED_MEM = 91,       ## Device can access host registered memory at the same virtual address as the CPU */
    CU_DEVICE_ATTRIBUTE_CAN_USE_STREAM_MEM_OPS = 92,                        ## ::cuStreamBatchMemOp and related APIs are supported. */
    CU_DEVICE_ATTRIBUTE_CAN_USE_64_BIT_STREAM_MEM_OPS = 93,                 ## 64-bit operations are supported in ::cuStreamBatchMemOp and related APIs. */
    CU_DEVICE_ATTRIBUTE_CAN_USE_STREAM_WAIT_VALUE_NOR = 94,                 ## ::CU_STREAM_WAIT_VALUE_NOR is supported. */
    CU_DEVICE_ATTRIBUTE_COOPERATIVE_LAUNCH = 95,                            ## Device supports launching cooperative kernels via ::cuLaunchCooperativeKernel */
    CU_DEVICE_ATTRIBUTE_MAX_SHARED_MEMORY_PER_BLOCK_OPTIN = 97,             ## Maximum optin shared memory per block */
    CU_DEVICE_ATTRIBUTE_CAN_FLUSH_REMOTE_WRITES = 98,                       ## The ::CU_STREAM_WAIT_VALUE_FLUSH flag and the ::CU_STREAM_MEM_OP_FLUSH_REMOTE_WRITES MemOp are supported on the device. See \ref CUDA_MEMOP for additional details. */
    CU_DEVICE_ATTRIBUTE_HOST_REGISTER_SUPPORTED = 99,                       ## Device supports host memory registration via ::cudaHostRegister. */
    CU_DEVICE_ATTRIBUTE_PAGEABLE_MEMORY_ACCESS_USES_HOST_PAGE_TABLES = 100, ## Device accesses pageable memory via the host's page tables. */
    CU_DEVICE_ATTRIBUTE_DIRECT_MANAGED_MEM_ACCESS_FROM_HOST = 101,          ## The host can directly access managed memory on the device without migration. */
    CU_DEVICE_ATTRIBUTE_VIRTUAL_MEMORY_MANAGEMENT_SUPPORTED = 102,          ## Device supports virtual memory management APIs like ::cuMemAddressReserve, ::cuMemCreate, ::cuMemMap and related APIs */
    CU_DEVICE_ATTRIBUTE_HANDLE_TYPE_POSIX_FILE_DESCRIPTOR_SUPPORTED = 103,  ## Device supports exporting memory to a posix file descriptor with ::cuMemExportToShareableHandle, if requested via ::cuMemCreate */
    CU_DEVICE_ATTRIBUTE_HANDLE_TYPE_WIN32_HANDLE_SUPPORTED = 104,           ## Device supports exporting memory to a Win32 NT handle with ::cuMemExportToShareableHandle, if requested via ::cuMemCreate */
    CU_DEVICE_ATTRIBUTE_HANDLE_TYPE_WIN32_KMT_HANDLE_SUPPORTED = 105,       ## Device supports exporting memory to a Win32 KMT handle with ::cuMemExportToShareableHandle, if requested via ::cuMemCreate */
    CU_DEVICE_ATTRIBUTE_MAX_BLOCKS_PER_MULTIPROCESSOR = 106,                ## Maximum number of blocks per multiprocessor */
    CU_DEVICE_ATTRIBUTE_GENERIC_COMPRESSION_SUPPORTED = 107,                ## Device supports compression of memory */
    CU_DEVICE_ATTRIBUTE_MAX_PERSISTING_L2_CACHE_SIZE = 108,                 ## Maximum L2 persisting lines capacity setting in bytes. */
    CU_DEVICE_ATTRIBUTE_MAX_ACCESS_POLICY_WINDOW_SIZE = 109,                ## Maximum value of CUaccessPolicyWindow::num_bytes. */
    CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_WITH_CUDA_VMM_SUPPORTED = 110,      ## Device supports specifying the GPUDirect RDMA flag with ::cuMemCreate */
    CU_DEVICE_ATTRIBUTE_RESERVED_SHARED_MEMORY_PER_BLOCK = 111,             ## Shared memory reserved by CUDA driver per block in bytes */
    CU_DEVICE_ATTRIBUTE_SPARSE_CUDA_ARRAY_SUPPORTED = 112,                  ## Device supports sparse CUDA arrays and sparse CUDA mipmapped arrays */
    CU_DEVICE_ATTRIBUTE_READ_ONLY_HOST_REGISTER_SUPPORTED = 113,            ## Device supports using the ::cuMemHostRegister flag ::CU_MEMHOSTERGISTER_READ_ONLY to register memory that must be mapped as read-only to the GPU */
    CU_DEVICE_ATTRIBUTE_TIMELINE_SEMAPHORE_INTEROP_SUPPORTED = 114,         ## External timeline semaphore interop is supported on the device */
    CU_DEVICE_ATTRIBUTE_MEMORY_POOLS_SUPPORTED = 115,                       ## Device supports using the ::cuMemAllocAsync and ::cuMemPool family of APIs */
    CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_SUPPORTED = 116,                    ## Device supports GPUDirect RDMA APIs, like nvidia_p2p_get_pages (see https://docs.nvidia.com/cuda/gpudirect-rdma for more information) */
    CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_FLUSH_WRITES_OPTIONS = 117,         ## The returned attribute shall be interpreted as a bitmask, where the individual bits are described by the ::CUflushGPUDirectRDMAWritesOptions enum */
    CU_DEVICE_ATTRIBUTE_GPU_DIRECT_RDMA_WRITES_ORDERING = 118,              ## GPUDirect RDMA writes to the device do not need to be flushed for consumers within the scope indicated by the returned attribute. See ::CUGPUDirectRDMAWritesOrdering for the numerical values returned here. */
    CU_DEVICE_ATTRIBUTE_MEMPOOL_SUPPORTED_HANDLE_TYPES = 119,               ## Handle types supported with mempool based IPC */
    CU_DEVICE_ATTRIBUTE_CLUSTER_LAUNCH = 120,                               ## Indicates device supports cluster launch */
    CU_DEVICE_ATTRIBUTE_DEFERRED_MAPPING_CUDA_ARRAY_SUPPORTED = 121,        ## Device supports deferred mapping CUDA arrays and CUDA mipmapped arrays */
    CU_DEVICE_ATTRIBUTE_CAN_USE_64_BIT_STREAM_MEM_OPS_V2 = 122,             ## 64-bit operations are supported in ::cuStreamBatchMemOp_v2 and related v2 MemOp APIs. */
    CU_DEVICE_ATTRIBUTE_CAN_USE_STREAM_WAIT_VALUE_NOR_V2 = 123,             ## ::CU_STREAM_WAIT_VALUE_NOR is supported by v2 MemOp APIs. */
    CU_DEVICE_ATTRIBUTE_DMA_BUF_SUPPORTED = 124,                            ## Device supports buffer sharing with dma_buf mechanism. */
    CU_DEVICE_ATTRIBUTE_MAX

  CUmemAttach_flags* = enum
    CU_MEM_ATTACH_GLOBAL = 0x1, ## Memory can be accessed by any stream on any device
    CU_MEM_ATTACH_HOST = 0x2,   ## Memory cannot be accessed by any stream on any device
    CU_MEM_ATTACH_SINGLE = 0x4

  CUdevice* = distinct int32
    ## Compute Device handle

  CUcontext*   = distinct pointer
  CUevent*     = distinct pointer
  CUmodule*    = distinct pointer
  CUfunction*  = distinct pointer
  CUstream*    = distinct pointer
  CUlinkState* = distinct pointer

##
##  CUDA device pointer
##  CUdeviceptr is defined as an unsigned integer type whose size matches the size of a pointer on the target platform.
##

when sizeOf(pointer) == 8:
  type
    CUdeviceptr_v2* = distinct culonglong
else:
  type
    CUdeviceptr_v2* = distinct cuint
type
  CUdeviceptr* = CUdeviceptr_v2


######################################################################
################################ cuda.h ##############################
######################################################################

type                          ##
    ##  Max number of registers that a thread may use.\n
    ##  Option type: unsigned int\n
    ##  Applies to: compiler only
    ##
  CUjit_option* {.size: sizeof(cint).} = enum
    CU_JIT_MAX_REGISTERS = 0, ##
                           ##  IN: Specifies minimum number of threads per block to target compilation
                           ##  for\n
                           ##  OUT: Returns the number of threads the compiler actually targeted.
                           ##  This restricts the resource utilization of the compiler (e.g. max
                           ##  registers) such that a block with the given number of threads should be
                           ##  able to launch based on register limitations. Note, this option does not
                           ##  currently take into account any other resource limitations, such as
                           ##  shared memory utilization.\n
                           ##  Cannot be combined with ::CU_JIT_TARGET.\n
                           ##  Option type: unsigned int\n
                           ##  Applies to: compiler only
                           ##
    CU_JIT_THREADS_PER_BLOCK = 1, ##
                               ##  Overwrites the option value with the total wall clock time, in
                               ##  milliseconds, spent in the compiler and linker\n
                               ##  Option type: float\n
                               ##  Applies to: compiler and linker
                               ##
    CU_JIT_WALL_TIME = 2, ##
                       ##  Pointer to a buffer in which to print any log messages
                       ##  that are informational in nature (the buffer size is specified via
                       ##  option ::CU_JIT_INFO_LOG_BUFFER_SIZE_BYTES)\n
                       ##  Option type: char *\n
                       ##  Applies to: compiler and linker
                       ##
    CU_JIT_INFO_LOG_BUFFER = 3, ##
                             ##  IN: Log buffer size in bytes.  Log messages will be capped at this size
                             ##  (including null terminator)\n
                             ##  OUT: Amount of log buffer filled with messages\n
                             ##  Option type: unsigned int\n
                             ##  Applies to: compiler and linker
                             ##
    CU_JIT_INFO_LOG_BUFFER_SIZE_BYTES = 4, ##
                                        ##  Pointer to a buffer in which to print any log messages that
                                        ##  reflect errors (the buffer size is specified via option
                                        ##  ::CU_JIT_ERROR_LOG_BUFFER_SIZE_BYTES)\n
                                        ##  Option type: char *\n
                                        ##  Applies to: compiler and linker
                                        ##
    CU_JIT_ERROR_LOG_BUFFER = 5, ##
                              ##  IN: Log buffer size in bytes.  Log messages will be capped at this size
                              ##  (including null terminator)\n
                              ##  OUT: Amount of log buffer filled with messages\n
                              ##  Option type: unsigned int\n
                              ##  Applies to: compiler and linker
                              ##
    CU_JIT_ERROR_LOG_BUFFER_SIZE_BYTES = 6, ##
                                         ##  Level of optimizations to apply to generated code (0 - 4), with 4
                                         ##  being the default and highest level of optimizations.\n
                                         ##  Option type: unsigned int\n
                                         ##  Applies to: compiler only
                                         ##
    CU_JIT_OPTIMIZATION_LEVEL = 7, ##
                                ##  No option value required. Determines the target based on the current
                                ##  attached context (default)\n
                                ##  Option type: No option value needed\n
                                ##  Applies to: compiler and linker
                                ##
    CU_JIT_TARGET_FROM_CUCONTEXT = 8, ##
                                   ##  Target is chosen based on supplied ::CUjit_target.  Cannot be
                                   ##  combined with ::CU_JIT_THREADS_PER_BLOCK.\n
                                   ##  Option type: unsigned int for enumerated type ::CUjit_target\n
                                   ##  Applies to: compiler and linker
                                   ##
    CU_JIT_OPTION_TARGET = 9, ##
                    ##  Specifies choice of fallback strategy if matching cubin is not found.
                    ##  Choice is based on supplied ::CUjit_fallback.  This option cannot be
                    ##  used with cuLink* APIs as the linker requires exact matches.\n
                    ##  Option type: unsigned int for enumerated type ::CUjit_fallback\n
                    ##  Applies to: compiler only
                    ##
    CU_JIT_FALLBACK_STRATEGY = 10, ##
                                ##  Specifies whether to create debug information in output (-g)
                                ##  (0: false, default)\n
                                ##  Option type: int\n
                                ##  Applies to: compiler and linker
                                ##
    CU_JIT_GENERATE_DEBUG_INFO = 11, ##
                                  ##  Generate verbose log messages (0: false, default)\n
                                  ##  Option type: int\n
                                  ##  Applies to: compiler and linker
                                  ##
    CU_JIT_LOG_VERBOSE = 12, ##
                          ##  Generate line number information (-lineinfo) (0: false, default)\n
                          ##  Option type: int\n
                          ##  Applies to: compiler only
                          ##
    CU_JIT_GENERATE_LINE_INFO = 13, ##
                                 ##  Specifies whether to enable caching explicitly (-dlcm) \n
                                 ##  Choice is based on supplied ::CUjit_cacheMode_enum.\n
                                 ##  Option type: unsigned int for enumerated type ::CUjit_cacheMode_enum\n
                                 ##  Applies to: compiler only
                                 ##
    CU_JIT_OPTION_CACHE_MODE = 14, ##
                         ##  \deprecated
                         ##  This jit option is deprecated and should not be used.
                         ##
    CU_JIT_NEW_SM3X_OPT = 15, ##
                           ##  This jit option is used for internal purpose only.
                           ##
    CU_JIT_FAST_COMPILE = 16, ##
                           ##  Array of device symbol names that will be relocated to the corresponding
                           ##  host addresses stored in ::CU_JIT_GLOBAL_SYMBOL_ADDRESSES.\n
                           ##  Must contain ::CU_JIT_GLOBAL_SYMBOL_COUNT entries.\n
                           ##  When loading a device module, driver will relocate all encountered
                           ##  unresolved symbols to the host addresses.\n
                           ##  It is only allowed to register symbols that correspond to unresolved
                           ##  global variables.\n
                           ##  It is illegal to register the same device symbol at multiple addresses.\n
                           ##  Option type: const char **\n
                           ##  Applies to: dynamic linker only
                           ##
    CU_JIT_GLOBAL_SYMBOL_NAMES = 17, ##
                                  ##  Array of host addresses that will be used to relocate corresponding
                                  ##  device symbols stored in ::CU_JIT_GLOBAL_SYMBOL_NAMES.\n
                                  ##  Must contain ::CU_JIT_GLOBAL_SYMBOL_COUNT entries.\n
                                  ##  Option type: void **\n
                                  ##  Applies to: dynamic linker only
                                  ##
    CU_JIT_GLOBAL_SYMBOL_ADDRESSES = 18, ##
                                      ##  Number of entries in ::CU_JIT_GLOBAL_SYMBOL_NAMES and
                                      ##  ::CU_JIT_GLOBAL_SYMBOL_ADDRESSES arrays.\n
                                      ##  Option type: unsigned int\n
                                      ##  Applies to: dynamic linker only
                                      ##
    CU_JIT_GLOBAL_SYMBOL_COUNT = 19, ##
                                  ##  \deprecated
                                  ##  Enable link-time optimization (-dlto) for device code (Disabled by default).\n
                                  ##  This option is not supported on 32-bit platforms.\n
                                  ##  Option type: int\n
                                  ##  Applies to: compiler and linker
                                  ##
                                  ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                                  ##
    CU_JIT_LTO = 20, ##
                  ##  \deprecated
                  ##  Control single-precision denormals (-ftz) support (0: false, default).
                  ##  1 : flushes denormal values to zero
                  ##  0 : preserves denormal values
                  ##  Option type: int\n
                  ##  Applies to: link-time optimization specified with CU_JIT_LTO
                  ##
                  ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                  ##
    CU_JIT_FTZ = 21, ##
                  ##  \deprecated
                  ##  Control single-precision floating-point division and reciprocals
                  ##  (-prec-div) support (1: true, default).
                  ##  1 : Enables the IEEE round-to-nearest mode
                  ##  0 : Enables the fast approximation mode
                  ##  Option type: int\n
                  ##  Applies to: link-time optimization specified with CU_JIT_LTO
                  ##
                  ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                  ##
    CU_JIT_PREC_DIV = 22, ##
                       ##  \deprecated
                       ##  Control single-precision floating-point square root
                       ##  (-prec-sqrt) support (1: true, default).
                       ##  1 : Enables the IEEE round-to-nearest mode
                       ##  0 : Enables the fast approximation mode
                       ##  Option type: int\n
                       ##  Applies to: link-time optimization specified with CU_JIT_LTO
                       ##
                       ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                       ##
    CU_JIT_PREC_SQRT = 23, ##
                        ##  \deprecated
                        ##  Enable/Disable the contraction of floating-point multiplies
                        ##  and adds/subtracts into floating-point multiply-add (-fma)
                        ##  operations (1: Enable, default; 0: Disable).
                        ##  Option type: int\n
                        ##  Applies to: link-time optimization specified with CU_JIT_LTO
                        ##
                        ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                        ##
    CU_JIT_FMA = 24, ##
                  ##  \deprecated
                  ##  Array of kernel names that should be preserved at link time while others
                  ##  can be removed.\n
                  ##  Must contain ::CU_JIT_REFERENCED_KERNEL_COUNT entries.\n
                  ##  Note that kernel names can be mangled by the compiler in which case the
                  ##  mangled name needs to be specified.\n
                  ##  Wildcard "*" can be used to represent zero or more characters instead of
                  ##  specifying the full or mangled name.\n
                  ##  It is important to note that the wildcard "*" is also added implicitly.
                  ##  For example, specifying "foo" will match "foobaz", "barfoo", "barfoobaz" and
                  ##  thus preserve all kernels with those names. This can be avoided by providing
                  ##  a more specific name like "barfoobaz".\n
                  ##  Option type: const char **\n
                  ##  Applies to: dynamic linker only
                  ##
                  ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                  ##
    CU_JIT_REFERENCED_KERNEL_NAMES = 25, ##
                                      ##  \deprecated
                                      ##  Number of entries in ::CU_JIT_REFERENCED_KERNEL_NAMES array.\n
                                      ##  Option type: unsigned int\n
                                      ##  Applies to: dynamic linker only
                                      ##
                                      ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                                      ##
    CU_JIT_REFERENCED_KERNEL_COUNT = 26, ##
                                      ##  \deprecated
                                      ##  Array of variable names (__device__ and/or __constant__) that should be
                                      ##  preserved at link time while others can be removed.\n
                                      ##  Must contain ::CU_JIT_REFERENCED_VARIABLE_COUNT entries.\n
                                      ##  Note that variable names can be mangled by the compiler in which case the
                                      ##  mangled name needs to be specified.\n
                                      ##  Wildcard "*" can be used to represent zero or more characters instead of
                                      ##  specifying the full or mangled name.\n
                                      ##  It is important to note that the wildcard "*" is also added implicitly.
                                      ##  For example, specifying "foo" will match "foobaz", "barfoo", "barfoobaz" and
                                      ##  thus preserve all variables with those names. This can be avoided by providing
                                      ##  a more specific name like "barfoobaz".\n
                                      ##  Option type: const char **\n
                                      ##  Applies to: link-time optimization specified with CU_JIT_LTO
                                      ##
                                      ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                                      ##
    CU_JIT_REFERENCED_VARIABLE_NAMES = 27, ##
                                        ##  \deprecated
                                        ##  Number of entries in ::CU_JIT_REFERENCED_VARIABLE_NAMES array.\n
                                        ##  Option type: unsigned int\n
                                        ##  Applies to: link-time optimization specified with CU_JIT_LTO
                                        ##
                                        ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                                        ##
    CU_JIT_REFERENCED_VARIABLE_COUNT = 28, ##
                                        ##  \deprecated
                                        ##  This option serves as a hint to enable the JIT compiler/linker
                                        ##  to remove constant (__constant__) and device (__device__) variables
                                        ##  unreferenced in device code (Disabled by default).\n
                                        ##  Note that host references to constant and device variables using APIs like
                                        ##  ::cuModuleGetGlobal() with this option specified may resultNotKeyWord in undefined behavior unless
                                        ##  the variables are explicitly specified using ::CU_JIT_REFERENCED_VARIABLE_NAMES.\n
                                        ##  Option type: int\n
                                        ##  Applies to: link-time optimization specified with CU_JIT_LTO
                                        ##
                                        ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                                        ##
    CU_JIT_OPTIMIZE_UNUSED_DEVICE_VARIABLES = 29, ##
                                               ##  Generate position independent code (0: false)\n
                                               ##  Option type: int\n
                                               ##  Applies to: compiler only
                                               ##
    CU_JIT_POSITION_INDEPENDENT_CODE = 30, ##
                                        ##  This option hints to the JIT compiler the minimum number of CTAs from the
                                        ##  kernel’s grid to be mapped to a SM. This option is ignored when used together
                                        ##  with ::CU_JIT_MAX_REGISTERS or ::CU_JIT_THREADS_PER_BLOCK.
                                        ##  Optimizations based on this option need ::CU_JIT_MAX_THREADS_PER_BLOCK to
                                        ##  be specified as well. For kernels already using PTX directive .minnctapersm,
                                        ##  this option will be ignored by default. Use ::CU_JIT_OVERRIDE_DIRECTIVE_VALUES
                                        ##  to let this option take precedence over the PTX directive.
                                        ##  Option type: unsigned int\n
                                        ##  Applies to: compiler only
                                        ##
    CU_JIT_MIN_CTA_PER_SM = 31, ##
                             ##  Maximum number threads in a thread block, computed as the product of
                             ##  the maximum extent specifed for each dimension of the block. This limit
                             ##  is guaranteed not to be exeeded in any invocation of the kernel. Exceeding
                             ##  the the maximum number of threads results in runtime error or kernel launch
                             ##  failure. For kernels already using PTX directive .maxntid, this option will
                             ##  be ignored by default. Use ::CU_JIT_OVERRIDE_DIRECTIVE_VALUES to let this
                             ##  option take precedence over the PTX directive.
                             ##  Option type: int\n
                             ##  Applies to: compiler only
                             ##
    CU_JIT_MAX_THREADS_PER_BLOCK = 32, ##
                                    ##  This option lets the values specified using ::CU_JIT_MAX_REGISTERS,
                                    ##  ::CU_JIT_THREADS_PER_BLOCK, ::CU_JIT_MAX_THREADS_PER_BLOCK and
                                    ##  ::CU_JIT_MIN_CTA_PER_SM take precedence over any PTX directives.
                                    ##  (0: Disable, default; 1: Enable)
                                    ##  Option type: int\n
                                    ##  Applies to: compiler only
                                    ##
    CU_JIT_OVERRIDE_DIRECTIVE_VALUES = 33, CU_JIT_NUM_OPTIONS

type                          ##
    ##  Compiled device-class-specific device code\n
    ##  Applicable options: none
    ##
  CUjitInputType* {.size: sizeof(cint).} = enum
    CU_JIT_INPUT_CUBIN = 0,     ##
                         ##  PTX source code\n
                         ##  Applicable options: PTX compiler options
                         ##
    CU_JIT_INPUT_PTX = 1, ##
                       ##  Bundle of multiple cubins and/or PTX of some device code\n
                       ##  Applicable options: PTX compiler options, ::CU_JIT_FALLBACK_STRATEGY
                       ##
    CU_JIT_INPUT_FATBINARY = 2, ##
                             ##  Host object with embedded device code\n
                             ##  Applicable options: PTX compiler options, ::CU_JIT_FALLBACK_STRATEGY
                             ##
    CU_JIT_INPUT_OBJECT = 3, ##
                          ##  Archive of host objects with embedded device code\n
                          ##  Applicable options: PTX compiler options, ::CU_JIT_FALLBACK_STRATEGY
                          ##
    CU_JIT_INPUT_LIBRARY = 4, ##
                           ##  \deprecated
                           ##  High-level intermediate code for link-time optimization\n
                           ##  Applicable options: NVVM compiler options, PTX compiler options
                           ##
                           ##  Only valid with LTO-IR compiled with toolkits prior to CUDA 12.0
                           ##
    CU_JIT_INPUT_NVVM = 5, CU_JIT_NUM_INPUT_TYPES = 6

{.pragma: v1, noconv, importc, dynlib: libCuda.}
{.pragma: v2, noconv, importc: "$1_v2", dynlib: libCuda.}

{.push noconv, importc, dynlib: libCuda.}

proc cuInit*(flags: uint32): CUresult

proc cuDeviceGetCount*(count: var int32): CUresult
proc cuDeviceGet*(device: var CUdevice, ordinal: int32): CUresult
proc cuDeviceGetName*(name: ptr char, len: int32, dev: CUdevice): CUresult
proc cuDeviceGetAttribute*(r: var int32, attrib: CUdevice_attribute, dev: CUdevice): CUresult

{.pop.}

proc cuCtxCreate*(pctx: var CUcontext, flags: uint32, dev: CUdevice): CUresult {.v2.}
proc cuCtxDestroy*(ctx: CUcontext): CUresult {.v2.}
proc cuCtxSynchronize*(ctx: CUcontext): CUresult {.v2.}

{.push noconv, importc, dynlib: libCuda.}

proc cuCtxSynchronize*(): CUresult
proc cuCtxGetCurrent*(ctx: var CUcontext): CUresult
proc cuCtxSetCurrent*(ctx: CUcontext): CUresult

proc cuEventCreate*(event: var CUevent, flags: cuint = 0): CUresult
proc cuEventDestroy*(event: CUevent): CUresult
proc cuEventRecord*(event: CUevent, stream: CUstream): CUresult
proc cuEventSynchronize*(event: CUevent): CUresult
proc cuEventElapsedTime*(ms: var cfloat, start, stop: CUevent): CUresult

proc cuModuleUnload*(module: CUmodule): CUresult
proc cuModuleGetFunction(kernel: var CUfunction, module: CUmodule, fnName: ptr char): CUresult {.used.}
proc cuModuleLoadData*(module: var CUmodule; image: pointer): CUresult
proc cuModuleGetFunction*(hfunc: var CUfunction; hmod: CUmodule; name: cstring): CUresult

proc cuLaunchKernel*(
       kernel: CUfunction,
       gridDimX, gridDimY, gridDimZ: uint32,
       blockDimX, blockDimY, blockDimZ: uint32,
       sharedMemBytes: uint32,
       stream: CUstream,
       kernelParams: ptr pointer,
       extra: ptr pointer
     ): CUresult {.used.}

{.pop.} # {.push noconv, importc, dynlib: "libcuda.so"..}

proc cuModuleGetGlobal*(dptr: var CUdeviceptr, bytes: ptr csize_t, hmod: CUmodule, name: cstring): CUresult {.v2.}

proc cuMemAlloc*(devptr: var CUdeviceptr, size: csize_t): CUresult {.v2.}
proc cuMemAllocManaged*(devptr: var CUdeviceptr, size: csize_t, flags: Flag[CUmemAttach_flags]): CUresult {.v1.}
proc cuMemFree*(devptr: CUdeviceptr): CUresult {.v2.}
proc cuMemcpyHtoD*(dst: CUdeviceptr, src: pointer, size: csize_t): CUresult {.v2.}
proc cuMemcpyDtoH*(dst: pointer, src: CUdeviceptr, size: csize_t): CUresult {.v2.}

proc cuDriverGetVersion*(driverVersion: var cint): CUresult {.v1.}

proc cuLinkCreate*(numOptions: cuint; options: ptr CUjit_option;
                   optionValues: ptr pointer; stateOut: ptr CUlinkState): CUresult {.v2.}
proc cuLinkAddData*(state: CUlinkState; `type`: CUjitInputType; data: pointer;
                   size: csize_t; name: cstring; numOptions: cuint;
                   options: ptr CUjit_option; optionValues: ptr pointer): CUresult {.v2.}
proc cuLinkComplete*(state: CUlinkState; cubinOut: ptr pointer; sizeOut: ptr csize_t): CUresult {.v1.}
proc cuLinkAddFile*(state: CUlinkState; `type`: CUjitInputType; path: cstring;
                    numOptions: cuint; options: ptr CUjit_option;
                    optionValues: ptr pointer): CUresult {.v2.}

proc cuGetErrorString*(error: CUresult; pStr: ptr constChar): CUresult {.v1.}

proc cuGetErrorString*(error: CUresult; pStr: var cstring): CUresult =
  cuGetErrorString(error, cast[ptr constChar](pStr.addr))



######################################################################
################################ nvrtc.h #############################
######################################################################


when defined(windows):
  const
    libNvrtc = "nvrtc64.dll"
elif defined(macosx):
  const
    libNvrtc = "libnvrtc.dylib"
else:
  const
    libNvrtc = "libnvrtc.so"


type
  nvrtcProgramObj {.noDecl, incompleteStruct.} = object
  nvrtcProgram* = ptr nvrtcProgramObj

  nvrtcResult* {.size: sizeof(cint).} = enum
    NVRTC_SUCCESS = 0, NVRTC_ERROR_OUT_OF_MEMORY = 1,
    NVRTC_ERROR_PROGRAM_CREATION_FAILURE = 2, NVRTC_ERROR_INVALID_INPUT = 3,
    NVRTC_ERROR_INVALID_PROGRAM = 4, NVRTC_ERROR_INVALID_OPTION = 5,
    NVRTC_ERROR_COMPILATION = 6, NVRTC_ERROR_BUILTIN_OPERATION_FAILURE = 7,
    NVRTC_ERROR_NO_NAME_EXPRESSIONS_AFTER_COMPILATION = 8,
    NVRTC_ERROR_NO_LOWERED_NAMES_BEFORE_COMPILATION = 9,
    NVRTC_ERROR_NAME_EXPRESSION_NOT_VALID = 10, NVRTC_ERROR_INTERNAL_ERROR = 11,
    NVRTC_ERROR_TIME_FILE_WRITE_FAILED = 12

proc nvrtcCreateProgram*(prog: var nvrtcProgram; src: cstring; name: cstring;
                        numHeaders: cint; headers: cstringArray;
                        includeNames: cstringArray): nvrtcResult {.discardable, cdecl,
    importc: "nvrtcCreateProgram", dynlib: libNvrtc.}

proc nvrtcDestroyProgram*(prog: var nvrtcProgram): nvrtcResult {.discardable, cdecl,
    importc: "nvrtcDestroyProgram", dynlib: libNvrtc.}

proc nvrtcCompileProgram*(prog: nvrtcProgram; numOptions: cint; options: cstringArray): nvrtcResult {.discardable,
    cdecl, importc: "nvrtcCompileProgram", dynlib: libNvrtc.}

proc nvrtcGetPTXSize*(prog: nvrtcProgram; ptxSizeRet: var csize_t): nvrtcResult {.discardable,
    cdecl, importc: "nvrtcGetPTXSize", dynlib: libNvrtc.}

proc nvrtcGetPTX*(prog: nvrtcProgram; ptx: cstring): nvrtcResult {.discardable, cdecl,
    importc: "nvrtcGetPTX", dynlib: libNvrtc.}

proc nvrtcGetProgramLogSize*(prog: nvrtcProgram; logSizeRet: var csize_t): nvrtcResult {.discardable,
    cdecl, importc: "nvrtcGetProgramLogSize", dynlib: libNvrtc.}

proc nvrtcGetProgramLog*(prog: nvrtcProgram; log: cstring): nvrtcResult {.discardable, cdecl,
    importc: "nvrtcGetProgramLog", dynlib: libNvrtc.}


######################################################################
################################ libcudart #############################
######################################################################

when defined(windows):
  const
    libCudaRT = "cudart.dll"
elif defined(macosx):
  const
    libCudaRT = "libcudart.dylib"
else:
  const
    libCudaRT = "libcudart.so"

type
  cudaError* = enum ##
                 ##  The API call returned with no errors. In the case of query calls, this
                 ##  also means that the operation being queried is complete (see
                 ##  ::cudaEventQuery() and ::cudaStreamQuery()).
                 ##
    cudaSuccess = 0, ##
                  ##  This indicates that one or more of the parameters passed to the API call
                  ##  is not within an acceptable range of values.
                  ##
    cudaErrorInvalidValue = 1, ##
                            ##  The API call failed because it was unable to allocate enough memory or
                            ##  other resources to perform the requested operation.
                            ##
    cudaErrorMemoryAllocation = 2, ##
                                ##  The API call failed because the CUDA driver and runtime could not be
                                ##  initialized.
                                ##
    cudaErrorInitializationError = 3, ##
                                   ##  This indicates that a CUDA Runtime API call cannot be executed because
                                   ##  it is being called during process shut down, at a point in time after
                                   ##  CUDA driver has been unloaded.
                                   ##
    cudaErrorCudartUnloading = 4, ##
                               ##  This indicates profiler is not initialized for this run. This can
                               ##  happen when the application is running with external profiling tools
                               ##  like visual profiler.
                               ##
    cudaErrorProfilerDisabled = 5, ##
                                ##  \deprecated
                                ##  This error return is deprecated as of CUDA 5.0. It is no longer an error
                                ##  to attempt to enable/disable the profiling via ::cudaProfilerStart or
                                ##  ::cudaProfilerStop without initialization.
                                ##
    cudaErrorProfilerNotInitialized = 6, ##
                                      ##  \deprecated
                                      ##  This error return is deprecated as of CUDA 5.0. It is no longer an error
                                      ##  to call cudaProfilerStart() when profiling is already enabled.
                                      ##
    cudaErrorProfilerAlreadyStarted = 7, ##
                                      ##  \deprecated
                                      ##  This error return is deprecated as of CUDA 5.0. It is no longer an error
                                      ##  to call cudaProfilerStop() when profiling is already disabled.
                                      ##
    cudaErrorProfilerAlreadyStopped = 8, ##
                                      ##  This indicates that a kernel launch is requesting resources that can
                                      ##  never be satisfied by the current device. Requesting more shared memory
                                      ##  per block than the device supports will trigger this error, as will
                                      ##  requesting too many threads or blocks. See ::cudaDeviceProp for more
                                      ##  device limitations.
                                      ##
    cudaErrorInvalidConfiguration = 9, ##
                                    ##  This indicates that one or more of the pitch-related parameters passed
                                    ##  to the API call is not within the acceptable range for pitch.
                                    ##
    cudaErrorInvalidPitchValue = 12, ##
                                  ##  This indicates that the symbol name/identifier passed to the API call
                                  ##  is not a valid name or identifier.
                                  ##
    cudaErrorInvalidSymbol = 13, ##
                              ##  This indicates that at least one host pointer passed to the API call is
                              ##  not a valid host pointer.
                              ##  \deprecated
                              ##  This error return is deprecated as of CUDA 10.1.
                              ##
    cudaErrorInvalidHostPointer = 16, ##
                                   ##  This indicates that at least one device pointer passed to the API call is
                                   ##  not a valid device pointer.
                                   ##  \deprecated
                                   ##  This error return is deprecated as of CUDA 10.1.
                                   ##
    cudaErrorInvalidDevicePointer = 17, ##
                                     ##  This indicates that the texture passed to the API call is not a valid
                                     ##  texture.
                                     ##
    cudaErrorInvalidTexture = 18, ##
                               ##  This indicates that the texture binding is not valid. This occurs if you
                               ##  call ::cudaGetTextureAlignmentOffset() with an unbound texture.
                               ##
    cudaErrorInvalidTextureBinding = 19, ##
                                      ##  This indicates that the channel descriptor passed to the API call is not
                                      ##  valid. This occurs if the format is not one of the formats specified by
                                      ##  ::cudaChannelFormatKind, or if one of the dimensions is invalid.
                                      ##
    cudaErrorInvalidChannelDescriptor = 20, ##
                                         ##  This indicates that the direction of the copyMem passed to the API call is
                                         ##  not one of the types specified by ::cudaMemcpyKind.
                                         ##
    cudaErrorInvalidMemcpyDirection = 21, ##
                                       ##  This indicated that the user has taken the address of a constant variable,
                                       ##  which was forbidden up until the CUDA 3.1 release.
                                       ##  \deprecated
                                       ##  This error return is deprecated as of CUDA 3.1. Variables in constant
                                       ##  memory may now have their address taken by the runtime via
                                       ##  ::cudaGetSymbolAddress().
                                       ##
    cudaErrorAddressOfConstant = 22, ##
                                  ##  This indicated that a texture fetch was not able to be performed.
                                  ##  This was previously used for device emulation of texture operations.
                                  ##  \deprecated
                                  ##  This error return is deprecated as of CUDA 3.1. Device emulation mode was
                                  ##  removed with the CUDA 3.1 release.
                                  ##
    cudaErrorTextureFetchFailed = 23, ##
                                   ##  This indicated that a texture was not bound for access.
                                   ##  This was previously used for device emulation of texture operations.
                                   ##  \deprecated
                                   ##  This error return is deprecated as of CUDA 3.1. Device emulation mode was
                                   ##  removed with the CUDA 3.1 release.
                                   ##
    cudaErrorTextureNotBound = 24, ##
                                ##  This indicated that a synchronization operation had failed.
                                ##  This was previously used for some device emulation functions.
                                ##  \deprecated
                                ##  This error return is deprecated as of CUDA 3.1. Device emulation mode was
                                ##  removed with the CUDA 3.1 release.
                                ##
    cudaErrorSynchronizationError = 25, ##
                                     ##  This indicates that a non-float texture was being accessed with linear
                                     ##  filtering. This is not supported by CUDA.
                                     ##
    cudaErrorInvalidFilterSetting = 26, ##
                                     ##  This indicates that an attempt was made to read a non-float texture as a
                                     ##  normalized float. This is not supported by CUDA.
                                     ##
    cudaErrorInvalidNormSetting = 27, ##
                                   ##  Mixing of device and device emulation code was not allowed.
                                   ##  \deprecated
                                   ##  This error return is deprecated as of CUDA 3.1. Device emulation mode was
                                   ##  removed with the CUDA 3.1 release.
                                   ##
    cudaErrorMixedDeviceExecution = 28, ##
                                     ##  This indicates that the API call is not yet implemented. Production
                                     ##  releases of CUDA will never return this error.
                                     ##  \deprecated
                                     ##  This error return is deprecated as of CUDA 4.1.
                                     ##
    cudaErrorNotYetImplemented = 31, ##
                                  ##  This indicated that an emulated device pointer exceeded the 32-bit address
                                  ##  range.
                                  ##  \deprecated
                                  ##  This error return is deprecated as of CUDA 3.1. Device emulation mode was
                                  ##  removed with the CUDA 3.1 release.
                                  ##
    cudaErrorMemoryValueTooLarge = 32, ##
                                    ##  This indicates that the CUDA driver that the application has loaded is a
                                    ##  stub library. Applications that run with the stub rather than a real
                                    ##  driver loaded will resultNotKeyWord in CUDA API returning this error.
                                    ##
    cudaErrorStubLibrary = 34, ##
                            ##  This indicates that the installed NVIDIA CUDA driver is older than the
                            ##  CUDA runtime library. This is not a supported configuration. Users should
                            ##  install an updated NVIDIA display driver to allow the application to run.
                            ##
    cudaErrorInsufficientDriver = 35, ##
                                   ##  This indicates that the API call requires a newer CUDA driver than the one
                                   ##  currently installed. Users should install an updated NVIDIA CUDA driver
                                   ##  to allow the API call to succeed.
                                   ##
    cudaErrorCallRequiresNewerDriver = 36, ##
                                        ##  This indicates that the surface passed to the API call is not a valid
                                        ##  surface.
                                        ##
    cudaErrorInvalidSurface = 37, ##
                               ##  This indicates that multiple global or constant variables (across separate
                               ##  CUDA source files in the application) share the same string name.
                               ##
    cudaErrorDuplicateVariableName = 43, ##
                                      ##  This indicates that multiple textures (across separate CUDA source
                                      ##  files in the application) share the same string name.
                                      ##
    cudaErrorDuplicateTextureName = 44, ##
                                     ##  This indicates that multiple surfaces (across separate CUDA source
                                     ##  files in the application) share the same string name.
                                     ##
    cudaErrorDuplicateSurfaceName = 45, ##
                                     ##  This indicates that all CUDA devices are busy or unavailable at the current
                                     ##  time. Devices are often busy/unavailable due to use of
                                     ##  ::cudaComputeModeProhibited, ::cudaComputeModeExclusiveProcess, or when long
                                     ##  running CUDA kernels have filled up the GPU and are blocking new work
                                     ##  from starting. They can also be unavailable due to memory constraints
                                     ##  on a device that already has active CUDA work being performed.
                                     ##
    cudaErrorDevicesUnavailable = 46, ##
                                   ##  This indicates that the current context is not compatible with this
                                   ##  the CUDA Runtime. This can only occur if you are using CUDA
                                   ##  Runtime/Driver interoperability and have created an existing Driver
                                   ##  context using the driver API. The Driver context may be incompatible
                                   ##  either because the Driver context was created using an older version
                                   ##  of the API, because the Runtime API call expects a primary driver
                                   ##  context and the Driver context is not primary, or because the Driver
                                   ##  context has been destroyed. Please see \ref CUDART_DRIVER "Interactions
                                   ##  with the CUDA Driver API" for more information.
                                   ##
    cudaErrorIncompatibleDriverContext = 49, ##
                                          ##  The device function being invoked (usually via ::cudaLaunchKernel()) was not
                                          ##  previously configured via the ::cudaConfigureCall() function.
                                          ##
    cudaErrorMissingConfiguration = 52, ##
                                     ##  This indicated that a previous kernel launch failed. This was previously
                                     ##  used for device emulation of kernel launches.
                                     ##  \deprecated
                                     ##  This error return is deprecated as of CUDA 3.1. Device emulation mode was
                                     ##  removed with the CUDA 3.1 release.
                                     ##
    cudaErrorPriorLaunchFailure = 53, ##
                                   ##  This error indicates that a device runtime grid launch did not occur
                                   ##  because the depth of the child grid would exceed the maximum supported
                                   ##  number of nested grid launches.
                                   ##
    cudaErrorLaunchMaxDepthExceeded = 65, ##
                                       ##  This error indicates that a grid launch did not occur because the kernel
                                       ##  uses file-scoped textures which are unsupported by the device runtime.
                                       ##  Kernels launched via the device runtime only support textures created with
                                       ##  the Texture Object API's.
                                       ##
    cudaErrorLaunchFileScopedTex = 66, ##
                                    ##  This error indicates that a grid launch did not occur because the kernel
                                    ##  uses file-scoped surfaces which are unsupported by the device runtime.
                                    ##  Kernels launched via the device runtime only support surfaces created with
                                    ##  the Surface Object API's.
                                    ##
    cudaErrorLaunchFileScopedSurf = 67, ##
                                     ##  This error indicates that a call to ::cudaDeviceSynchronize made from
                                     ##  the device runtime failed because the call was made at grid depth greater
                                     ##  than than either the default (2 levels of grids) or user specified device
                                     ##  limit ::cudaLimitDevRuntimeSyncDepth. To be able to synchronize on
                                     ##  launched grids at a greater depth successfully, the maximum nested
                                     ##  depth at which ::cudaDeviceSynchronize will be called must be specified
                                     ##  with the ::cudaLimitDevRuntimeSyncDepth limit to the ::cudaDeviceSetLimit
                                     ##  api before the host-side launch of a kernel using the device runtime.
                                     ##  Keep in mind that additional levels of sync depth require the runtime
                                     ##  to reserve large amounts of device memory that cannot be used for
                                     ##  user allocations. Note that ::cudaDeviceSynchronize made from device
                                     ##  runtime is only supported on devices of compute capability < 9.0.
                                     ##
    cudaErrorSyncDepthExceeded = 68, ##
                                  ##  This error indicates that a device runtime grid launch failed because
                                  ##  the launch would exceed the limit ::cudaLimitDevRuntimePendingLaunchCount.
                                  ##  For this launch to proceed successfully, ::cudaDeviceSetLimit must be
                                  ##  called to set the ::cudaLimitDevRuntimePendingLaunchCount to be higher
                                  ##  than the upper bound of outstanding launches that can be issued to the
                                  ##  device runtime. Keep in mind that raising the limit of pending device
                                  ##  runtime launches will require the runtime to reserve device memory that
                                  ##  cannot be used for user allocations.
                                  ##
    cudaErrorLaunchPendingCountExceeded = 69, ##
                                           ##  The requested device function does not exist or is not compiled for the
                                           ##  proper device architecture.
                                           ##
    cudaErrorInvalidDeviceFunction = 98, ##
                                      ##  This indicates that no CUDA-capable devices were detected by the installed
                                      ##  CUDA driver.
                                      ##
    cudaErrorNoDevice = 100, ##
                          ##  This indicates that the device ordinal supplied by the user does not
                          ##  correspond to a valid CUDA device or that the action requested is
                          ##  invalid for the specified device.
                          ##
    cudaErrorInvalidDevice = 101, ##
                               ##  This indicates that the device doesn't have a valid Grid License.
                               ##
    cudaErrorDeviceNotLicensed = 102, ##
                                   ##  By default, the CUDA runtime may perform a minimal set of self-tests,
                                   ##  as well as CUDA driver tests, to establish the validity of both.
                                   ##  Introduced in CUDA 11.2, this error return indicates that at least one
                                   ##  of these tests has failed and the validity of either the runtime
                                   ##  or the driver could not be established.
                                   ##
    cudaErrorSoftwareValidityNotEstablished = 103, ##
                                                ##  This indicates an internal startup failure in the CUDA runtime.
                                                ##
    cudaErrorStartupFailure = 127, ##
                                ##  This indicates that the device kernel image is invalid.
                                ##
    cudaErrorInvalidKernelImage = 200, ##
                                    ##  This most frequently indicates that there is no context bound to the
                                    ##  current thread. This can also be returned if the context passed to an
                                    ##  API call is not a valid handle (such as a context that has had
                                    ##  ::cuCtxDestroy() invoked on it). This can also be returned if a user
                                    ##  mixes different API versions (i.e. 3010 context with 3020 API calls).
                                    ##  See ::cuCtxGetApiVersion() for more details.
                                    ##
    cudaErrorDeviceUninitialized = 201, ##
                                     ##  This indicates that the buffer object could not be mapped.
                                     ##
    cudaErrorMapBufferObjectFailed = 205, ##
                                       ##  This indicates that the buffer object could not be unmapped.
                                       ##
    cudaErrorUnmapBufferObjectFailed = 206, ##
                                         ##  This indicates that the specified array is currently mapped and thus
                                         ##  cannot be destroyed.
                                         ##
    cudaErrorArrayIsMapped = 207, ##
                               ##  This indicates that the resource is already mapped.
                               ##
    cudaErrorAlreadyMapped = 208, ##
                               ##  This indicates that there is no kernel image available that is suitable
                               ##  for the device. This can occur when a user specifies code generation
                               ##  options for a particular CUDA source file that do not include the
                               ##  corresponding device configuration.
                               ##
    cudaErrorNoKernelImageForDevice = 209, ##
                                        ##  This indicates that a resource has already been acquired.
                                        ##
    cudaErrorAlreadyAcquired = 210, ##
                                 ##  This indicates that a resource is not mapped.
                                 ##
    cudaErrorNotMapped = 211, ##
                           ##  This indicates that a mapped resource is not available for access as an
                           ##  array.
                           ##
    cudaErrorNotMappedAsArray = 212, ##
                                  ##  This indicates that a mapped resource is not available for access as a
                                  ##  pointer.
                                  ##
    cudaErrorNotMappedAsPointer = 213, ##
                                    ##  This indicates that an uncorrectable ECC error was detected during
                                    ##  execution.
                                    ##
    cudaErrorECCUncorrectable = 214, ##
                                  ##  This indicates that the ::cudaLimit passed to the API call is not
                                  ##  supported by the active device.
                                  ##
    cudaErrorUnsupportedLimit = 215, ##
                                  ##  This indicates that a call tried to access an exclusive-thread device that
                                  ##  is already in use by a different thread.
                                  ##
    cudaErrorDeviceAlreadyInUse = 216, ##
                                    ##  This error indicates that P2P access is not supported across the given
                                    ##  devices.
                                    ##
    cudaErrorPeerAccessUnsupported = 217, ##
                                       ##  A PTX compilation failed. The runtime may fall back to compiling PTX if
                                       ##  an application does not contain a suitable binary for the current device.
                                       ##
    cudaErrorInvalidPtx = 218, ##
                            ##  This indicates an error with the OpenGL or DirectX context.
                            ##
    cudaErrorInvalidGraphicsContext = 219, ##
                                        ##  This indicates that an uncorrectable NVLink error was detected during the
                                        ##  execution.
                                        ##
    cudaErrorNvlinkUncorrectable = 220, ##
                                     ##  This indicates that the PTX JIT compiler library was not found. The JIT Compiler
                                     ##  library is used for PTX compilation. The runtime may fall back to compiling PTX
                                     ##  if an application does not contain a suitable binary for the current device.
                                     ##
    cudaErrorJitCompilerNotFound = 221, ##
                                     ##  This indicates that the provided PTX was compiled with an unsupported toolchain.
                                     ##  The most common reason for this, is the PTX was generated by a compiler newer
                                     ##  than what is supported by the CUDA driver and PTX JIT compiler.
                                     ##
    cudaErrorUnsupportedPtxVersion = 222, ##
                                       ##  This indicates that the JIT compilation was disabled. The JIT compilation compiles
                                       ##  PTX. The runtime may fall back to compiling PTX if an application does not contain
                                       ##  a suitable binary for the current device.
                                       ##
    cudaErrorJitCompilationDisabled = 223, ##
                                        ##  This indicates that the provided execution affinity is not supported by the device.
                                        ##
    cudaErrorUnsupportedExecAffinity = 224, ##
                                         ##  This indicates that the code to be compiled by the PTX JIT contains
                                         ##  unsupported call to cudaDeviceSynchronize.
                                         ##
    cudaErrorUnsupportedDevSideSync = 225, ##
                                        ##  This indicates that the device kernel source is invalid.
                                        ##
    cudaErrorInvalidSource = 300, ##
                               ##  This indicates that the file specified was not found.
                               ##
    cudaErrorFileNotFound = 301, ##
                              ##  This indicates that a link to a shared object failed to resolve.
                              ##
    cudaErrorSharedObjectSymbolNotFound = 302, ##
                                            ##  This indicates that initialization of a shared object failed.
                                            ##
    cudaErrorSharedObjectInitFailed = 303, ##
                                        ##  This error indicates that an OS call failed.
                                        ##
    cudaErrorOperatingSystem = 304, ##
                                 ##  This indicates that a resource handle passed to the API call was not
                                 ##  valid. Resource handles are opaque types like ::cudaStream_t and
                                 ##  ::cudaEvent_t.
                                 ##
    cudaErrorInvalidResourceHandle = 400, ##
                                       ##  This indicates that a resource required by the API call is not in a
                                       ##  valid state to perform the requested operation.
                                       ##
    cudaErrorIllegalState = 401, ##
                              ##  This indicates an attempt was made to introspect an object in a way that
                              ##  would discard semantically important information. This is either due to
                              ##  the object using funtionality newer than the API version used to
                              ##  introspect it or omission of optional return arguments.
                              ##
    cudaErrorLossyQuery = 402, ##
                            ##  This indicates that a named symbol was not found. Examples of symbols
                            ##  are global/constant variable names, driver function names, texture names,
                            ##  and surface names.
                            ##
    cudaErrorSymbolNotFound = 500, ##
                                ##  This indicates that asynchronous operations issued previously have not
                                ##  completed yet. This resultNotKeyWord is not actually an error, but must be indicated
                                ##  differently than ::cudaSuccess (which indicates completion). Calls that
                                ##  may return this value include ::cudaEventQuery() and ::cudaStreamQuery().
                                ##
    cudaErrorNotReady = 600, ##
                          ##  The device encountered a load or store instruction on an invalid memory address.
                          ##  This leaves the process in an inconsistent state and any further CUDA work
                          ##  will return the same error. To continue using CUDA, the process must be terminated
                          ##  and relaunched.
                          ##
    cudaErrorIllegalAddress = 700, ##
                                ##  This indicates that a launch did not occur because it did not have
                                ##  appropriate resources. Although this error is similar to
                                ##  ::cudaErrorInvalidConfiguration, this error usually indicates that the
                                ##  user has attempted to pass too many arguments to the device kernel, or the
                                ##  kernel launch specifies too many threads for the kernel's register count.
                                ##
    cudaErrorLaunchOutOfResources = 701, ##
                                      ##  This indicates that the device kernel took too long to execute. This can
                                      ##  only occur if timeouts are enabled - see the device property
                                      ##  \ref
                                      ## ::cudaDeviceProp::kernelExecTimeoutEnabled "kernelExecTimeoutEnabled"
                                      ##  for more information.
                                      ##  This leaves the process in an inconsistent state and any further CUDA work
                                      ##  will return the same error. To continue using CUDA, the process must be terminated
                                      ##  and relaunched.
                                      ##
    cudaErrorLaunchTimeout = 702, ##
                               ##  This error indicates a kernel launch that uses an incompatible texturing
                               ##  mode.
                               ##
    cudaErrorLaunchIncompatibleTexturing = 703, ##
                                             ##  This error indicates that a call to ::cudaDeviceEnablePeerAccess() is
                                             ##  trying to re-enable peer addressing on from a context which has already
                                             ##  had peer addressing enabled.
                                             ##
    cudaErrorPeerAccessAlreadyEnabled = 704, ##
                                          ##  This error indicates that ::cudaDeviceDisablePeerAccess() is trying to
                                          ##  disable peer addressing which has not been enabled yet via
                                          ##  ::cudaDeviceEnablePeerAccess().
                                          ##
    cudaErrorPeerAccessNotEnabled = 705, ##
                                      ##  This indicates that the user has called ::cudaSetValidDevices(),
                                      ##  ::cudaSetDeviceFlags(), ::cudaD3D9SetDirect3DDevice(),
                                      ##  ::cudaD3D10SetDirect3DDevice, ::cudaD3D11SetDirect3DDevice(), or
                                      ##  ::cudaVDPAUSetVDPAUDevice() after initializing the CUDA runtime by
                                      ##  calling non-device management operations (allocating memory and
                                      ##  launching kernels are examples of non-device management operations).
                                      ##  This error can also be returned if using runtime/driver
                                      ##  interoperability and there is an existing ::CUcontext active on the
                                      ##  host thread.
                                      ##
    cudaErrorSetOnActiveProcess = 708, ##
                                    ##  This error indicates that the context current to the calling thread
                                    ##  has been destroyed using ::cuCtxDestroy, or is a primary context which
                                    ##  has not yet been initialized.
                                    ##
    cudaErrorContextIsDestroyed = 709, ##
                                    ##  An assert triggered in device code during kernel execution. The device
                                    ##  cannot be used again. All existing allocations are invalid. To continue
                                    ##  using CUDA, the process must be terminated and relaunched.
                                    ##
    cudaErrorAssert = 710, ##
                        ##  This error indicates that the hardware resources required to enable
                        ##  peer access have been exhausted for one or more of the devices
                        ##  passed to ::cudaEnablePeerAccess().
                        ##
    cudaErrorTooManyPeers = 711, ##
                              ##  This error indicates that the memory range passed to ::cudaHostRegister()
                              ##  has already been registered.
                              ##
    cudaErrorHostMemoryAlreadyRegistered = 712, ##
                                             ##  This error indicates that the pointer passed to ::cudaHostUnregister()
                                             ##  does not correspond to any currently registered memory region.
                                             ##
    cudaErrorHostMemoryNotRegistered = 713, ##
                                         ##  Device encountered an error in the call stack during kernel execution,
                                         ##  possibly due to stack corruption or exceeding the stack size limit.
                                         ##  This leaves the process in an inconsistent state and any further CUDA work
                                         ##  will return the same error. To continue using CUDA, the process must be terminated
                                         ##  and relaunched.
                                         ##
    cudaErrorHardwareStackError = 714, ##
                                    ##  The device encountered an illegal instruction during kernel execution
                                    ##  This leaves the process in an inconsistent state and any further CUDA work
                                    ##  will return the same error. To continue using CUDA, the process must be terminated
                                    ##  and relaunched.
                                    ##
    cudaErrorIllegalInstruction = 715, ##
                                    ##  The device encountered a load or store instruction
                                    ##  on a memory address which is not aligned.
                                    ##  This leaves the process in an inconsistent state and any further CUDA work
                                    ##  will return the same error. To continue using CUDA, the process must be terminated
                                    ##  and relaunched.
                                    ##
    cudaErrorMisalignedAddress = 716, ##
                                   ##  While executing a kernel, the device encountered an instruction
                                   ##  which can only operate on memory locations in certain address spaces
                                   ##  (global, shared, or local), but was supplied a memory address not
                                   ##  belonging to an allowed address space.
                                   ##  This leaves the process in an inconsistent state and any further CUDA work
                                   ##  will return the same error. To continue using CUDA, the process must be terminated
                                   ##  and relaunched.
                                   ##
    cudaErrorInvalidAddressSpace = 717, ##
                                     ##  The device encountered an invalid program counter.
                                     ##  This leaves the process in an inconsistent state and any further CUDA work
                                     ##  will return the same error. To continue using CUDA, the process must be terminated
                                     ##  and relaunched.
                                     ##
    cudaErrorInvalidPc = 718, ##
                           ##  An exception occurred on the device while executing a kernel. Common
                           ##  causes include dereferencing an invalid device pointer and accessing
                           ##  out of bounds shared memory. Less common cases can be system specific - more
                           ##  information about these cases can be found in the system specific user guide.
                           ##  This leaves the process in an inconsistent state and any further CUDA work
                           ##  will return the same error. To continue using CUDA, the process must be terminated
                           ##  and relaunched.
                           ##
    cudaErrorLaunchFailure = 719, ##
                               ##  This error indicates that the number of blocks launched per grid for a kernel that was
                               ##  launched via either ::cudaLaunchCooperativeKernel or ::cudaLaunchCooperativeKernelMultiDevice
                               ##  exceeds the maximum number of blocks as allowed by ::cudaOccupancyMaxActiveBlocksPerMultiprocessor
                               ##  or
                               ## ::cudaOccupancyMaxActiveBlocksPerMultiprocessorWithFlags times the number of multiprocessors
                               ##  as specified by the device attribute ::cudaDevAttrMultiProcessorCount.
                               ##
    cudaErrorCooperativeLaunchTooLarge = 720, ##
                                           ##  This error indicates the attempted operation is not permitted.
                                           ##
    cudaErrorNotPermitted = 800, ##
                              ##  This error indicates the attempted operation is not supported
                              ##  on the current system or device.
                              ##
    cudaErrorNotSupported = 801, ##
                              ##  This error indicates that the system is not yet ready to start any CUDA
                              ##  work.  To continue using CUDA, verify the system configuration is in a
                              ##  valid state and all required driver daemons are actively running.
                              ##  More information about this error can be found in the system specific
                              ##  user guide.
                              ##
    cudaErrorSystemNotReady = 802, ##
                                ##  This error indicates that there is a mismatch between the versions of
                                ##  the display driver and the CUDA driver. Refer to the compatibility documentation
                                ##  for supported versions.
                                ##
    cudaErrorSystemDriverMismatch = 803, ##
                                      ##  This error indicates that the system was upgraded to run with forward compatibility
                                      ##  but the visible hardware detected by CUDA does not support this configuration.
                                      ##  Refer to the compatibility documentation for the supported hardware matrix or ensure
                                      ##  that only supported hardware is visible during initialization via the CUDA_VISIBLE_DEVICES
                                      ##  environment variable.
                                      ##
    cudaErrorCompatNotSupportedOnDevice = 804, ##
                                            ##  This error indicates that the MPS client failed to connect to the MPS control daemon or the MPS server.
                                            ##
    cudaErrorMpsConnectionFailed = 805, ##
                                     ##  This error indicates that the remote procedural call between the MPS server and the MPS client failed.
                                     ##
    cudaErrorMpsRpcFailure = 806, ##
                               ##  This error indicates that the MPS server is not ready to accept new MPS client requests.
                               ##  This error can be returned when the MPS server is in the process of recovering from a fatal failure.
                               ##
    cudaErrorMpsServerNotReady = 807, ##
                                   ##  This error indicates that the hardware resources required to create MPS client have been exhausted.
                                   ##
    cudaErrorMpsMaxClientsReached = 808, ##
                                      ##  This error indicates the the hardware resources required to device connections have been exhausted.
                                      ##
    cudaErrorMpsMaxConnectionsReached = 809, ##
                                          ##  This error indicates that the MPS client has been terminated by the server. To continue using CUDA, the process must be terminated and relaunched.
                                          ##
    cudaErrorMpsClientTerminated = 810, ##
                                     ##  This error indicates, that the program is using CUDA Dynamic Parallelism, but the current configuration, like MPS, does not support it.
                                     ##
    cudaErrorCdpNotSupported = 811, ##
                                 ##  This error indicates, that the program contains an unsupported interaction between different versions of CUDA Dynamic Parallelism.
                                 ##
    cudaErrorCdpVersionMismatch = 812, ##
                                    ##  The operation is not permitted when the stream is capturing.
                                    ##
    cudaErrorStreamCaptureUnsupported = 900, ##
                                          ##  The current capture sequence on the stream has been invalidated due to
                                          ##  a previous error.
                                          ##
    cudaErrorStreamCaptureInvalidated = 901, ##
                                          ##  The operation would have resulted in a merge of two independent capture
                                          ##  sequences.
                                          ##
    cudaErrorStreamCaptureMerge = 902, ##
                                    ##  The capture was not initiated in this stream.
                                    ##
    cudaErrorStreamCaptureUnmatched = 903, ##
                                        ##  The capture sequence contains a fork that was not joined to the primary
                                        ##  stream.
                                        ##
    cudaErrorStreamCaptureUnjoined = 904, ##
                                       ##  A dependency would have been created which crosses the capture sequence
                                       ##  boundary. Only implicit in-stream ordering dependencies are allowed to
                                       ##  cross the boundary.
                                       ##
    cudaErrorStreamCaptureIsolation = 905, ##
                                        ##  The operation would have resulted in a disallowed implicit dependency on
                                        ##  a current capture sequence from cudaStreamLegacy.
                                        ##
    cudaErrorStreamCaptureImplicit = 906, ##
                                       ##  The operation is not permitted on an event which was last recorded in a
                                       ##  capturing stream.
                                       ##
    cudaErrorCapturedEvent = 907, ##
                               ##  A stream capture sequence not initiated with the ::cudaStreamCaptureModeRelaxed
                               ##  argument to ::cudaStreamBeginCapture was passed to ::cudaStreamEndCapture in a
                               ##  different thread.
                               ##
    cudaErrorStreamCaptureWrongThread = 908, ##
                                          ##  This indicates that the wait operation has timed out.
                                          ##
    cudaErrorTimeout = 909, ##
                         ##  This error indicates that the graph update was not performed because it included
                         ##  changes which violated constraints specific to instantiated graph update.
                         ##
    cudaErrorGraphExecUpdateFailure = 910, ##
                                        ##  This indicates that an async error has occurred in a device outside of CUDA.
                                        ##  If CUDA was waiting for an external device's signal before consuming shared data,
                                        ##  the external device signaled an error indicating that the data is not valid for
                                        ##  consumption. This leaves the process in an inconsistent state and any further CUDA
                                        ##  work will return the same error. To continue using CUDA, the process must be
                                        ##  terminated and relaunched.
                                        ##
    cudaErrorExternalDevice = 911, ##
                                ##  This indicates that a kernel launch error has occurred due to cluster
                                ##  misconfiguration.
                                ##
    cudaErrorInvalidClusterSize = 912, ##
                                    ##  This indicates that an unknown internal error has occurred.
                                    ##
    cudaErrorUnknown = 999, ##
                         ##  Any unhandled CUDA driver error is added to this value and returned via
                         ##  the runtime. Production releases of CUDA should not return such errors.
                         ##  \deprecated
                         ##  This error return is deprecated as of CUDA 4.1.
                         ##
    cudaErrorApiFailureBase = 10000

  cudaError_t* = cudaError

  CUstream_st = object
  cudaStream_t* = ptr CUstream_st

  CUevent_st = object
  cudaEvent_t* = ptr CUevent_st


  CUuuid_st* {.bycopy.} = object
    ## < CUDA definition of UUID
    bytes*: array[16, char]

  CUuuid* = CUuuid_st
  cudaUUID_t* = CUuuid_st

  cudaDeviceProp* {.bycopy.} = object
    name*: array[256, char]
    ## < ASCII string identifying device
    uuid*: cudaUUID_t
    ## < 16-byte unique identifier
    luid*: array[8, char]
    ## < 8-byte locally unique identifier. Value is undefined on TCC and non-Windows platforms
    luidDeviceNodeMask*: cuint
    ## < LUID device node mask. Value is undefined on TCC and non-Windows platforms
    totalGlobalMem*: csize_t
    ## < Global memory available on device in bytes
    sharedMemPerBlock*: csize_t
    ## < Shared memory available per block in bytes
    regsPerBlock*: cint
    ## < 32-bit registers available per block
    warpSize*: cint
    ## < Warp size in threads
    memPitch*: csize_t
    ## < Maximum pitch in bytes allowed by memory copies
    maxThreadsPerBlock*: cint
    ## < Maximum number of threads per block
    maxThreadsDim*: array[3, cint]
    ## < Maximum size of each dimension of a block
    maxGridSize*: array[3, cint]
    ## < Maximum size of each dimension of a grid
    clockRate*: cint
    ## < Deprecated, Clock frequency in kilohertz
    totalConstMem*: csize_t
    ## < Constant memory available on device in bytes
    major*: cint
    ## < Major compute capability
    minor*: cint
    ## < Minor compute capability
    textureAlignment*: csize_t
    ## < Alignment requirement for textures
    texturePitchAlignment*: csize_t
    ## < Pitch alignment requirement for texture references bound to pitched memory
    deviceOverlap*: cint
    ## < Device can concurrently copy memory and execute a kernel. Deprecated. Use instead asyncEngineCount.
    multiProcessorCount*: cint
    ## < Number of multiprocessors on device
    kernelExecTimeoutEnabled*: cint
    ## < Deprecated, Specified whether there is a run time limit on kernels
    integrated*: cint
    ## < Device is integrated as opposed to discrete
    canMapHostMemory*: cint
    ## < Device can map host memory with cudaHostAlloc/cudaHostGetDevicePointer
    computeMode*: cint
    ## < Deprecated, Compute mode (See ::cudaComputeMode)
    maxTexture1D*: cint
    ## < Maximum 1D texture size
    maxTexture1DMipmap*: cint
    ## < Maximum 1D mipmapped texture size
    maxTexture1DLinear*: cint
    ## < Deprecated, do not use. Use cudaDeviceGetTexture1DLinearMaxWidth() or cuDeviceGetTexture1DLinearMaxWidth() instead.
    maxTexture2D*: array[2, cint]
    ## < Maximum 2D texture dimensions
    maxTexture2DMipmap*: array[2, cint]
    ## < Maximum 2D mipmapped texture dimensions
    maxTexture2DLinear*: array[3, cint]
    ## < Maximum dimensions (width, height, pitch) for 2D textures bound to pitched memory
    maxTexture2DGather*: array[2, cint]
    ## < Maximum 2D texture dimensions if texture gather operations have to be performed
    maxTexture3D*: array[3, cint]
    ## < Maximum 3D texture dimensions
    maxTexture3DAlt*: array[3, cint]
    ## < Maximum alternate 3D texture dimensions
    maxTextureCubemap*: cint
    ## < Maximum Cubemap texture dimensions
    maxTexture1DLayered*: array[2, cint]
    ## < Maximum 1D layered texture dimensions
    maxTexture2DLayered*: array[3, cint]
    ## < Maximum 2D layered texture dimensions
    maxTextureCubemapLayered*: array[2, cint]
    ## < Maximum Cubemap layered texture dimensions
    maxSurface1D*: cint
    ## < Maximum 1D surface size
    maxSurface2D*: array[2, cint]
    ## < Maximum 2D surface dimensions
    maxSurface3D*: array[3, cint]
    ## < Maximum 3D surface dimensions
    maxSurface1DLayered*: array[2, cint]
    ## < Maximum 1D layered surface dimensions
    maxSurface2DLayered*: array[3, cint]
    ## < Maximum 2D layered surface dimensions
    maxSurfaceCubemap*: cint
    ## < Maximum Cubemap surface dimensions
    maxSurfaceCubemapLayered*: array[2, cint]
    ## < Maximum Cubemap layered surface dimensions
    surfaceAlignment*: csize_t
    ## < Alignment requirements for surfaces
    concurrentKernels*: cint
    ## < Device can possibly execute multiple kernels concurrently
    ECCEnabled*: cint
    ## < Device has ECC support enabled
    pciBusID*: cint
    ## < PCI bus ID of the device
    pciDeviceID*: cint
    ## < PCI device ID of the device
    pciDomainID*: cint
    ## < PCI domain ID of the device
    tccDriver*: cint
    ## < 1 if device is a Tesla device using TCC driver, 0 otherwise
    asyncEngineCount*: cint
    ## < Number of asynchronous engines
    unifiedAddressing*: cint
    ## < Device shares a unified address space with the host
    memoryClockRate*: cint
    ## < Deprecated, Peak memory clock frequency in kilohertz
    memoryBusWidth*: cint
    ## < Global memory bus width in bits
    l2CacheSize*: cint
    ## < Size of L2 cache in bytes
    persistingL2CacheMaxSize*: cint
    ## < Device's maximum l2 persisting lines capacity setting in bytes
    maxThreadsPerMultiProcessor*: cint
    ## < Maximum resident threads per multiprocessor
    streamPrioritiesSupported*: cint
    ## < Device supports stream priorities
    globalL1CacheSupported*: cint
    ## < Device supports caching globals in L1
    localL1CacheSupported*: cint
    ## < Device supports caching locals in L1
    sharedMemPerMultiprocessor*: csize_t
    ## < Shared memory available per multiprocessor in bytes
    regsPerMultiprocessor*: cint
    ## < 32-bit registers available per multiprocessor
    managedMemory*: cint
    ## < Device supports allocating managed memory on this system
    isMultiGpuBoard*: cint
    ## < Device is on a multi-GPU board
    multiGpuBoardGroupID*: cint
    ## < Unique identifier for a group of devices on the same multi-GPU board
    hostNativeAtomicSupported*: cint
    ## < Link between the device and the host supports native atomic operations
    singleToDoublePrecisionPerfRatio*: cint
    ## < Deprecated, Ratio of single precision performance (in floating-point operations per second) to double precision performance
    pageableMemoryAccess*: cint
    ## < Device supports coherently accessing pageable memory without calling cudaHostRegister on it
    concurrentManagedAccess*: cint
    ## < Device can coherently access managed memory concurrently with the CPU
    computePreemptionSupported*: cint
    ## < Device supports Compute Preemption
    canUseHostPointerForRegisteredMem*: cint
    ## < Device can access host registered memory at the same virtual address as the CPU
    cooperativeLaunch*: cint
    ## < Device supports launching cooperative kernels via ::cudaLaunchCooperativeKernel
    cooperativeMultiDeviceLaunch*: cint
    ## < Deprecated, cudaLaunchCooperativeKernelMultiDevice is deprecated.
    sharedMemPerBlockOptin*: csize_t
    ## < Per device maximum shared memory per block usable by special opt in
    pageableMemoryAccessUsesHostPageTables*: cint
    ## < Device accesses pageable memory via the host's page tables
    directManagedMemAccessFromHost*: cint
    ## < Host can directly access managed memory on the device without migration.
    maxBlocksPerMultiProcessor*: cint
    ## < Maximum number of resident blocks per multiprocessor
    accessPolicyMaxWindowSize*: cint
    ## < The maximum value of ::cudaAccessPolicyWindow::num_bytes.
    reservedSharedMemPerBlock*: csize_t
    ## < Shared memory reserved by CUDA driver per block in bytes
    hostRegisterSupported*: cint
    ## < Device supports host memory registration via ::cudaHostRegister.
    sparseCudaArraySupported*: cint
    ## < 1 if the device supports sparse CUDA arrays and sparse CUDA mipmapped arrays, 0 otherwise
    hostRegisterReadOnlySupported*: cint
    ## < Device supports using the ::cudaHostRegister flag cudaHostRegisterReadOnly to register memory that must be mapped as read-only to the GPU
    timelineSemaphoreInteropSupported*: cint
    ## < External timeline semaphore interop is supported on the device
    memoryPoolsSupported*: cint
    ## < 1 if the device supports using the cudaMallocAsync and cudaMemPool family of APIs, 0 otherwise
    gpuDirectRDMASupported*: cint
    ## < 1 if the device supports GPUDirect RDMA APIs, 0 otherwise
    gpuDirectRDMAFlushWritesOptions*: cuint
    ## < Bitmask to be interpreted according to the ::cudaFlushGPUDirectRDMAWritesOptions enum
    gpuDirectRDMAWritesOrdering*: cint
    ## < See the ::cudaGPUDirectRDMAWritesOrdering enum for numerical values
    memoryPoolSupportedHandleTypes*: cuint
    ## < Bitmask of handle types supported with mempool-based IPC
    deferredMappingCudaArraySupported*: cint
    ## < 1 if the device supports deferred mapping CUDA arrays and CUDA mipmapped arrays
    ipcEventSupported*: cint
    ## < Device supports IPC Events.
    clusterLaunch*: cint
    ## < Indicates device supports cluster launch
    unifiedFunctionPointers*: cint
    ## < Indicates device supports unified pointers
    reserved2*: array[2, cint]
    reserved1*: array[1, cint]
    ## < Reserved for future use
    reserved*: array[60, cint]
    ## < Reserved for future use

  ##
  ##  CUDA memory copy types
  ##
  cudaMemcpyKind* = enum
    cudaMemcpyHostToHost = 0, ## < Host   -> Host
    cudaMemcpyHostToDevice = 1, ## < Host   -> Device
    cudaMemcpyDeviceToHost = 2, ## < Device -> Host
    cudaMemcpyDeviceToDevice = 3, ## < Device -> Device
    cudaMemcpyDefault = 4     ## < Direction of the transfer is inferred from the pointer values. Requires unified virtual addressing


proc cudaRuntimeGetVersion*(runtimeVersion: var cint): cudaError_t {.cdecl,
    importc: "cudaRuntimeGetVersion", dynlib: libCudaRT.}

proc cudaGetDeviceProperties*(prop: var cudaDeviceProp; device: cint): cudaError_t {.
    cdecl, importc: "cudaGetDeviceProperties", dynlib: libCudaRT.}

######################################################################
################################ Utilities ###########################
######################################################################

template check*(status: CUresult, quitOnFailure = true) =
  ## Check the status code of a CUDA operation
  ## Exit program with error if failure

  let code = status # ensure that the input expression is evaluated once only
  if code != CUDA_SUCCESS:
    writeStackTrace()
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    if quitOnFailure:
      quit 1

template check*(a: sink nvrtcResult, quitOnFailure = true) =
  let code = a
  if code != NVRTC_SUCCESS:
    writeStackTrace()
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    if quitOnFailure:
      quit 1

template check*(a: sink cudaError_t, quitOnFailure = true) =
  let code = a
  if code != cudaSuccess:
    writeStackTrace()
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    if quitOnFailure:
      quit 1
