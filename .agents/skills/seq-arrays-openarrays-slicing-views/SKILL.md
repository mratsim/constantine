---
name: seq-arrays-openarrays-slicing-views
description: Nim seq, arrays, openarray, slicing, and views best practices for zero-allocation cryptographic code
license: MIT
compatibility: opencode
metadata:
  audience: developers
  language: nim
---

## What I do

Provide guidance on working with dynamically-sized buffers in Nim for cryptographic code.

Emphasizes avoiding `seq` in favor of auditable memory management through Constantine's shim over the system allocator.

Avoid Nim slicing syntax `..<` slice syntax on arrays, sequences and openarrays as it creates an intermediate seq, which:
- Causes an avoidable heap allocation
- Allocates using Nim allocator
- Violates no-alloc conventions in cryptographic code that handle secrets
- Can trigger side-channel vulnerabilities

## Why No seq?

We actively avoid memory allocation for any protocol that:
- handle secrets
- could be expected to run in a trusted enclave or embedded devices

This includes encryption, hashing and signatures protocols.

When memory allocation is necessary, for example for multithreading, GPU computing or succinct or zero-knowledge proof protocol, we use custom allocators from `constantine/platforms/allocs.nim`. Those are thin wrappers around the OS `malloc`/`free` with effect tracking `{.tags:[HeapAlloc].}` or `{.tags:[Alloca].}`. Then we can use Nim's effect tracking `{.tags:[].}` to ensure no *heap allocation* or *alloca* is used in the call stack of specific functions.

```nim
# Compiler tracked heap allocation
let ptr = allocHeapArrayAligned(int, 128, alignment = 64)

# Compiler tracked stack allocation
let stackPtr = allocStackArray(int, 128)

# Don't do this in cryptographic code!
let bad = @[1, 2, 3]  # seq - hidden allocation!
```

## Array/View Types Overview

### array[T, U]
- Fixed size, stack-allocated
- Safe for cryptographic constants
- Use `sizeof` to compute total size for heap allocation

### openArray[T]
- A virtual type (ptr + length) passed by value
- Cannot be stored in types or returned from functions
- Slicing with `[a ..< b]` creates an intermediate **seq** (heap allocation!)
- Use .toOpenArray(start, stopInclusive) instead

### ptr UncheckedArray[T]
- Raw pointer to contiguous memory
- Can be stored in types
- Use `cast[ptr UncheckedArray[T]](addr)` or `.asUnchecked()` to convert

### View[T]
- A Nim type storing (ptr + length)
- Can be stored in types or returned from functions
- Convert to openArray via `.toOpenArray` template

### StridedView[T]
- For non-contiguous data (e.g., FFT even/odd splitting)
- Stores: data ptr, length, stride, offset

## Converting Between Types

### openArray to ptr UncheckedArray
```nim
# PREFERRED: Using views.nim (import constantine/platforms/views)
let ptrArr = oa.asUnchecked()

# Alternative: Using cast
let ptrArr = cast[ptr UncheckedArray[T]](oa[0].unsafeAddr)
```

### ptr UncheckedArray to openArray
```nim
# Using system.nim (start, stopInclusive) - default
let oa = toOpenArray(ptrArr, start, stopInclusive)

# Using views.nim (ptr, length) - convenience template
let oa = toOpenArray(ptrArr, length)
# Or simply: ptrArr.toOpenArray(len)
```

### openArray to View
```nim
let v = toView(oa)
# Or: View[T](data: cast[ptr UncheckedArray[T]](oa[0].unsafeAddr), len: oa.len)
```

## Slicing Without seq Creation

NEVER use slice syntax like `array[0 ..< len]` on openArray parameters - this creates a seq (heap allocation).

Instead use:
```nim
# Bad - creates seq!
process(data[0 ..< count])

# Good - no allocation (system.nim uses stopInclusive)
process(data.toOpenArray(0, count-1))
```

`ptr UncheckedArray` should use the ptr+len syntax from `import constantine/platforms/views`

```
# Good - using views.nim convenience (ptr, length)
process(myDataPtr.toOpenArray(count))
```

## Constantine Allocator

 Constantine provides tracked memory management in `constantine/platforms/allocs.nim`:

### Stack Allocation
```nim
template allocStack*(T: typedesc): ptr T
template allocStackUnchecked*(T: typedesc, size: int): ptr T
template allocStackArray*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T]
```

### Heap Allocation
```nim
# Standard allocation (uninitialized memory)
proc allocHeap*(T: typedesc): ptr T
proc allocHeapUnchecked*(T: typedesc, size: int): ptr T
proc allocHeapArray*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T]
proc allocHeapAligned*(T: typedesc, alignment: static Natural): ptr T
proc allocHeapArrayAligned*(T: typedesc, len: int, alignment: static Natural): ptr UncheckedArray[T]
proc allocHeapAlignedPtr*(T: typedesc[ptr], alignment: static Natural): T
proc allocHeapUncheckedAlignedPtr*(T: typedesc[ptr], size: int, alignment: static Natural): T

# Zero-initialized allocation (critical for ARC with custom =destroy procs)
proc alloc0Heap*(T: typedesc): ptr T
proc alloc0HeapUnchecked*(T: typedesc, size: int): ptr T
proc alloc0HeapArray*(T: typedesc, len: SomeInteger): ptr UncheckedArray[T]
proc alloc0HeapAligned*(T: typedesc, alignment: static Natural): ptr T
proc alloc0HeapArrayAligned*(T: typedesc, len: int, alignment: static Natural): ptr UncheckedArray[T]
proc alloc0HeapAlignedPtr*(T: typedesc[ptr], alignment: static Natural): T
proc alloc0HeapUncheckedAlignedPtr*(T: typedesc[ptr], size: int, alignment: static Natural): T
```

**Important**: Use `alloc0*` variants when:
- Allocating structs with custom `=destroy` procs that check for nil pointers
- Working with ARC memory management to avoid double-free on uninitialized memory
- Example: `EthereumKZGContext` has `ECFFT_Descriptor` fields with `=destroy` that free memory

## varargs

Nim varargs can accept:
- Arrays: `foo([1, 2, 3])`
- Seqs: `foo(@[1, 2, 3])` - **avoid in crypto code**
- OpenArray: `foo(someOpenArray)`
- Direct args: `foo(1, 2, 3)`

## When to use me

- Working with Constantine library code
- When slicing buffers
- When needing dynamic memory management
