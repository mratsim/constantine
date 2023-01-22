# Weave
# Copyright (c) 2019 Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

when defined(linux):
  import ./futex_linux
  export futex_linux
elif defined(windows):
  import ./futex_windows
  export futex_windows
elif defined(macos):
  import ./futex_darwin
  export futex_darwin
else:
  import ./futex_generic
  export futex_generic