# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/platforms/loadtime_functions

# When Constantine is built as a library, we want to minimize friction of using it.
# Hence we want to users to be able to directly use it without special ceremony.
#
# This is possible for dynamic libraries if --noMain isn't used.
#
#   https://github.com/nim-lang/Nim/blob/v2.0.0/compiler/cgen.nim#L1572-L1583
#   https://github.com/nim-lang/Nim/blob/v2.0.0/lib/nimbase.h#L513
#
# The function DllMain is autoloaded on Windows
# Functions tagged __attribute__((constructor)) are autoloaded on UNIX OSes
#
# Alas, Nim doesn't provide such facilities for static libraries
# so we provide our own {.loadTime.} macro for autoloading:
# - any proc
# - on any OS
# - whether using a dynamic or static library
#
# We use them for runtime CPU features detection.
#
# And on Windows as functions in DLLs (kernel APIs for the threadpool for example) are loaded
# as global variables

when defined(windows) and (appType == "lib" or appType == "staticlib"):
  proc ctt_init_NimMain() {.importc, cdecl.}
    ## Setup Nim globals, including loading library dependencies on Windows
    ## We assume that Constantine was compiled with --nimMainPrefix:ctt_init_

  proc ctt_autoload_NimMain() {.load_time.} =
    ## Autosetup Constantine globals on library load.
    ## This must be referenced from an another module
    ## to not be optimized away by the static linker
    ctt_init_NimMain()

  proc ctt_autoloader_addr*(): pointer =
    ## This returns an runtime reference to the autoloader
    ## so that it cannot be optimized away.
    ## Compare it with "nil"
    cast[pointer](ctt_autoload_NimMain)
