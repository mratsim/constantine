# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                       File IO
#
# ############################################################

# We create our own File IO primitives on top of <stdio.h>
# We do not use std/syncio or std/streams
# as we do not use Nim memory allocator and exceptions.

# Ensure all exceptions are converted to error codes
{.push raises: [], checks: off.}

# Datatypes
# ------------------------------------------------------------

type
  FileSeekFrom {.size: sizeof(cint).} = enum
    ## SEEK_SET, SEEK_CUR and SEEK_END in stdio.h
    kAbsolute
    kCurrent
    kEnd

  FileMode* = enum
    # We always use binary mode for files for universality.
    kRead           # Open a file for reading in binary mode. File must exist.
    kOverwrite      # Open a file for overwriting in binary mode. If file exists it is cleared, otherwise it is created.
    kAppend         # Open a file for writing in binary mode. If file exists data is appended, otherwise it is created.
    kReadWrite      # Open a fil for read-write in binary mode. File must exist.
    kReadOverwrite  # Open a file for read-overwrite in binary mode. If file exists it is cleared, otherwise it is created.

const
  childProcNoInherit = block:
    # Child processes should not inherit open files
    when defined(windows):
      "N"
    elif defined(linux) or defined(bsd):
      "e"
    else:
      ""

  MapFileMode = [
    # We want to ensure no dynamic alloc at runtime with strings
    kRead:          cstring("rb"  & childProcNoInherit),
    kOverwrite:     cstring("wb"  & childProcNoInherit),
    kAppend:        cstring("ab"  & childProcNoInherit),
    kReadWrite:     cstring("rb+" & childProcNoInherit),
    kReadOverwrite: cstring("wb+" & childProcNoInherit)
  ]

# Opening/Closing files
# ------------------------------------------------------------

proc c_fopen(filepath, mode: cstring): File {.importc: "fopen", header: "<stdio.h>", sideeffect.}
proc c_fclose(f: File): cint {.importc: "fclose", header: "<stdio.h>", sideeffect.}
proc c_fflush*(f: File) {.importc: "fflush", header: "<stdio.h>", sideeffect, tags:[WriteIOEffect].}

when defined(windows):
  proc c_fileno(f: File): cint {.importc: "_fileno", header: "<stdio.h>", sideeffect.}
else:
  type
    Mode {.importc: "mode_t", header: "<sys/types.h>".} = cint
    Stat {.importc: "struct stat", header: "<sys/stat.h>", final, pure.} = object
      st_mode: Mode
  proc is_dir(m: Mode): bool {.importc: "S_ISDIR", header: "<sys/stat.h>".}
  proc c_fileno(f: File): cint {.importc: "fileno", header: "<fcntl.h>", sideeffect.}
  proc c_fstat(a1: cint, a2: var Stat): cint {.importc: "fstat", header: "<sys/stat.h>", sideeffect.}

proc close*(f: File) =
  if not f.isNil:
    discard f.c_fclose()

proc open*(f: var File, filepath: cstring, mode = kRead): bool =
  f = c_fopen(filepath, MapFileMode[mode])
  if f.isNil:
    return false

  # Posix OSes can open directories, prevent that.
  when defined(posix):
    var stat {.noInit.}: Stat
    if c_fstat(c_fileno(f), stat) >= 0 and stat.st_mode.is_dir:
      f.close()
      return false

  return true


# Navigating files
# ------------------------------------------------------------

when defined(windows):
  proc getFilePosition*(f: File): int64 {.importc: "_ftelli64", header: "<stdio.h>", sideeffect.}
  proc setFilePosition*(f: File, offset: int64, relative = kAbsolute): cint {.importc: "_fseeki64", header: "<stdio.h>", sideeffect.}
else:
  proc getFilePosition*(f: File): int64 {.importc: "ftello", header: "<stdio.h>", sideeffect.}
  proc setFilePosition*(f: File, offset: int64, relative = kAbsolute): cint {.importc: "fseeko", header: "<stdio.h>", sideeffect.}

# Reading files
# ------------------------------------------------------------

proc c_fread(buffer: pointer, len, count: csize_t, f: File): csize_t {.importc: "fread", header: "<stdio.h>", sideeffect, tags:[ReadIOEffect].}

proc readInto*(f: File, buffer: pointer, len: int): int =
  ## Read data into buffer, return the number of bytes read
  cast[int](c_fread(buffer, 1, cast[csize_t](len), f))

proc readInto*[T](f: File, buf: var T): bool =
  ## Read data into buffer,
  ## return true if the number of bytes read
  ## matches the output type size
  return f.readInto(buf.addr, sizeof(buf)) == sizeof(T)

proc read*(f: File, T: typedesc): T =
  ## Interpret next bytes as type `T`
  ## Panics if the number of bytes read does not match
  ## the size of `T`
  let ok = f.readInto(result)
  doAssert ok, "Fatal error when reading '" & $T & "' from file."

# Parsing files
# ------------------------------------------------------------

proc c_fscanf*(f: File, format: cstring): cint{.importc:"fscanf", header: "<stdio.h>", varargs, sideeffect, tags:[ReadIOEffect].}
  ## Note: The "format" parameter and followup arguments MUST NOT be forgotten
  ##       to not be exposed to the "format string attacks"

# Formatted print
# ------------------------------------------------------------

proc c_printf*(fmt: cstring): cint {.sideeffect, importc: "printf", header: "<stdio.h>", varargs, discardable, tags:[WriteIOEffect].}
func c_snprintf*(dst: cstring, maxLen: csize_t, format: cstring): cint {.importc:"snprintf", header: "<stdio.h>", varargs.}
  ## dst is really a `var` parameter, but Nim var are lowered to pointer hence unsuitable here.
  ## Note: The "format" parameter and followup arguments MUST NOT be forgotten
  ##       to not be exposed to the "format string attacks"
