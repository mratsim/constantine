# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# AMD Code Object Manager (comgr)
# --------------------------------------------------------------------------------------------------
#
# https://github.com/ROCm/llvm-project/tree/amd-staging/amd/comgr

# Overview
# Unlike Nvidia GPUs that use a Virtual ISA that is then recompiled
# by the CUDA driver, AMD GPUs produce object code.
#
# That object code then must be linked by LLD
#   https://llvm.org/docs/AMDGPUUsage.html#elf-code-object
#
# Unfortunately LLD is not designed as a library like the rest of LLVM
# and in particular does not provide a C API
#   https://groups.google.com/g/llvm-dev/c/K30vI0AU9vg?pli=1
#
# 1. We can link to it using C++ lld::elf::link (or lld::coff::link or ...)
#   https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/lld/include/lld/Common/Driver.h#L52-L57
#   This is what is done in MLIR:
#   https://reviews.llvm.org/D80676#change-KfPawdnRjasK
#
# 2. Alternatively, if we don't want to compile Nim via C++
#    we can have a .cpp file with extern "C"
#    and customize the build with
#    - querying the nimcache directory via std/compilersettings
#    - staticExec the .cpp file
#    - passL to link the resulting object
#    - Use a C++ linker
#    See https://github.com/xrfez/nim_mixed_c_cpp_static/blob/master/helloWorld.nim#L14-L18
#
# 3. Yet another alternative is to call LDD
#
# 4. MCJIT or OrcJIT can bypass the need of an external linker
#    But calling GPU functions is not supported
#    https://llvm.org/docs/JITLink.html#jitlink-availability-and-feature-status
#
# 5. It might be possible to use AMD HIP RTC API
#    as it supports linking LLVM bitcode
#    https://rocm.docs.amd.com/projects/HIP/en/docs-6.0.0/user_guide/hip_rtc.html
#
# Criticisms
#
# Solution 3 seems to be wildly adopted, in Julia, IREE and Taichi
# - https://github.com/iree-org/iree/blob/26f77de/compiler/plugins/target/LLVMCPU/internal/EmbeddedLinkerTool.cpp#L42-L48
# - https://github.com/JuliaGPU/AMDGPU.jl/blob/v0.9.6/src/compiler/codegen.jl#L148-L154
# - https://github.com/taichi-dev/taichi/pull/6482/files#diff-9ab763eb7ff4e6aca0a97f774cc740c609d0258ac584039d0c8cae099dfea452R90
#
# However ldd is shipped as a separate tool from LLVM, and as a cryptographic library
# we need to minimize the attack surface, i.e. someone installing a "ldd" script that would be executed byu our code.
# It's harder to replace library paths as those need root or are restricted to a shell session if overloading LD_LIBRARY_PATH
#
# Solution 1 needs temporary files
# Solution 2 too and seems hard to maintain
# Solution 4 is a non-starter
#
# Solution 5 is likely possible as the header offers the following enum value
# to pass to the linker "hiprtcJITInputType: HIPRTC_JIT_INPUT_OBJECT"
# However we don't really need the full RTC since we already did LLVM IR -> object file
#
# Looking deeper into hipRTC we see that it depends on comgr, just like the HIP runtime
# and comgr only roles is dealing with object file.
# It does use LLD under-the-hood but from a fork specialized for AMD purposes:
#   https://github.com/ROCm/llvm-project/blob/rocm-6.2.0/amd/comgr/src/comgr-compiler.cpp#L614-L630
# Hence we solve all of our concerns.

const
  # Generated from Comgr 2.6
  AMD_COMGR_INTERFACE_VERSION_MAJOR {.used.} = 2
  AMD_COMGR_INTERFACE_VERSION_MINOR {.used.} = 6

##  \defgroup codeobjectmanager Code Object Manager
##   @{
##
##  @brief The code object manager is a callable library that provides
##  operations for creating and inspecting code objects.
##
##  The library provides handles to various objects. Concurrent execution of
##  operations is supported provided all objects accessed by each concurrent
##  operation are disjoint. For example, the @p amd_comgr_data_set_t handles
##  passed to operations must be disjoint, together with all the @p
##  amd_comgr_data_t handles that have been added to it. The exception is that
##  the default device library data object handles can be non-disjoint as they
##  are imutable.
##
##  The library supports generating and inspecting code objects that
##  contain machine code for a certain set of instruction set
##  arhitectures (isa). The set of isa supported and information about
##  the properties of the isa can be queried.
##
##  The library supports performing an action that can take data
##  objects of one kind, and generate new data objects of another kind.
##
##  Data objects are referenced using handles using @p
##  amd_comgr_data_t. The kinds of data objects are given
##  by @p amd_comgr_data_kind_t.
##
##  To perform an action, two @p amd_comgr_data_set_t
##  objects are created. One is used to hold all the data objects
##  needed by an action, and other is updated by the action with all
##  the result data objects. In addition, an @p
##  amd_comgr_action_info_t is created to hold
##  information that controls the action. These are then passed to @p
##  amd_comgr_do_action to perform an action specified by
##  @p amd_comgr_action_kind_t.
##
##  Some data objects can have associated metadata. There are
##  operations for querying this metadata.
##
##  The default device library that satisfies the requirements of the
##  compiler action can be obtained.
##
##  The library inspects some environment variables to aid in debugging. These
##  include:
##  - @p AMD_COMGR_SAVE_TEMPS: If this is set, and is not "0", the library does
##    not delete temporary files generated while executing compilation actions.
##    These files do not appear in the current working directory, but are
##    instead left in a platform-specific temporary directory (/tmp on Linux and
##    C:\Temp or the path found in the TEMP environment variable on Windows).
##  - @p AMD_COMGR_REDIRECT_LOGS: If this is not set, or is set to "0", logs are
##    returned to the caller as normal. If this is set to "stdout"/"-" or
##    "stderr", logs are instead redirected to the standard output or error
##    stream, respectively. If this is set to any other value, it is interpreted
##    as a filename which logs should be appended to. Logs may be redirected
##    irrespective of whether logging is enabled.
##  - @p AMD_COMGR_EMIT_VERBOSE_LOGS: If this is set, and is not "0", logs will
##    include additional Comgr-specific informational messages.
##
##
##  @brief Status codes.

type
  ComgrStatus* {.size: sizeof(cint).}  = enum
    # From amd_comgr_status_t
    AMD_COMGR_STATUS_SUCCESS = 0x0, ## The function has been executed successfully.
    AMD_COMGR_STATUS_ERROR = 0x1, ## A generic error has occurred.
    AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT = 0x2,
      ##  One of the actual arguments does not meet a precondition stated
      ##  in the documentation of the corresponding formal argument. This
      ##  includes both invalid Action types, and invalid arguments to
      ##  valid Action types.
    AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES = 0x3 ##  Failed to allocate the necessary resources.

type
  ComgrDataKind* {.size: sizeof(cint).} = enum
    # From amd_comgr_data_kind_t
    AMD_COMGR_DATA_KIND_UNDEF = 0x0,       ## No data is available.
    AMD_COMGR_DATA_KIND_SOURCE = 0x1,      ## The data is a textual main source.
    AMD_COMGR_DATA_KIND_INCLUDE = 0x2,
      ##  The data is a textual source that is included in the main source
      ##  or other include source.
    AMD_COMGR_DATA_KIND_PRECOMPILED_HEADER = 0x3,
      ##  The data is a precompiled-header source that is included in the main
      ##  source or other include source.
    AMD_COMGR_DATA_KIND_DIAGNOSTIC = 0x4,  ##  The data is a diagnostic output.
    AMD_COMGR_DATA_KIND_LOG = 0x5,         ## The data is a textual log output.
    AMD_COMGR_DATA_KIND_BC = 0x6,          ## The data is compiler LLVM IR bit code for a specific isa.
    AMD_COMGR_DATA_KIND_RELOCATABLE = 0x7, ## The data is a relocatable machine code object for a specific isa.
    AMD_COMGR_DATA_KIND_EXECUTABLE = 0x8,
      ##  The data is an executable machine code object for a specific
      ##  isa. An executable is the kind of code object that can be loaded
      ##  and executed.
    AMD_COMGR_DATA_KIND_BYTES = 0x9,       ## The data is a block of bytes.
    AMD_COMGR_DATA_KIND_FATBIN = 0x10,     ## The data is a fat binary (clang-offload-bundler output).
    AMD_COMGR_DATA_KIND_AR = 0x11,         ##  The data is an archive.
    AMD_COMGR_DATA_KIND_BC_BUNDLE = 0x12,  ## The data is a bundled bitcode.
    AMD_COMGR_DATA_KIND_AR_BUNDLE = 0x13   ## The data is a bundled archive.



type
  ComGrActionKind* {.size: sizeof(cint).} = enum
    ##
    ##  @brief The kinds of actions that can be performed.
    ##
    # From amd_comgr_action_kind_t
    AMD_COMGR_ACTION_SOURCE_TO_PREPROCESSOR = 0x0,
      ##  Preprocess each source data object in @p input in order. For each
      ##  successful preprocessor invocation, add a source data object to @p result.
      ##  Resolve any include source names using the names of include data objects
      ##  in @p input. Resolve any include relative path names using the working
      ##  directory path in @p info. Preprocess the source for the language in @p
      ##  info.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any preprocessing fails.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name or language is not set in @p info.
    AMD_COMGR_ACTION_ADD_PRECOMPILED_HEADERS = 0x1,
      ##  Copy all existing data objects in @p input to @p output, then add the
      ##  device-specific and language-specific precompiled headers required for
      ##  compilation.
      ##
      ##  Currently the only supported languages are @p AMD_COMGR_LANGUAGE_OPENCL_1_2
      ##  and @p AMD_COMGR_LANGUAGE_OPENCL_2_0.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT if isa name or language
      ##  is not set in @p info, or the language is not supported.
    AMD_COMGR_ACTION_COMPILE_SOURCE_TO_BC = 0x2,
      ##  Compile each source data object in @p input in order. For each
      ##  successful compilation add a bc data object to @p result. Resolve
      ##  any include source names using the names of include data objects
      ##  in @p input. Resolve any include relative path names using the
      ##  working directory path in @p info. Produce bc for isa name in @p
      ##  info. Compile the source for the language in @p info.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any compilation
      ##  fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name or language is not set in @p info.
    AMD_COMGR_ACTION_ADD_DEVICE_LIBRARIES = 0x3,
      ##  Copy all existing data objects in @p input to @p output, then add the
      ##  device-specific and language-specific bitcode libraries required for
      ##  compilation.
      ##
      ##  Currently the only supported languages are @p AMD_COMGR_LANGUAGE_OPENCL_1_2,
      ##  @p AMD_COMGR_LANGUAGE_OPENCL_2_0, and @p AMD_COMGR_LANGUAGE_HIP.
      ##
      ##  The options in @p info should be set to a set of language-specific flags.
      ##  For OpenCL and HIP these include:
      ##
      ##     correctly_rounded_sqrt
      ##     daz_opt
      ##     finite_only
      ##     unsafe_math
      ##     wavefrontsize64
      ##
      ##  For example, to enable daz_opt and unsafe_math, the options should be set
      ##  as:
      ##
      ##     const char *options[] = {"daz_opt, "unsafe_math"};
      ##     size_t optionsCount = sizeof(options) / sizeof(options[0]);
      ##
      ## amd_comgr_action_info_set_option_list(info, options, optionsCount);
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT if isa name or language
      ##  is not set in @p info, the language is not supported, an unknown
      ##  language-specific flag is supplied, or a language-specific flag is
      ##  repeated.
      ##
      ##  @deprecated since 1.7
      ##  @warning This action, followed by @c AMD_COMGR_ACTION_LINK_BC_TO_BC, may
      ##  result in subtle bugs due to incorrect linking of the device libraries.
      ##  The @c
      ## AMD_COMGR_ACTION_COMPILE_SOURCE_WITH_DEVICE_LIBS_TO_BC action can
      ##  be used as a workaround which ensures the link occurs correctly.
    AMD_COMGR_ACTION_LINK_BC_TO_BC = 0x4, ##
      ##  Link a collection of bitcodes, bundled bitcodes, and bundled bitcode
      ##  archives in @p into a single composite (unbundled) bitcode @p.
      ##  Any device library bc data object must be explicitly added to @p input if
      ##  needed.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if the link or unbundling fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all bc data objects in @p input.
    AMD_COMGR_ACTION_OPTIMIZE_BC_TO_BC = 0x5,
      ##  Optimize each bc data object in @p input and create an optimized bc data
      ##  object to @p result.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if the optimization fails.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all bc data objects in @p input.
    AMD_COMGR_ACTION_CODEGEN_BC_TO_RELOCATABLE = 0x6,
      ##  Perform code generation for each bc data object in @p input in
      ##  order. For each successful code generation add a relocatable data
      ##  object to @p result.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any code
      ##  generation fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all bc data objects in @p input.
    AMD_COMGR_ACTION_CODEGEN_BC_TO_ASSEMBLY = 0x7,
      ##  Perform code generation for each bc data object in @p input in
      ##  order. For each successful code generation add an assembly source data
      ##  object to @p result.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any code
      ##  generation fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all bc data objects in @p input.
    AMD_COMGR_ACTION_LINK_RELOCATABLE_TO_RELOCATABLE = 0x8,
      ##  Link each relocatable data object in @p input together and add
      ##  the linked relocatable data object to @p result. Any device
      ##  library relocatable data object must be explicitly added to @p
      ##  input if needed.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if the link fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all relocatable data objects in @p input.
    AMD_COMGR_ACTION_LINK_RELOCATABLE_TO_EXECUTABLE = 0x9,
      ##  Link each relocatable data object in @p input together and add
      ##  the linked executable data object to @p result. Any device
      ##  library relocatable data object must be explicitly added to @p
      ##  input if needed.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if the link fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all relocatable data objects in @p input.
    AMD_COMGR_ACTION_ASSEMBLE_SOURCE_TO_RELOCATABLE = 0xA,
      ##  Assemble each source data object in @p input in order into machine code.
      ##  For each successful assembly add a relocatable data object to @p result.
      ##  Resolve any include source names using the names of include data objects in
      ##  @p input. Resolve any include relative path names using the working
      ##  directory path in @p info. Produce relocatable for isa name in @p info.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any assembly fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT if isa name is not set in
      ##  @p info.
    AMD_COMGR_ACTION_DISASSEMBLE_RELOCATABLE_TO_SOURCE = 0xB,
      ##  Disassemble each relocatable data object in @p input in
      ##  order. For each successful disassembly add a source data object to
      ##  @p result.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any disassembly
      ##  fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all relocatable data objects in @p input.
    AMD_COMGR_ACTION_DISASSEMBLE_EXECUTABLE_TO_SOURCE = 0xC,
      ##  Disassemble each executable data object in @p input in order. For
      ##  each successful disassembly add a source data object to @p result.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR if any disassembly
      ##  fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info and does not match the isa name
      ##  of all relocatable data objects in @p input.
    AMD_COMGR_ACTION_DISASSEMBLE_BYTES_TO_SOURCE = 0xD,
      ##  Disassemble each bytes data object in @p input in order. For each
      ##  successful disassembly add a source data object to @p
      ##  result. Only simple assembly language commands are generate that
      ##  corresponf to raw bytes are supported, not any directives that
      ##  control the code object layout, or symbolic branch targets or
      ##  names.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any disassembly
      ##  fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name is not set in @p info
    AMD_COMGR_ACTION_COMPILE_SOURCE_TO_FATBIN = 0xE,
      ##  Compile each source data object in @p input in order. For each
      ##  successful compilation add a fat binary to @p result. Resolve
      ##  any include source names using the names of include data objects
      ##  in @p input. Resolve any include relative path names using the
      ##  working directory path in @p info. Produce fat binary for isa name in @p
      ##  info. Compile the source for the language in @p info.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any compilation
      ##  fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name or language is not set in @p info.
      ##
      ##  @deprecated since 2.5
      ##  @see in-process compilation via
      ## AMD_COMGR_ACTION_COMPILE_SOURCE_TO_BC, etc.
      ##  instead

    AMD_COMGR_ACTION_COMPILE_SOURCE_WITH_DEVICE_LIBS_TO_BC = 0xF
      ##  Compile each source data object in @p input in order. For each
      ##  successful compilation add a bc data object to @p result. Resolve
      ##  any include source names using the names of include data objects
      ##  in @p input. Resolve any include relative path names using the
      ##  working directory path in @p info. Produce bc for isa name in @p
      ##  info. Compile the source for the language in @p info. Link against
      ##  the device-specific and language-specific bitcode device libraries
      ##  required for compilation.
      ##
      ##  Return @p AMD_COMGR_STATUS_ERROR if any compilation
      ##  fails.
      ##
      ##  Return @p
      ## AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT
      ##  if isa name or language is not set in @p info.

type
  ComgrData* {.bycopy.} = object
    ##  @brief A handle to a data object.
    ##
    ##  Data objects are used to hold the data which is either an input or
    ##  output of a code object manager action.
    # From amd_comgr_data_t
    handle*: uint64

  ComgrActionInfo* {.bycopy.} = object
    ##  @brief A handle to an action information object.
    ##
    ##  An action information object holds all the necessary information,
    ##  excluding the input data objects, required to perform an action.
    # From amd_comgr_action_info_t
    handle*: uint64

type
  ComgrDataset* {.bycopy.} = object
    ##  @brief A handle to an action information object.
    ##
    ##  An action information object holds all the necessary information,
    ##  excluding the input data objects, required to perform an action.
    # From amd_comgr_data_set_t
    handle*: uint64


const libPath = "/opt/rocm/lib/" # For now, only support Linux
static: echo "[Constantine] Will search AMD Comgr in $LD_LIBRARY_PATH and " & libPath & "libamd_comgr.so"
const libAmdComgr = "(libamd_comgr.so|" & libPath & "libamd_comgr.so)"

{.push noconv, importc, dynlib: libAmdComgr.}

proc amd_comgr_create_data*(kind: ComgrDataKind; data: var ComgrData): ComgrStatus
  ##  @brief Create a data object that can hold data of a specified kind.
  ##
  ##  Data objects are reference counted and are destroyed when the
  ##  reference count reaches 0. When a data object is created its
  ##  reference count is 1, it has 0 bytes of data, it has an empty name,
  ##  and it has no metadata.
  ##
  ##  @param[in] kind The kind of data the object is intended to hold.
  ##
  ##  @param[out] data A handle to the data object created. Its reference
  ##  count is set to 1.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  kind is an invalid data kind, or @p
  ##  AMD_COMGR_DATA_KIND_UNDEF. @p data is NULL.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to create the data object as out of resources.

proc amd_comgr_release_data*(data: ComgrData): ComgrStatus
  ##  @brief Indicate that no longer using a data object handle.
  ##
  ##  The reference count of the associated data object is
  ##  decremented. If it reaches 0 it is destroyed.
  ##
  ##  @param[in] data The data object to release.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  data is an invalid data object, or has kind @p
  ##  AMD_COMGR_DATA_KIND_UNDEF.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update the data object as out of resources.

proc amd_comgr_set_data*(data: ComgrData; size: csize_t; bytes: pointer): ComgrStatus
  ##  @brief Set the data content of a data object to the specified
  ##  bytes.
  ##
  ##  Any previous value of the data object is overwritten. Any metadata
  ##  associated with the data object is also replaced which invalidates
  ##  all metadata handles to the old metadata.
  ##
  ##  @param[in] data The data object to update.
  ##
  ##  @param[in] size The number of bytes in the data specified by @p bytes.
  ##
  ##  @param[in] bytes The bytes to set the data object to. The bytes are
  ##  copied into the data object and can be freed after the call.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  data is an invalid data object, or has kind @p
  ##  AMD_COMGR_DATA_KIND_UNDEF.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update the data object as out of resources.

proc amd_comgr_set_data_name*(data: ComgrData; name: cstring): ComgrStatus
  ##  @brief Set the name associated with a data object.
  ##
  ##  When compiling, the full name of an include directive is used to
  ##  reference the contents of the include data object with the same
  ##  name. The name may also be used for other data objects in log and
  ##  diagnostic output.
  ##
  ##  @param[in] data The data object to update.
  ##
  ##  @param[in] name A null terminated string that specifies the name to
  ##  use for the data object. If NULL then the name is set to the empty
  ##  string.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  data is an invalid data object, or has kind @p
  ##  AMD_COMGR_DATA_KIND_UNDEF.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update the data object as out of resources.

proc amd_comgr_get_data*(data: ComgrData; size: var csize_t; bytes: pointer): ComgrStatus
  ##  @brief Get the data object name and/or name length.
  ##
  ##  @param[in] data The data object to query.
  ##
  ##  @param[in, out] size On entry, the size of @p name. On return, the size of
  ##  the data object name including the terminating null character.
  ##
  ##  @param[out] name If not NULL, then the first @p size characters of the
  ##  data object name are copied. If @p name is NULL, only @p size is updated
  ##  (useful in order to find the size of buffer required to copy the name).
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  data is an invalid data object, or has kind @p
  ##  AMD_COMGR_DATA_KIND_UNDEF. @p size is NULL.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update the data object as out of resources.

proc amd_comgr_create_action_info*(action_info: var ComgrActionInfo): ComgrStatus
  ##  @brief Create an action info object.
  ##
  ##  @param[out] action_info A handle to the action info object created.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  action_info is NULL.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to create the action info object as out of resources.

proc amd_comgr_destroy_action_info*(action_info: ComgrActionInfo): ComgrStatus
  ##  @brief Destroy an action info object.
  ##
  ##  @param[in] action_info A handle to the action info object to destroy.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  action_info is an invalid action info object.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update action info object as out of resources.

proc amd_comgr_action_info_set_isa_name*(action_info: ComgrActionInfo;
                                        isa_name: cstring): ComgrStatus

  ##  @brief Set the isa name of an action info object.
  ##
  ##  When an action info object is created it has no isa name. Some
  ##  actions require that the action info object has an isa name
  ##  defined.
  ##
  ##  @param[in] action_info A handle to the action info object to be
  ##  updated.
  ##
  ##  @param[in] isa_name A null terminated string that is the isa name. If NULL
  ##  or the empty string then the isa name is cleared. The isa name is defined as
  ##  the Code Object Target Identification string, described at
  ##  https://llvm.org/docs/AMDGPUUsage.html#code-object-target-identification
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  action_info is an invalid action info object. @p isa_name is not an
  ##  isa name supported by this version of the code object manager
  ##  library.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update action info object as out of resources.
  ##
  ## -----
  ## Example ISA: "amdgcn-amd-amdhsa--gfx900"

proc amd_comgr_create_data_set*(data_set: var ComgrDataset): ComgrStatus
  ##  @brief Create a data set object.
  ##
  ##  @param[out] data_set A handle to the data set created. Initially it
  ##  contains no data objects.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has been executed
  ##  successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p data_set is NULL.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES Unable to create the data
  ##  set object as out of resources.

proc amd_comgr_destroy_data_set*(data_set: ComgrDataset): ComgrStatus
  ##  @brief Destroy a data set object.
  ##
  ##  The reference counts of any associated data objects are decremented. Any
  ##  handles to the data set object become invalid.
  ##
  ##  @param[in] data_set A handle to the data set object to destroy.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has been executed
  ##  successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p data_set is an invalid
  ##  data set object.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES Unable to update data set
  ##  object as out of resources.

proc amd_comgr_data_set_add*(data_set: ComgrDataset; data: ComgrData): ComgrStatus
  ##  @brief Add a data object to a data set object if it is not already added.
  ##
  ##  The reference count of the data object is incremented.
  ##
  ##  @param[in] data_set A handle to the data set object to be updated.
  ##
  ##  @param[in] data A handle to the data object to be added. If @p data_set
  ##  already has the specified handle present, then it is not added. The order
  ##  that data objects are added is preserved.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has been executed
  ##  successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p data_set is an invalid
  ##  data set object. @p data is an invalid data object; has undef kind; has
  ##  include kind but does not have a name.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES Unable to update data set
  ##  object as out of resources.

proc amd_comgr_do_action*(kind: ComGrActionKind;
                         info: ComgrActionInfo;
                         input: ComgrDataset; output: ComgrDataset): ComgrStatus

  ##  @brief Perform an action.
  ##
  ##  Each action ignores any data objects in @p input that it does not
  ##  use. If logging is enabled in @info then @p result will have a log
  ##  data object added. Any diagnostic data objects produced by the
  ##  action will be added to @p result. See the description of each
  ##  action in @p amd_comgr_action_kind_t.
  ##
  ##  @param[in] kind The action to perform.
  ##
  ##  @param[in] info The action info to use when performing the action.
  ##
  ##  @param[in] input The input data objects to the @p kind action.
  ##
  ##  @param[out] result Any data objects are removed before performing
  ##  the action which then adds all data objects produced by the action.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has
  ##  been executed successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR An error was
  ##  reported when executing the action.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p
  ##  kind is an invalid action kind. @p input_data or @p result_data are
  ##  invalid action data object handles. See the description of each
  ##  action in @p amd_comgr_action_kind_t for other
  ##  conditions that result in this status.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES
  ##  Unable to update the data object as out of resources.

proc amd_comgr_action_data_get_data*(data_set: ComgrDataset;
                                    data_kind: ComgrDataKind;
                                    index: csize_t; data: var ComgrData): ComgrStatus
  ##  @brief Return the Nth data object of a specified data kind that is added to a
  ##  data set object.
  ##
  ##  The reference count of the returned data object is incremented.
  ##
  ##  @param[in] data_set A handle to the data set object to be queried.
  ##
  ##  @param[in] data_kind The data kind of the data object to be returned.
  ##
  ##  @param[in] index The index of the data object of data kind @data_kind to be
  ##  returned. The first data object is index 0. The order of data objects matches
  ##  the order that they were added to the data set object.
  ##
  ##  @param[out] data The data object being requested.
  ##
  ##  @retval ::AMD_COMGR_STATUS_SUCCESS The function has been executed
  ##  successfully.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT @p data_set is an invalid
  ##  data set object. @p data_kind is an invalid data kind or @p
  ##  AMD_COMGR_DATA_KIND_UNDEF. @p index is greater than the number of data
  ##  objects of kind @p data_kind. @p data is NULL.
  ##
  ##  @retval ::AMD_COMGR_STATUS_ERROR_OUT_OF_RESOURCES Unable to query data set
  ##  object as out of resources.

{.pop.} # noconv, importc, dynlib: libAmdComgr
