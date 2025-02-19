# This file is taken from `nimcuda`.

##[This module implements some auto-detection of cuda installation locations,
   as well as communication with the c compilers about this info.

   If you want to manually overide the autodetection, pass the nim compiler
   `-d:CudaLib="PATH_TO_CUDA_DYN_LIBS"` and/or
   `-d:CudaIncludes="PATH_TO_CUDA_HEADERS"`.
]##

#[The following is a rip of std/distros, slightly modified for compile-time
  use.
  The extra specificity compared to normal `defined` tests or `hostOS`
  is needed because some linux distros install cuda in very different places
  (im looking at you, arch!)
]#


from std/distros import Distribution
import std/[os, strutils, macros, macrocache]
when NimMajor == 2:
  import std/envvars


# we cache the result of the 'cmdRelease'
# execution for faster platform detections.
var
  unameRes {.compileTime.}: string
  osReleaseIDRes {.compileTime.}: string
  releaseRes {.compileTime.}: string
  hostnamectlRes {.compileTime.}: string

template cmdRelease(cmd, cache): untyped =
  if cache.len == 0:
    # cache = (when defined(nimscript): gorge(cmd) else: execProcess(cmd))
    cache = gorge(cmd)
  cache

template uname(): untyped = cmdRelease("uname -a", unameRes)
template osReleaseID(): untyped =
  cmdRelease("cat /etc/os-release | grep ^ID=", osReleaseIDRes)
template release(): untyped = cmdRelease("lsb_release -d", releaseRes)
template hostnamectl(): untyped = cmdRelease("hostnamectl", hostnamectlRes)

proc detectOsWithAllCmd(d: Distribution): bool {.compileTime.} =
  let dd = toLowerAscii($d)
  result = dd in toLowerAscii(osReleaseID()) or dd in toLowerAscii(release()) or
            dd in toLowerAscii(uname()) or ("operating system: " & dd) in
                toLowerAscii(hostnamectl())

proc detectOsImpl(d: Distribution): bool {.compileTime.} =
  case d
  of Distribution.Windows: result = defined(windows)
  of Distribution.Posix: result = defined(posix)
  of Distribution.MacOSX: result = defined(macosx)
  of Distribution.Linux: result = defined(linux)
  of Distribution.BSD: result = defined(bsd)
  else:
    when defined(bsd):
      case d
      of Distribution.FreeBSD, Distribution.NetBSD, Distribution.OpenBSD:
        result = $d in uname()
      else:
        result = false
    elif defined(linux):
      const EasyLinux = when (NimMajor, NimMinor) >= (1, 6):
          {Distribution.Elementary, Distribution.Ubuntu, Distribution.Debian,
          Distribution.Fedora, Distribution.OpenMandriva, Distribution.CentOS,
          Distribution.Alpine, Distribution.Mageia, Distribution.Zorin,
          Distribution.Void}
        else:
          {Distribution.Elementary, Distribution.Ubuntu, Distribution.Debian,
          Distribution.Fedora, Distribution.OpenMandriva, Distribution.CentOS,
          Distribution.Alpine, Distribution.Mageia, Distribution.Zorin}

      case d
      of Distribution.Gentoo:
        result = ("-" & $d & " ") in uname()
      of EasyLinux:
        result = toLowerAscii($d) in osReleaseID()
      of Distribution.RedHat:
        result = "rhel" in osReleaseID()
      of Distribution.ArchLinux:
        result = "arch" in osReleaseID()
      # when (NimMajor, NimMinor) >= (1, 6):
      #   of Distribution.Artix:
      #     result = "artix" in osReleaseID()
      of Distribution.NixOS:
        # Check if this is a Nix build or NixOS environment
        result = existsEnv("NIX_BUILD_TOP") or
          existsEnv("__NIXOS_SET_ENVIRONMENT_DONE")
      of Distribution.OpenSUSE:
        result = "suse" in toLowerAscii(uname()) or
          "suse" in toLowerAscii(release())
      of Distribution.GoboLinux:
        result = "-Gobo " in uname()
      of Distribution.Solaris:
        let uname = toLowerAscii(uname())
        result = ("sun" in uname) or ("solaris" in uname)
      of Distribution.Haiku:
        result = defined(haiku)
      else:
        result = detectOsWithAllCmd(d)
    else:
      result = false

template detectOs(d: untyped): bool =
  ## Distro/OS detection. For convenience, the
  ## required `Distribution.` qualifier is added to the
  ## enum value.
  detectOsImpl(Distribution.d)



# begin actual detection
when detectOs(Windows):
  from std/os import getEnv, `/`
  const
    CudaPath = getEnv("CUDA_PATH")
    CudaIncludes* {.strdefine.} = CudaPath / "include"
    CudaLib* {.strdefine.} = CudaPath / "lib64"

elif detectOs(ArchLinux):
  from std/os import `/`
  const
    CudaPath = "/opt/cuda"
    CudaIncludes* {.strdefine.} = CudaPath / "include"
    CudaLib* {.strdefine.} = CudaPath / "lib64"

elif detectOs(Linux):
  # Generic linux catch-all.
  # This includes anyone following the cuda installation guide.
  const
    CudaPath = "/usr/local/cuda"
    CudaIncludes* {.strdefine.} = CudaPath / "include"
    CudaLib* {.strdefine.} = CudaPath / "lib64"

else:
  # Some wild operating system!
  const
    CudaIncludes* {.strdefine.} = "unknown"
    CudaLib* {.strdefine.} = "unknown"


# check for validity
when not dirExists(CudaIncludes):
  {.error: "Could not find the cuda source headers! Please specify the " &
     "location of the cuda includes directory by passing " &
     "`-d:CudaIncludes=\"YOUR_PATH\"` to the nim compiler.".}
elif not dirExists(CudaLib):
  {.error: "Could not find the cuda shared libraries! Please specify the " &
     "location of the cuda library directory by passing " &
     "`-d:CudaLib=\"YOUR_PATH\"` to the nim compiler.".}



macro tellCompilerToUseCuda*(): untyped =
  ## Tells the compiler and linker to use cuda libraries.
  # we'll use macrocaching so that we dont unneccessarily emit a million times

  const ToldCompilerCount = CacheCounter"ToldCompilerToUseCudaCount"
  if ToldCompilerCount.value == 0:
    result = quote do:
      {.passC: "-I" & CudaIncludes.}
      {.passL: "-L" & CudaLib & " -lcuda".}
    inc ToldCompilerCount
