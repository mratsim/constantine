---
name: constantine-debugging
description: Constantine debugging techniques and tools
license: MIT
compatibility: opencode
metadata:
  audience: developers
  language: nim
---

## What I do

Cover debugging techniques for Constantine cryptographic code.

## Quick Debugging

### debugEcho

Use `debugEcho` instead of `echo` to avoid side-effect warnings in `func` procedures:

```nim
# Bad - echo has side effects, triggers compiler warnings in funcs
echo "Value: ", value

# Good - debugEcho is allowed in debug code
debugEcho "Value: ", value.toHex()
```

### toHex for Quick Output

Use the `toHex()` functions for quick inspection of cryptographic values. **You must import the corresponding IO module**:

```nim
# Field elements (Fr, Fp)
import constantine/math/io/io_fields
debugEcho "Scalar: ", scalar.toHex()

# Elliptic curve points
import constantine/math/io/io_ec
debugEcho "Point: ", point.toHex()

# BigInts
import constantine/math/io/io_bigints
debugEcho "BigInt: ", bigInt.toHex()

# Extension fields (Fp2, Fp4, Fp6, Fp12)
import constantine/math/io/io_extfields
debugEcho "Fp2: ", fp2.toHex()
```

## Conditional Debug Code

### debug: Template

Code guarded by `debug:` from `constantine/platforms/primitives.nim` is only compiled when `-d:CTT_DEBUG` is defined:

```nim
from constantine/platforms/primitives import debug

debug:
  # This code only compiles with -d:CTT_DEBUG
  echo "Debug info: ", value.toHex()
  doAssert someCondition, "Debug assertion failed"
```

Compile with:
```bash
nim c -d:CTT_DEBUG your_file.nim
```

## Full Stack Traces

In release mode, code is optimized and stack traces may be incomplete. Use `-d:linetrace` for full stack traces:

```bash
# Full stack traces in release mode
nim c -d:release -d:linetrace your_file.nim
```

This is often necessary because:
- Release mode with `-d:release` is needed for realistic performance
- But `-d:release` removes debug info by default
- `-d:linetrace` restores full stack traces while keeping optimizations

## Complex Debug Blocks

For complex debugging that can't use `debugEcho`, wrap in `{.cast(noSideEffect).}`:

```nim
{.cast(noSideEffect).}:
  block:
    # Complex debug code here
    echo "Debug info: ", someVar
    echo "More info: ", anotherVar.toHex()
```

## Required Imports for toHex

| Type | Import |
|------|--------|
| Field elements (Fp, Fr) | `constantine/math/io/io_fields` |
| Elliptic curve points | `constantine/math/io/io_ec` |
| BigInts | `constantine/math/io/io_bigints` |
| Extension fields (Fp2, Fp4...) | `constantine/math/io/io_extfields` |

## Debugging Tips

1. **Import the right IO module** - toHex won't work without it
2. **Start with toHex** - Quickest way to see values
3. **Use debugEcho** - For simple prints in func procedures  
4. **Use debug: template** - For code that should only exist in debug builds
5. **Use {.cast(noSideEffect).}** - For complex debug blocks in funcs
6. **Use -d:CTT_DEBUG** - For conditional compilation of debug code
7. **Use -d:linetrace** - For full stack traces in release mode
