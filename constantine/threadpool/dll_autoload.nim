# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# To ensure that __attribute__((constructor)) procs are not
# removed because they are unaccessible, we force symbol reference
when defined(windows) and (appType == "lib" or appType == "staticlib"):
  import ../../bindings/lib_autoload
  
  proc check_lib_dependency_loader*() =
    ## This prevents the linker from deleting our constructor function
    ## that loads Windows kernel, synchronization and threading related functions.
    ## We only need to have any symbol in the translation unit being used.
    doAssert ctt_autoloader_addr() != nil
else:
  template check_lib_dependency_loader*() =
    ## This prevents the linker from deleting our constructor function
    ## that loads Windows kernel, synchronization and threading related functions.
    ## We only need to have any symbol in the translation unit being used.
    discard