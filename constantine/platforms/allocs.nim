# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                        Allocators
#
# ############################################################

# Due to the following constraints:
# - No dynamic allocation in single-threaded codepaths (for compatibility with embedded devices like TPM or secure hardware)
# - Avoiding cryptographic material in third-party libraries (like a memory allocator)
# - Giving full control of the library user on allocation strategy
# - Performance, especially for long-running processes (fragmentation, multithreaded allocation...)
#
# stack allocation is strongly preferred where necessary.

when defined(windows):
  proc alloca(size: int): pointer {.header: "<malloc.h>".}
else:
  proc alloca(size: int): pointer {.header: "<alloca.h>".}

template alloca*(T: typedesc): ptr T =
  cast[ptr T](alloca(sizeof(T)))

template alloca*(T: typedesc, len: Natural): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](alloca(sizeof(T) * len))