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

static: echo "[Constantine] Using library libcuda.so"
{.passl: "-L/opt/cuda/lib64 -lcuda".}

# Cuda offers 2 APIs:
# - cuda.h               the driver API
# - cuda_runtime.h       the runtime API
#
# https://docs.nvidia.com/cuda/cuda-runtime-api/driver-vs-runtime-api.html
#
# We need to use the lower-level driver API for JIT modules loading and reloading

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
  CUcontext* = distinct pointer
  CUmodule* = distinct pointer
  CUfunction* = distinct pointer
  CUstream* = distinct pointer
  CUdeviceptr* = distinct pointer

{.push noconv, importc, dynlib: "libcuda.so".}

proc cuInit*(flags: uint32): CUresult

proc cuDeviceGetCount*(count: var int32): CUresult
proc cuDeviceGet*(device: var CUdevice, ordinal: int32): CUresult
proc cuDeviceGetName*(name: ptr char, len: int32, dev: CUdevice): CUresult
proc cuDeviceGetAttribute*(r: var int32, attrib: CUdevice_attribute, dev: CUdevice): CUresult

proc cuCtxCreate*(pctx: var CUcontext, flags: uint32, dev: CUdevice): CUresult
proc cuCtxDestroy*(ctx: CUcontext): CUresult
proc cuCtxSynchronize*(ctx: CUcontext): CUresult

proc cuModuleLoadData(module: var CUmodule, sourceCode: ptr char): CUresult {.used.}
proc cuModuleUnload*(module: CUmodule): CUresult
proc cuModuleGetFunction(kernel: var CUfunction, module: CUmodule, fnName: ptr char): CUresult {.used.}

proc cuLaunchKernel(
       kernel: CUfunction,
       gridDimX, gridDimY, gridDimZ: uint32,
       blockDimX, blockDimY, blockDimZ: uint32,
       sharedMemBytes: uint32,
       stream: CUstream,
       kernelParams: ptr pointer,
       extra: ptr pointer
     ): CUresult {.used.}

proc cuMemAlloc*(devptr: var CUdeviceptr, size: csize_t): CUresult
proc cuMemAllocManaged*(devptr: var CUdeviceptr, size: csize_t, flags: Flag[CUmemAttach_flags]): CUresult
proc cuMemFree*(devptr: CUdeviceptr): CUresult
proc cuMemcpyHtoD*(dst: CUdeviceptr, src: pointer, size: csize_t): CUresult
proc cuMemcpyDtoH*(dst: pointer, src: CUdeviceptr, size: csize_t): CUresult

{.pop.} # {.push noconv, importc, dynlib: "libcuda.so".}
