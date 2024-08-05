# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#               Bindings to AMD GPUs libraries
#
# ############################################################

import ./c_abi

# ############################################################
#
#                         HIP
#
# ############################################################

# Cuda Driver API -> Hip porting guide
# - https://rocm.docs.amd.com/projects/HIP/en/docs-5.7.1/user_guide/hip_porting_driver_api.html
# - https://rocm.docs.amd.com/projects/HIPIFY/en/latest/tables/CUDA_Driver_API_functions_supported_by_HIP.html
#
# c2nim on /opt/rocm/include/hip/hip_runtime_api.h
# or just copy-pasting can be used.

const libPath = "/opt/rocm/lib/" # For now, only support Linux
static: echo "[Constantine] Will search AMD HIP runtime in $LD_LIBRARY_PATH and " & libPath & "libamdhip64.so"
const libAmdHip = "(libamdhip64.so|" & libPath & "libamdhip64.so)"

type
  HipError* {.size: sizeof(cint).} = enum
    ## hipError_t
    hipSuccess                     = 0 ## Successful completion.
    hipErrorInvalidValue           = 1 ## One or more of the parameters passed to the API call is NULL
                                       ## or not in an acceptable range.
    # hipErrorOutOfMemory = 2          ## out of memory range.
                                       ## Deprecated
    hipErrorMemoryAllocation = 2       ## Memory allocation error.
    # hipErrorNotInitialized   = 3     ## Invalid not initialized
                                       ## Deprecated
    hipErrorInitializationError    = 3
    hipErrorDeinitialized          = 4   ## Deinitialized
    hipErrorProfilerDisabled       = 5
    hipErrorProfilerNotInitialized = 6
    hipErrorProfilerAlreadyStarted = 7
    hipErrorProfilerAlreadyStopped = 8
    hipErrorInvalidConfiguration   = 9   ## Invalide configuration
    hipErrorInvalidPitchValue      = 12  ## Invalid pitch value
    hipErrorInvalidSymbol          = 13  ## Invalid symbol
    hipErrorInvalidDevicePointer   = 17  ## Invalid Device Pointer
    hipErrorInvalidMemcpyDirection = 21  ## Invalid memory copy direction
    hipErrorInsufficientDriver     = 35
    hipErrorMissingConfiguration   = 52
    hipErrorPriorLaunchFailure     = 53
    hipErrorInvalidDeviceFunction  = 98  ## Invalid device function
    hipErrorNoDevice               = 100 ## Call to hipGetDeviceCount returned 0 devices
    hipErrorInvalidDevice          = 101 ## DeviceID must be in range from 0 to compute-devices.
    hipErrorInvalidImage           = 200 ## Invalid image
    hipErrorInvalidContext         = 201 ## Produced when input context is invalid.
    hipErrorContextAlreadyCurrent  = 202
    # hipErrorMapFailed              = 205
                                         ## Deprecated
    hipErrorMapBufferObjectFailed      = 205 ## Produced when the IPC memory attach failed from ROCr.
    hipErrorUnmapFailed                = 206
    hipErrorArrayIsMapped              = 207
    hipErrorAlreadyMapped              = 208
    hipErrorNoBinaryForGpu             = 209
    hipErrorAlreadyAcquired            = 210
    hipErrorNotMapped                  = 211
    hipErrorNotMappedAsArray           = 212
    hipErrorNotMappedAsPointer         = 213
    hipErrorECCNotCorrectable          = 214
    hipErrorUnsupportedLimit           = 215 ## Unsupported limit
    hipErrorContextAlreadyInUse        = 216 ## The context is already in use
    hipErrorPeerAccessUnsupported      = 217
    hipErrorInvalidKernelFile          = 218 ## In CUDA DRV it is CUDA_ERROR_INVALID_PTX
    hipErrorInvalidGraphicsContext     = 219
    hipErrorInvalidSource              = 300 ## Invalid source.
    hipErrorFileNotFound               = 301 ## the file is not found.
    hipErrorSharedObjectSymbolNotFound = 302
    hipErrorSharedObjectInitFailed     = 303 ## Failed to initialize shared object.
    hipErrorOperatingSystem            = 304 ## Not the correct operating system
    # hipErrorInvalidHandle            = 400 ## Invalide handle
                                           ## Deprecated
    hipErrorInvalidResourceHandle = 400 ## Resource handle (hipEvent_t or hipStream_t) invalid.
    hipErrorIllegalState          = 401 ## Resource required is not in a valid state to perform operation.
    hipErrorNotFound              = 500 ## Not found
    hipErrorNotReady              = 600 ## Indicates that asynchronous operations enqueued earlier are not
                                        ## ready.  This is not actually an error but is used to distinguish
                                        ## from hipSuccess (which indicates completion).  APIs that return
                                        ## this error include hipEventQuery and hipStreamQuery.
    hipErrorIllegalAddress           = 700
    hipErrorLaunchOutOfResources     = 701 ## Out of resources error.
    hipErrorLaunchTimeOut            = 702 ## Timeout for the launch.
    hipErrorPeerAccessAlreadyEnabled = 704  ## Peer access was already enabled from the current device.
    hipErrorPeerAccessNotEnabled     = 705  ## Peer access was never enabled from the current device.
    hipErrorSetOnActiveProcess          = 708 ## The process is active.
    hipErrorContextIsDestroyed          = 709 ## The context is already destroyed
    hipErrorAssert                      = 710 ## Produced when the kernel calls assert.
    hipErrorHostMemoryAlreadyRegistered = 712 ## Produced when trying to lock a page-locked memory.
    hipErrorHostMemoryNotRegistered     = 713 ## Produced when trying to unlock a non-page-locked memory.
    hipErrorLaunchFailure               = 719 ## An exception occurred on the device while executing a kernel.
    hipErrorCooperativeLaunchTooLarge =
        720  ## This error indicates that the number of blocks launched per grid for a kernel
             ## that was launched via cooperative launch APIs exceeds the maximum number of
             ## allowed blocks for the current device
    hipErrorNotSupported             = 801 ## Produced when the hip API is not supported/implemented
    hipErrorStreamCaptureUnsupported = 900 ## The operation is not permitted when the stream
                                          ## is capturing.
    hipErrorStreamCaptureInvalidated = 901 ## The current capture sequence on the stream
                                          ## has been invalidated due to a previous error.
    hipErrorStreamCaptureMerge = 902 ## The operation would have resulted in a merge of
                                     ## two independent capture sequences.
    hipErrorStreamCaptureUnmatched = 903 ## The capture was not initiated in this stream.
    hipErrorStreamCaptureUnjoined  = 904 ## The capture sequence contains a fork that was not
                                         ## joined to the primary stream.
    hipErrorStreamCaptureIsolation = 905 ## A dependency would have been created which crosses
                                         ## the capture sequence boundary. Only implicit
                                         ## in-stream ordering dependencies  are allowed
                                         ## to cross the boundary
    hipErrorStreamCaptureImplicit = 906 ## The operation would have resulted in a disallowed
                                        ## implicit dependency on a current capture sequence
                                        ## from hipStreamLegacy.
    hipErrorCapturedEvent = 907 ## The operation is not permitted on an event which was last
                                ## recorded in a capturing stream.
    hipErrorStreamCaptureWrongThread = 908 ## A stream capture sequence not initiated with
                                           ## the hipStreamCaptureModeRelaxed argument to
                                           ## hipStreamBeginCapture was passed to
                                           ## hipStreamEndCapture in a different thread.
    hipErrorGraphExecUpdateFailure = 910 ## This error indicates that the graph update
                                         ## not performed because it included changes which
                                         ## violated constraintsspecific to instantiated graph
                                         ## update.
    hipErrorUnknown = 999 ## Unknown error.

    ## HSA Runtime Error Codes start here.
    hipErrorRuntimeMemory = 1052 ## HSA runtime memory call returned error.  Typically not seen
                                 ## in production systems.
    hipErrorRuntimeOther = 1053  ## HSA runtime call other than memory returned error.  Typically
                                 ## not seen in production systems.
    hipErrorTbd  ## Marker that more error codes are needed.


  HipDeviceAttribute* {.size: sizeof(cint).} = enum
    ## hipDeviceAttribute_t

    # hipDeviceAttributeCudaCompatibleBegin = 0

    hipDeviceAttributeCudaCompatibleBegin = 0          ## Whether ECC support is enabled.
    hipDeviceAttributeAccessPolicyMaxWindowSize        ## Cuda only. The maximum size of the window policy in bytes.
    hipDeviceAttributeAsyncEngineCount                 ## Asynchronous engines number.
    hipDeviceAttributeCanMapHostMemory                 ## Whether host memory can be mapped into device address space
    hipDeviceAttributeCanUseHostPointerForRegisteredMem ## Device can access host registered memory
                                                        ## at the same virtual address as the CPU
    hipDeviceAttributeClockRate                        ## Peak clock frequency in kilohertz.
    hipDeviceAttributeComputeMode                      ## Compute mode that device is currently in.
    hipDeviceAttributeComputePreemptionSupported       ## Device supports Compute Preemption.
    hipDeviceAttributeConcurrentKernels                ## Device can possibly execute multiple kernels concurrently.
    hipDeviceAttributeConcurrentManagedAccess          ## Device can coherently access managed memory concurrently with the CPU
    hipDeviceAttributeCooperativeLaunch                ## Support cooperative launch
    hipDeviceAttributeCooperativeMultiDeviceLaunch     ## Support cooperative launch on multiple devices
    hipDeviceAttributeDeviceOverlap                    ## Device can concurrently copy memory and execute a kernel.
                                                       ## Deprecated. Use instead asyncEngineCount.
    hipDeviceAttributeDirectManagedMemAccessFromHost   ## Host can directly access managed memory on
                                                       ## the device without migration
    hipDeviceAttributeGlobalL1CacheSupported           ## Device supports caching globals in L1
    hipDeviceAttributeHostNativeAtomicSupported        ## Link between the device and the host supports native atomic operations
    hipDeviceAttributeIntegrated                       ## Device is integrated GPU
    hipDeviceAttributeIsMultiGpuBoard                  ## Multiple GPU devices.
    hipDeviceAttributeKernelExecTimeout                ## Run time limit for kernels executed on the device
    hipDeviceAttributeL2CacheSize                      ## Size of L2 cache in bytes. 0 if the device doesn't have L2 cache.
    hipDeviceAttributeLocalL1CacheSupported            ## caching locals in L1 is supported
    hipDeviceAttributeLuid                             ## 8-byte locally unique identifier in 8 bytes. Undefined on TCC and non-Windows platforms
    hipDeviceAttributeLuidDeviceNodeMask               ## Luid device node mask. Undefined on TCC and non-Windows platforms
    hipDeviceAttributeComputeCapabilityMajor           ## Major compute capability version number.
    hipDeviceAttributeManagedMemory                    ## Device supports allocating managed memory on this system
    hipDeviceAttributeMaxBlocksPerMultiProcessor       ## Max block size per multiprocessor
    hipDeviceAttributeMaxBlockDimX                     ## Max block size in width.
    hipDeviceAttributeMaxBlockDimY                     ## Max block size in height.
    hipDeviceAttributeMaxBlockDimZ                     ## Max block size in depth.
    hipDeviceAttributeMaxGridDimX                      ## Max grid size  in width.
    hipDeviceAttributeMaxGridDimY                      ## Max grid size  in height.
    hipDeviceAttributeMaxGridDimZ                      ## Max grid size  in depth.
    hipDeviceAttributeMaxSurface1D                     ## Maximum size of 1D surface.
    hipDeviceAttributeMaxSurface1DLayered              ## Cuda only. Maximum dimensions of 1D layered surface.
    hipDeviceAttributeMaxSurface2D                     ## Maximum dimension (width height) of 2D surface.
    hipDeviceAttributeMaxSurface2DLayered              ## Cuda only. Maximum dimensions of 2D layered surface.
    hipDeviceAttributeMaxSurface3D                     ## Maximum dimension (width height depth) of 3D surface.
    hipDeviceAttributeMaxSurfaceCubemap                ## Cuda only. Maximum dimensions of Cubemap surface.
    hipDeviceAttributeMaxSurfaceCubemapLayered         ## Cuda only. Maximum dimension of Cubemap layered surface.
    hipDeviceAttributeMaxTexture1DWidth                ## Maximum size of 1D texture.
    hipDeviceAttributeMaxTexture1DLayered              ## Maximum dimensions of 1D layered texture.
    hipDeviceAttributeMaxTexture1DLinear               ## Maximum number of elements allocatable in a 1D linear texture.
                                                       ## Use cudaDeviceGetTexture1DLinearMaxWidth() instead on Cuda.
    hipDeviceAttributeMaxTexture1DMipmap               ## Maximum size of 1D mipmapped texture.
    hipDeviceAttributeMaxTexture2DWidth                ## Maximum dimension width of 2D texture.
    hipDeviceAttributeMaxTexture2DHeight               ## Maximum dimension hight of 2D texture.
    hipDeviceAttributeMaxTexture2DGather               ## Maximum dimensions of 2D texture if gather operations  performed.
    hipDeviceAttributeMaxTexture2DLayered              ## Maximum dimensions of 2D layered texture.
    hipDeviceAttributeMaxTexture2DLinear               ## Maximum dimensions (width height pitch) of 2D textures bound to pitched memory.
    hipDeviceAttributeMaxTexture2DMipmap               ## Maximum dimensions of 2D mipmapped texture.
    hipDeviceAttributeMaxTexture3DWidth                ## Maximum dimension width of 3D texture.
    hipDeviceAttributeMaxTexture3DHeight               ## Maximum dimension height of 3D texture.
    hipDeviceAttributeMaxTexture3DDepth                ## Maximum dimension depth of 3D texture.
    hipDeviceAttributeMaxTexture3DAlt                  ## Maximum dimensions of alternate 3D texture.
    hipDeviceAttributeMaxTextureCubemap                ## Maximum dimensions of Cubemap texture
    hipDeviceAttributeMaxTextureCubemapLayered         ## Maximum dimensions of Cubemap layered texture.
    hipDeviceAttributeMaxThreadsDim                    ## Maximum dimension of a block
    hipDeviceAttributeMaxThreadsPerBlock               ## Maximum number of threads per block.
    hipDeviceAttributeMaxThreadsPerMultiProcessor      ## Maximum resident threads per multiprocessor.
    hipDeviceAttributeMaxPitch                         ## Maximum pitch in bytes allowed by memory copies
    hipDeviceAttributeMemoryBusWidth                   ## Global memory bus width in bits.
    hipDeviceAttributeMemoryClockRate                  ## Peak memory clock frequency in kilohertz.
    hipDeviceAttributeComputeCapabilityMinor           ## Minor compute capability version number.
    hipDeviceAttributeMultiGpuBoardGroupID             ## Unique ID of device group on the same multi-GPU board
    hipDeviceAttributeMultiprocessorCount              ## Number of multiprocessors on the device.
    hipDeviceAttributeUnused1                          ## Previously hipDeviceAttributeName
    hipDeviceAttributePageableMemoryAccess             ## Device supports coherently accessing pageable memory
                                                       ## without calling hipHostRegister on it
    hipDeviceAttributePageableMemoryAccessUsesHostPageTables ## Device accesses pageable memory via the host's page tables
    hipDeviceAttributePciBusId                         ## PCI Bus ID.
    hipDeviceAttributePciDeviceId                      ## PCI Device ID.
    hipDeviceAttributePciDomainID                      ## PCI Domain ID.
    hipDeviceAttributePersistingL2CacheMaxSize         ## Maximum l2 persisting lines capacity in bytes
    hipDeviceAttributeMaxRegistersPerBlock             ## 32-bit registers available to a thread block. This number is shared
                                                       ## by all thread blocks simultaneously resident on a multiprocessor.
    hipDeviceAttributeMaxRegistersPerMultiprocessor    ## 32-bit registers available per block.
    hipDeviceAttributeReservedSharedMemPerBlock        ## Shared memory reserved by CUDA driver per block.
    hipDeviceAttributeMaxSharedMemoryPerBlock          ## Maximum shared memory available per block in bytes.
    hipDeviceAttributeSharedMemPerBlockOptin           ## Maximum shared memory per block usable by special opt in.
    hipDeviceAttributeSharedMemPerMultiprocessor       ## Shared memory available per multiprocessor.
    hipDeviceAttributeSingleToDoublePrecisionPerfRatio ## Cuda only. Performance ratio of single precision to double precision.
    hipDeviceAttributeStreamPrioritiesSupported        ## Whether to support stream priorities.
    hipDeviceAttributeSurfaceAlignment                 ## Alignment requirement for surfaces
    hipDeviceAttributeTccDriver                        ## Cuda only. Whether device is a Tesla device using TCC driver
    hipDeviceAttributeTextureAlignment                 ## Alignment requirement for textures
    hipDeviceAttributeTexturePitchAlignment            ## Pitch alignment requirement for 2D texture references bound to pitched memory;
    hipDeviceAttributeTotalConstantMemory              ## Constant memory size in bytes.
    hipDeviceAttributeTotalGlobalMem                   ## Global memory available on devicice.
    hipDeviceAttributeUnifiedAddressing                ## Cuda only. An unified address space shared with the host.
    hipDeviceAttributeUnused2                          ## Previously hipDeviceAttributeUuid
    hipDeviceAttributeWarpSize                         ## Warp size in threads.
    hipDeviceAttributeMemoryPoolsSupported             ## Device supports HIP Stream Ordered Memory Allocator
    hipDeviceAttributeVirtualMemoryManagementSupported ## Device supports HIP virtual memory management
    hipDeviceAttributeHostRegisterSupported            ## Can device support host memory registration via hipHostRegister
    hipDeviceAttributeCudaCompatibleEnd = 9999

    # hipDeviceAttributeAmdSpecificBegin = 10000
    # ----------------------------------------------------------------------------

    hipDeviceAttributeClockInstructionRate = 10000             ## Frequency in khz of the timer used by the device-side "clock*"
    hipDeviceAttributeUnused3                                  ## Previously hipDeviceAttributeArch
    hipDeviceAttributeMaxSharedMemoryPerMultiprocessor         ## Maximum Shared Memory PerMultiprocessor.
    hipDeviceAttributeUnused4                                  ## Previously hipDeviceAttributeGcnArch
    hipDeviceAttributeUnused5                                  ## Previously hipDeviceAttributeGcnArchName
    hipDeviceAttributeHdpMemFlushCntl                          ## Address of the HDP_MEM_COHERENCY_FLUSH_CNTL register
    hipDeviceAttributeHdpRegFlushCntl                          ## Address of the HDP_REG_COHERENCY_FLUSH_CNTL register
    hipDeviceAttributeCooperativeMultiDeviceUnmatchedFunc      ## Supports cooperative launch on multiple
                                                               ## devices with unmatched functions
    hipDeviceAttributeCooperativeMultiDeviceUnmatchedGridDim   ## Supports cooperative launch on multiple
                                                               ## devices with unmatched grid dimensions
    hipDeviceAttributeCooperativeMultiDeviceUnmatchedBlockDim  ## Supports cooperative launch on multiple
                                                               ## devices with unmatched block dimensions
    hipDeviceAttributeCooperativeMultiDeviceUnmatchedSharedMem ## Supports cooperative launch on multiple
                                                               ## devices with unmatched shared memories
    hipDeviceAttributeIsLargeBar                               ## Whether it is LargeBar
    hipDeviceAttributeAsicRevision                             ## Revision of the GPU in this device
    hipDeviceAttributeCanUseStreamWaitValue                    ## '1' if Device supports hipStreamWaitValue32() and
                                                               ## hipStreamWaitValue64(), '0' otherwise.
    hipDeviceAttributeImageSupport                             ## '1' if Device supports image, '0' otherwise.
    hipDeviceAttributePhysicalMultiProcessorCount              ## All available physical compute
                                                               ## units for the device
    hipDeviceAttributeFineGrainSupport                         ## '1' if Device supports fine grain, '0' otherwise
    hipDeviceAttributeWallClockRate                            ## Constant frequency of wall clock in kilohertz.

    hipDeviceAttributeAmdSpecificEnd = 19999
    hipDeviceAttributeVendorSpecificBegin = 20000
    ## Extended attributes for vendors

  HipMemAttach_flags* = enum
    hipMemAttachGlobal = 0x1, ## Memory can be accessed by any stream on any device
    hipMemAttachHost = 0x2,   ## Memory cannot be accessed by any stream on any device
    hipMemAttachSingle = 0x4

  HipDevice* = distinct int32      ## Hip Compute Device handle
  HipContext* = distinct pointer   # hipCtx_t
  HipModule* = distinct pointer    # hipModule_t
  HipFunction* = distinct pointer  # hipFunction_t
  HipStream* = distinct pointer    # hipStream_t
  HipDeviceptr* = distinct pointer # HipDeviceptr_t
    ## A pointer to data on the Hip device

type
  HipDeviceProp* {.bycopy.} = object
    # Generated via c2nim from HIP v6.0.2
    # The ABI seems forward compatible with reserved bytes
    #
    # We don't import the `hip_runtime_api.h` header
    # for one less dependency during deployment,
    # especially given than some distributions like Ubuntu
    # split between a dev (with headers) and regular package
    # and Windows path management is cumbersome.

    # Note the macro
    # #define hipDeviceProp_t hipDeviceProp_tR0600

    name*: array[256, char]
    ## Device name.
    uuid*: hipUUID
    ## UUID of a device
    luid*: array[8, byte]
    ## 8-byte unique identifier. Only valid on windows
    luidDeviceNodeMask*: cuint
    ## LUID node mask
    totalGlobalMem*: csize_t
    ## Size of global memory region (in bytes).
    sharedMemPerBlock*: csize_t
    ## Size of shared memory region (in bytes).
    regsPerBlock*: cint
    ## Registers per block.
    warpSize*: cint
    ## Warp size.
    memPitch*: csize_t
    ## Maximum pitch in bytes allowed by memory copies
    ## pitched memory
    maxThreadsPerBlock*: cint
    ## Max work items per work group or workgroup max size.
    maxThreadsDim*: array[3, cint]
    ## Max number of threads in each dimension (XYZ) of a block.
    maxGridSize*: array[3, cint]
    ## Max grid dimensions (XYZ).
    clockRate*: cint
    ## Max clock frequency of the multiProcessors in khz.
    totalConstMem*: csize_t
    ## Size of shared memory region (in bytes).
    major*: cint
    ## Major compute capability.  On HCC, this is an approximation and features may
    ## differ from CUDA CC.  See the arch feature flags for portable ways to query
    ## feature caps.
    minor*: cint
    ## Minor compute capability.  On HCC, this is an approximation and features may
    ## differ from CUDA CC.  See the arch feature flags for portable ways to query
    ## feature caps.
    textureAlignment*: csize_t
    ## Alignment requirement for textures
    texturePitchAlignment*: csize_t
    ## Pitch alignment requirement for texture references bound to
    deviceOverlap*: cint
    ## Deprecated. Use asyncEngineCount instead
    multiProcessorCount*: cint
    ## Number of multi-processors (compute units).
    kernelExecTimeoutEnabled*: cint
    ## Run time limit for kernels executed on the device
    integrated*: cint
    ## APU vs dGPU
    canMapHostMemory*: cint
    ## Check whether HIP can map host memory
    computeMode*: cint
    ## Compute mode.
    maxTexture1D*: cint
    ## Maximum number of elements in 1D images
    maxTexture1DMipmap*: cint
    ## Maximum 1D mipmap texture size
    maxTexture1DLinear*: cint
    ## Maximum size for 1D textures bound to linear memory
    maxTexture2D*: array[2, cint]
    ## Maximum dimensions (width, height) of 2D images, in image elements
    maxTexture2DMipmap*: array[2, cint]
    ## Maximum number of elements in 2D array mipmap of images
    maxTexture2DLinear*: array[3, cint]
    ## Maximum 2D tex dimensions if tex are bound to pitched memory
    maxTexture2DGather*: array[2, cint]
    ## Maximum 2D tex dimensions if gather has to be performed
    maxTexture3D*: array[3, cint]
    ## Maximum dimensions (width, height, depth) of 3D images, in image
    ## elements
    maxTexture3DAlt*: array[3, cint]
    ## Maximum alternate 3D texture dims
    maxTextureCubemap*: cint
    ## Maximum cubemap texture dims
    maxTexture1DLayered*: array[2, cint]
    ## Maximum number of elements in 1D array images
    maxTexture2DLayered*: array[3, cint]
    ## Maximum number of elements in 2D array images
    maxTextureCubemapLayered*: array[2, cint]
    ## Maximum cubemaps layered texture dims
    maxSurface1D*: cint
    ## Maximum 1D surface size
    maxSurface2D*: array[2, cint]
    ## Maximum 2D surface size
    maxSurface3D*: array[3, cint]
    ## Maximum 3D surface size
    maxSurface1DLayered*: array[2, cint]
    ## Maximum 1D layered surface size
    maxSurface2DLayered*: array[3, cint]
    ## Maximum 2D layared surface size
    maxSurfaceCubemap*: cint
    ## Maximum cubemap surface size
    maxSurfaceCubemapLayered*: array[2, cint]
    ## Maximum cubemap layered surface size
    surfaceAlignment*: csize_t
    ## Alignment requirement for surface
    concurrentKernels*: cint
    ## Device can possibly execute multiple kernels concurrently.
    ECCEnabled*: cint
    ## Device has ECC support enabled
    pciBusID*: cint
    ## PCI Bus ID.
    pciDeviceID*: cint
    ## PCI Device ID.
    pciDomainID*: cint
    ## PCI Domain ID
    tccDriver*: cint
    ## 1:If device is Tesla device using TCC driver, else 0
    asyncEngineCount*: cint
    ## Number of async engines
    unifiedAddressing*: cint
    ## Does device and host share unified address space
    memoryClockRate*: cint
    ## Max global memory clock frequency in khz.
    memoryBusWidth*: cint
    ## Global memory bus width in bits.
    l2CacheSize*: cint
    ## L2 cache size.
    persistingL2CacheMaxSize*: cint
    ## Device's max L2 persisting lines in bytes
    maxThreadsPerMultiProcessor*: cint
    ## Maximum resident threads per multi-processor.
    streamPrioritiesSupported*: cint
    ## Device supports stream priority
    globalL1CacheSupported*: cint
    ## Indicates globals are cached in L1
    localL1CacheSupported*: cint
    ## Locals are cahced in L1
    sharedMemPerMultiprocessor*: csize_t
    ## Amount of shared memory available per multiprocessor.
    regsPerMultiprocessor*: cint
    ## registers available per multiprocessor
    managedMemory*: cint
    ## Device supports allocating managed memory on this system
    isMultiGpuBoard*: cint
    ## 1 if device is on a multi-GPU board, 0 if not.
    multiGpuBoardGroupID*: cint
    ## Unique identifier for a group of devices on same multiboard GPU
    hostNativeAtomicSupported*: cint
    ## Link between host and device supports native atomics
    singleToDoublePrecisionPerfRatio*: cint
    ## Deprecated. CUDA only.
    pageableMemoryAccess*: cint
    ## Device supports coherently accessing pageable memory
    ## without calling hipHostRegister on it
    concurrentManagedAccess*: cint
    ## Device can coherently access managed memory concurrently with
    ## the CPU
    computePreemptionSupported*: cint
    ## Is compute preemption supported on the device
    canUseHostPointerForRegisteredMem*: cint
    ## Device can access host registered memory with same
    ## address as the host
    cooperativeLaunch*: cint
    ## HIP device supports cooperative launch
    cooperativeMultiDeviceLaunch*: cint
    ## HIP device supports cooperative launch on multiple
    ## devices
    sharedMemPerBlockOptin*: csize_t
    ## Per device m ax shared mem per block usable by special opt in
    pageableMemoryAccessUsesHostPageTables*: cint
    ## Device accesses pageable memory via the host's
    ## page tables
    directManagedMemAccessFromHost*: cint
    ## Host can directly access managed memory on the device
    ## without migration
    maxBlocksPerMultiProcessor*: cint
    ## Max number of blocks on CU
    accessPolicyMaxWindowSize*: cint
    ## Max value of access policy window
    reservedSharedMemPerBlock*: csize_t
    ## Shared memory reserved by driver per block
    hostRegisterSupported*: cint
    ## Device supports hipHostRegister
    sparseHipArraySupported*: cint
    ## Indicates if device supports sparse hip arrays
    hostRegisterReadOnlySupported*: cint
    ## Device supports using the hipHostRegisterReadOnly flag
    ## with hipHostRegistger
    timelineSemaphoreInteropSupported*: cint
    ## Indicates external timeline semaphore support
    memoryPoolsSupported*: cint
    ## Indicates if device supports hipMallocAsync and hipMemPool APIs
    gpuDirectRDMASupported*: cint
    ## Indicates device support of RDMA APIs
    gpuDirectRDMAFlushWritesOptions*: cuint
    ## Bitmask to be interpreted according to
    ## hipFlushGPUDirectRDMAWritesOptions
    gpuDirectRDMAWritesOrdering*: cint
    ## value of hipGPUDirectRDMAWritesOrdering
    memoryPoolSupportedHandleTypes*: cuint
    ## Bitmask of handle types support with mempool based IPC
    deferredMappingHipArraySupported*: cint
    ## Device supports deferred mapping HIP arrays and HIP
    ## mipmapped arrays
    ipcEventSupported*: cint
    ## Device supports IPC events
    clusterLaunch*: cint
    ## Device supports cluster launch
    unifiedFunctionPointers*: cint
    ## Indicates device supports unified function pointers
    reserved*: array[63, cint]
    ## CUDA Reserved.
    hipReserved*: array[32, cint]
    ## Reserved for adding new entries for HIP/CUDA.
    ##  HIP Only struct members
    gcnArchName*: array[256, char]
    ## AMD GCN Arch Name. HIP Only.
    maxSharedMemoryPerMultiProcessor*: csize_t
    ## Maximum Shared Memory Per CU. HIP Only.
    clockInstructionRate*: cint
    ## Frequency in khz of the timer used by the device-side "clock*"
    ## instructions.  New for HIP.
    arch*: HipDeviceArch
    ## Architectural feature flags.  New for HIP.
    hdpMemFlushCntl*: ptr cuint
    ## Addres of HDP_MEM_COHERENCY_FLUSH_CNTL register
    hdpRegFlushCntl*: ptr cuint
    ## Addres of HDP_REG_COHERENCY_FLUSH_CNTL register
    cooperativeMultiDeviceUnmatchedFunc*: cint
    ## HIP device supports cooperative launch on
    ## multiple
    ##  devices with unmatched functions
    cooperativeMultiDeviceUnmatchedGridDim*: cint
    ## HIP device supports cooperative launch on
    ## multiple
    ##  devices with unmatched grid dimensions
    cooperativeMultiDeviceUnmatchedBlockDim*: cint
    ## HIP device supports cooperative launch on
    ## multiple
    ##  devices with unmatched block dimensions
    cooperativeMultiDeviceUnmatchedSharedMem*: cint
    ## HIP device supports cooperative launch on
    ## multiple
    ##  devices with unmatched shared memories
    isLargeBar*: cint
    ## 1: if it is a large PCI bar device, else 0
    asicRevision*: cint
    ## Revision of the GPU in this device

  hipUUID* {.bycopy.} = object
    bytes*: array[16, byte]

  HipDeviceArch* {.bycopy.} = object
    ##  32-bit Atomics
    hasGlobalInt32Atomics* {.bitsize: 1.}: cuint
    ## 32-bit integer atomics for global memory.
    hasGlobalFloatAtomicExch* {.bitsize: 1.}: cuint
    ## 32-bit float atomic exch for global memory.
    hasSharedInt32Atomics* {.bitsize: 1.}: cuint
    ## 32-bit integer atomics for shared memory.
    hasSharedFloatAtomicExch* {.bitsize: 1.}: cuint
    ## 32-bit float atomic exch for shared memory.
    hasFloatAtomicAdd* {.bitsize: 1.}: cuint
    ## 32-bit float atomic add in global and shared memory.
    ##  64-bit Atomics
    hasGlobalInt64Atomics* {.bitsize: 1.}: cuint
    ## 64-bit integer atomics for global memory.
    hasSharedInt64Atomics* {.bitsize: 1.}: cuint
    ## 64-bit integer atomics for shared memory.
    ##  Doubles
    hasDoubles* {.bitsize: 1.}: cuint
    ## Double-precision floating point.
    ##  Warp cross-lane operations
    hasWarpVote* {.bitsize: 1.}: cuint
    ## Warp vote instructions (__any, __all).
    hasWarpBallot* {.bitsize: 1.}: cuint
    ## Warp ballot instructions (__ballot).
    hasWarpShuffle* {.bitsize: 1.}: cuint
    ## Warp shuffle operations. (__shfl_*).
    hasFunnelShift* {.bitsize: 1.}: cuint
    ## Funnel two words into one with shift&mask caps.
    ##  Sync
    hasThreadFenceSystem* {.bitsize: 1.}: cuint
    ## __threadfence_system.
    hasSyncThreadsExt* {.bitsize: 1.}: cuint
    ## __syncthreads_count, syncthreads_and, syncthreads_or.
    ##  Misc
    hasSurfaceFuncs* {.bitsize: 1.}: cuint
    ## Surface functions.
    has3dGrid* {.bitsize: 1.}: cuint
    ## Grid and group dims are 3D (rather than 2D).
    hasDynamicParallelism* {.bitsize: 1.}: cuint
    ## Dynamic parallelism.

proc hipGetDeviceProperties*(prop: var HipDeviceProp, ordinal: int32): HipError {.
  noconv, importc: "hipGetDevicePropertiesR0600", dynlib: libAmdHip.}
  # Note the macro
  # `#define hipGetDeviceProperties hipGetDevicePropertiesR0600`

{.push noconv, importc, dynlib: libAmdHip.}

proc hipInit*(flags: uint32): HipError

proc hipGetDeviceCount*(count: var int32): HipError
proc hipDeviceGet*(device: var HipDevice, ordinal: int32): HipError
proc hipDeviceGetName*(name: ptr char, len: int32, dev: HipDevice): HipError
proc hipDeviceGetAttribute*(r: var int32, attrib: HipDeviceAttribute, dev: HipDevice): HipError

proc hipCtxCreate*(ctx: var HipContext, flags: uint32, dev: HipDevice): HipError
proc hipCtxDestroy*(ctx: HipContext): HipError
proc hipCtxSynchronize*(ctx: HipContext): HipError

proc hipModuleLoadData(module: var HipModule, code_object: pointer): HipError {.used.}
proc hipModuleUnload*(module: HipModule): HipError
proc hipModuleGetFunction(kernel: var HipFunction, module: HipModule, fnName: ptr char): HipError {.used.}

proc hipModuleLaunchKernel(
       kernel: HipFunction,
       gridDimX, gridDimY, gridDimZ: uint32,
       blockDimX, blockDimY, blockDimZ: uint32,
       sharedMemBytes: uint32,
       stream: HipStream,
       kernelParams: ptr pointer,
       extra: ptr pointer
     ): HipError {.used.}

proc hipMalloc*(devptr: var HipDeviceptr, size: csize_t): HipError
proc hipMallocManaged*(devptr: var HipDeviceptr, size: csize_t, flags: Flag[HipMemAttach_flags]): HipError
proc hipFree*(devptr: HipDeviceptr): HipError
proc hipMemcpyHtoD*(dst: HipDeviceptr, src: pointer, size: csize_t): HipError
proc hipMemcpyDtoH*(dst: pointer, src: HipDeviceptr, size: csize_t): HipError

{.pop.} # {.push importc, dynlib: "libamdhip64.so".}

# ------------------------------------------------------------------------------
# Sanity check

when isMainModule:

  template check*(status: HipError) =
    ## Check the status code of a Hip operation
    ## Exit program with error if failure

    let code = status # ensure that the input expression is evaluated once only
    if code != hipSuccess:
      writeStackTrace()
      stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
      quit 1

  proc main*() =
    var props: HipDeviceProp
    var device: cint = 0
    check hipGetDeviceProperties(props, device)
    echo "warpSize: ", props.warpSize
    echo "GCN Architecture: ", props.gcnArchName

  main()
