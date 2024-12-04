## XXX: for now dependent on nimcuda for ease of development

import
  std / [strformat, strutils],
  nimcuda/cuda12_5/[nvrtc, check, cuda, cuda_runtime_api, driver_types]

import ./nim_ast_to_cuda_ast
import ./cuda_execute_dsl
export cuda_execute_dsl
export nim_ast_to_cuda_ast

## Set to true, if you want some extra output (driver & runtime version for example)
const DebugCuda {.booldefine.} = true
## Path to your CUDA installation. Currently a `strdefine`, will likely change in the future
const CudaPath {.strdefine.} = "/usr/local/cuda-12.6/targets/x86_64-linux/"

## NOTE: We need to define the paths to our CUDA installation at compile time,
## because we need to use the `{.header: ...}` pragma for the CUDA wrapper.
## We might move to a 'supply your own `nim.cfg` defining them' approach in the future.
{.passC: "-I" & CudaPath & "/include".}
{.passL: "-L" & CudaPath & "/lib -lcuda".}

## Dummy data for the typed nature of the `cuda` macro. These define commonly used
## CUDA specific names so that they produce valid Nim code in the context of a typed macro.
template global*() {.pragma.}
template device*() {.pragma.}
template forceinline*() {.pragma.}
type
  Dim* = cint ## dummy to have access to math
  NvBlockIdx* = object
    x*: Dim
    y*: Dim
    z*: Dim
  NvBlockDim = object
    x*: Dim
    y*: Dim
    z*: Dim
  NvThreadIdx* = object
    x*: Dim
    y*: Dim
    z*: Dim

## These are dummy elements to make CUDA block / thread index / dim
## access possible in the *typed* `cuda` macro. It cannot be `const`,
## because then the typed code would evaluate the values before we
## can work with it from the typed macro.
let blockIdx* = NvBlockIdx()
let blockDim* = NvBlockDim()
let threadIdx* = NvThreadIdx()

## Similar for procs. They don't need any implementation, as they won't ever be actually called.
proc printf*(fmt: string) {.varargs.} = discard
proc memcpy*(dst, src: pointer, size: int) = discard

type
  NVRTC* = object
    numBlocks* = 32 # number of blocks to launch
    threadsPerBlock* = 128 # number of threads for each block. Total threads: `numBlocks * threadsPerBlock`
    name*: string # Name of the program (of the generated in memory CUDA file)
    prog*: nvrtcProgram
    log*: string # The compilation log
    ptx*: string # PTX of the program
    cubin*: pointer
    cubinSize*: csize_t
    device*: CUdevice
    kernel*: CUfunction
    module*: CUmodule
    context*: CUcontext

proc `=destroy`(nvrtc: NVRTC) =
  if nvrtc.module != nil:
    check cuModuleUnload nvrtc.module
  if nvrtc.context != nil:
    check cuCtxDestroy nvrtc.context

proc initNvrtc*(cuda: string, name = "sample.cu"): NVRTC =
  ## Initializes an NVRTC object for the given program `cuda`
  when DebugCuda:
    var x: cint
    cuDriverGetVersion(x.addr)
    echo "Driver version: ", x

    var rtVer: cint
    echo cudaRuntimeGetVersion(addr rtVer)
    echo "Runtime ver: ", rtVer

    var prop: cudaDeviceProp
    echo cudaGetDeviceProperties(addr prop, 0);
    echo "Compute capability: ", prop.major, " ", prop.minor

  var
    context: CUcontext
    device: CUdevice

  check cuInit(0)
  check cuDeviceGet(addr device, 0)
  check cuCtxCreate(addr context, 0, device)

  # Create an instance of nvrtcProgram based on the passed code
  var prog: nvrtcProgram
  check nvrtcCreateProgram(addr(prog), cstring cuda, cstring name, 0, nil, nil)

  result = NVRTC(prog: prog, name: name,
                 device: device,
                 context: context)


proc log*(nvrtc: var NVRTC) =
  ## Retrieve the compilation log.
  var logSize: csize_t
  check nvrtcGetProgramLogSize(nvrtc.prog, addr logSize)

  var log = cstring newString(Natural logSize)

  check nvrtcGetProgramLog(nvrtc.prog, log)
  nvrtc.log = $log # usually empty if no issues found by the compiler

proc compile*(nvrtc: var NVRTC) =
  # Compile the program with fmad disabled.
  # Note: Can specify GPU target architecture explicitly with '-arch' flag.
  const
    Options = [
      cstring "--gpu-architecture=compute_61", # or whatever your GPU arch is
      # "--fmad=false", # and whatever other options for example
    ]

    NumberOfOptions = cint Options.len
  let compileResult =  nvrtcCompileProgram(nvrtc.prog, NumberOfOptions,
                                           cast[cstringArray](addr Options[0]))

  nvrtc.log()
  ## XXX: only in `DebugCuda`?
  echo "Compilation log:\n------------------------------"
  echo nvrtc.log
  echo "------------------------------"
  check compileResult

proc getPtx*(nvrtc: var NVRTC) =
  ## Obtain PTX from the program.
  var ptxSize: csize_t
  check nvrtcGetPTXSize(nvrtc.prog, addr ptxSize)

  var ptx = newString(int ptxSize)
  check nvrtcGetPTX(nvrtc.prog, ptx)

  when DebugCuda:
    echo "PTX size: ", ptxSize
    echo "-------------------- PTX --------------------\n", nvrtc.ptx

  check nvrtcDestroyProgram(addr nvrtc.prog) # Destroy the program.
  nvrtc.ptx = ptx

proc link*(nvrtc: var NVRTC) =
  ## OPTIONAL STEP. Alternative to passing the PTX to `cuModuleLoadData`.
  # Create linker
  var linkState: CUlinkState
  var linkOptions: array[4, CUjit_option]
  var linkOptionValues: array[4, pointer]
  var errorLog = newString(4096)
  var infoLog = newString(4096)
  var walltime: float32

  linkOptions[0] = CU_JIT_WALL_TIME
  linkOptionValues[0] = addr walltime
  linkOptions[1] = CU_JIT_ERROR_LOG_BUFFER_SIZE_BYTES
  linkOptionValues[1] = cast[pointer](4096)
  linkOptions[2] = CU_JIT_ERROR_LOG_BUFFER
  linkOptionValues[2] = addr errorLog[0]
  linkOptions[3] = CU_JIT_INFO_LOG_BUFFER
  linkOptionValues[3] = addr infoLog[0]

  check cuLinkCreate(3, addr linkOptions[0], addr linkOptionValues[0], addr linkState)

  # Add PTX
  var res = cuLinkAddData(linkState, CU_JIT_INPUT_PTX,
                          cast[pointer](cstring nvrtc.ptx),
                          csize_t nvrtc.ptx.len,
                          "kernel.ptx", 0, nil, nil)

  var status: CUresult
  if res != CUDA_SUCCESS:
    var error_str: cstring
    #discard cuGetErrorString(res, addr error_str)
    cuGetErrorString(status, cast[cstringArray](addr error_str));
    echo "Link add PTX failed: ", error_str
    echo "Error log: ", errorLog
    quit(1)

  # Add the device runtime (provides printf support)
  ## NOTE: Linking requires yout to pass the path to `libcudadevrt.a` at CT
  res = cuLinkAddFile(linkState, CU_JIT_INPUT_LIBRARY,
                      "/usr/local/cuda/targets/x86_64-linux/lib/libcudadevrt.a",  # Adjust path as needed
                      0, nil, nil)
  if res != CUDA_SUCCESS:
    var error_str: cstring
    cuGetErrorString(status, cast[cstringArray](addr error_str));
    echo "Link add device runtime failed: ", error_str
    echo "Error log: ", errorLog
    quit(1)

  # Complete linking
  var cubn: pointer
  var cubinSize: csize_t
  res = cuLinkComplete(linkState, cubn.addr, cubinSize.addr)
  nvrtc.cubinSize = cubinSize
  if res != CUDA_SUCCESS:
    var error_str: cstring
    cuGetErrorString(status, cast[cstringArray](addr error_str));
    echo "Link complete failed: ", error_str
    echo "Error log: ", errorLog
    quit(1)

  when DebugCuda:
    echo "[INFO]: Writing CUBIN data to file /tmp/test.cubin"
    echo "Cubin size: ", cubinSize
    var f = open("/tmp/test.cubin", fmWrite)
    discard f.writeBuffer(cubn, cubinSize)
    f.close()

  # Assign the cubin
  nvrtc.cubin = cubn

template execute*(nvrtc: var NVRTC, fn: string, res, inputs: typed) =
  ## Load the generated PTX, get the target kernel `fn` and execute it with the `res` and `inputs`

  # After getting the PTX...
  var error_log = newString(8192)
  var info_log = newString(8192)

  ## NOTE: if you wish to use the `link` approach, pass `nvrtc.cubin` instead of `PTX`
  #let status = cuModuleLoadData(addr nvrtc.module, nvrtc.cubin)
  let status = cuModuleLoadData(addr nvrtc.module, cstring nvrtc.ptx)
  if status != CUDA_SUCCESS:
    var error_str: cstring #const char* error_str;
    cuGetErrorString(status, cast[cstringArray](addr error_str));
    echo "Module load failed: ", error_str
    echo "JIT Error log: ", error_log
    echo "JIT Info log: ", info_log
    quit(1)
  check cuModuleGetFunction(addr nvrtc.kernel, nvrtc.module, fn)

  # now execute the kernel
  execCuda(nvrtc.kernel, nvrtc.numBlocks, nvrtc.threadsPerBlock, res, inputs)

  # synchronize so that e.g. `printf` statements will be printed before we (possibly) quit
  check cuCtxSynchronize() #
