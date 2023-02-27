# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises:[].}  # No exceptions for crypto
{.push checks:off.} # No int->size_t exceptions

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

# We use Nim effect system to track allocating subroutines
type
  Alloca*    = object
  HeapAlloc* = object

# Bindings
# ----------------------------------------------------------------------------------
# We wrap them with int instead of size_t / csize_t

when defined(windows):
  proc alloca(size: int): pointer {.tags:[Alloca], header: "<malloc.h>".}
else:
  proc alloca(size: int): pointer {.tags:[Alloca], header: "<alloca.h>".}

proc malloc(size: int): pointer {.tags:[HeapAlloc], header: "<stdlib.h>".}
proc free(p: pointer) {.tags:[HeapAlloc], header: "<stdlib.h>".}

when defined(windows):
  proc aligned_alloc_windows(size, alignment: int): pointer {.tags:[HeapAlloc],importc:"_aligned_malloc", header:"<malloc.h>".}
    # Beware of the arg order!
  proc aligned_alloc(alignment, size: int): pointer {.inline.} =
    aligned_alloc_windows(size, alignment)
  proc aligned_free(p: pointer){.tags:[HeapAlloc],importc:"_aligned_free", header:"<malloc.h>".}
elif defined(osx):
  proc posix_memalign(mem: var pointer, alignment, size: int){.tags:[HeapAlloc],importc, header:"<stdlib.h>".}
  proc aligned_alloc(alignment, size: int): pointer {.inline.} =
    posix_memalign(result, alignment, size)
  proc aligned_free(p: pointer) {.tags:[HeapAlloc], importc: "free", header: "<stdlib.h>".}
else:
  proc aligned_alloc(alignment, size: int): pointer {.tags:[HeapAlloc],importc, header:"<stdlib.h>".}
  proc aligned_free(p: pointer) {.tags:[HeapAlloc], importc: "free", header: "<stdlib.h>".}

# Helpers
# ----------------------------------------------------------------------------------

proc isPowerOfTwo(n: int): bool {.inline.} =
  (n and (n - 1)) == 0 and (n != 0)

func roundNextMultipleOf(x: int, n: static int): int {.inline.} =
  ## Round the input to the next multiple of "n"
  when n.isPowerOfTwo():
    # n is a power of 2. (If compiler cannot prove that x>0 it does not make the optim)
    result = (x + n - 1) and not(n - 1)
  else:
    result = x.ceilDiv_vartime(n) * n

# Stack allocation
# ----------------------------------------------------------------------------------

template allocStack*(T: typedesc): ptr T =
  cast[ptr T](alloca(sizeof(T)))

template allocStackUnchecked*(T: typedesc, size: int): ptr T =
  ## Stack allocation for types containing a variable-sized UncheckedArray field
  cast[ptr T](alloca(size))

template allocStackArray*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](alloca(sizeof(T) * cast[int](len)))

# Heap allocation
# ----------------------------------------------------------------------------------

proc allocHeap*(T: typedesc): ptr T {.inline.} =
  cast[type result](malloc(sizeof(T)))

proc allocHeapUnchecked*(T: typedesc, size: int): ptr T {.inline.} =
  ## Heap allocation for types containing a variable-sized UncheckedArray field
  cast[type result](malloc(size))

proc allocHeapArray*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T] {.inline.} =
  cast[type result](malloc(sizeof(T) * cast[int](len)))

proc freeHeap*(p: pointer) {.inline.} =
  free(p)

proc allocHeapAligned*(T: typedesc, alignment: static Natural): ptr T {.inline.} =
  # aligned_alloc requires allocating in multiple of the alignment.
  let # Cannot be static with bitfields. Workaround https://github.com/nim-lang/Nim/issues/19040
    size = sizeof(T)
    requiredMem = size.roundNextMultipleOf(alignment)

  cast[ptr T](aligned_alloc(alignment, requiredMem))

proc allocHeapUncheckedAligned*(T: typedesc, size: int, alignment: static Natural): ptr T {.inline.} =
  ## Aligned heap allocation for types containing a variable-sized UncheckedArray field
  ## or an importc type with missing size information
  # aligned_alloc requires allocating in multiple of the alignment.
  let requiredMem = size.roundNextMultipleOf(alignment)

  cast[ptr T](aligned_alloc(alignment, requiredMem))

proc allocHeapArrayAligned*(T: typedesc, len: int, alignment: static Natural): ptr UncheckedArray[T] {.inline.} =
  # aligned_alloc requires allocating in multiple of the alignment.
  let
    size = sizeof(T) * len
    requiredMem = size.roundNextMultipleOf(alignment)

  cast[ptr UncheckedArray[T]](aligned_alloc(alignment, requiredMem))

proc allocHeapAlignedPtr*(T: typedesc[ptr], alignment: static Natural): T {.inline.} =
  allocHeapAligned(typeof(default(T)[]), alignment)

proc allocHeapUncheckedAlignedPtr*(T: typedesc[ptr], size: int, alignment: static Natural): T {.inline.} =
  ## Aligned heap allocation for types containing a variable-sized UncheckedArray field
  ## or an importc type with missing size information
  allocHeapUncheckedAligned(typeof(default(T)[]), size, alignment)

proc freeHeapAligned*(p: pointer) {.inline.} =
  aligned_free(p)