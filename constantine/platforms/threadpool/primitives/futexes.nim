# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when defined(linux):
  import ./futexes_linux
  export futexes_linux
elif defined(windows):
  import ./futexes_windows
  export futexes_windows
elif defined(osx):
  import ./futexes_macos
  export futexes_macos
else:
  {.error: "Futexes are not implemented for your OS".}
