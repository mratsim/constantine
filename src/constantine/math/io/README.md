# I/O, serialization, encoding/decoding

## Overview

This folder provides serialization, encoding and decoding primitives
from Constantine internal representation to/from a canonical representation.

**Warning: ⚠️ This folder contains internal APIs**.
As serialization protocols get added, hardened serialization primitives
suitable for public use will be provided.

### Internal API

For the time being here is the description of the internal API.

Constant-time APIs only leak the number of bits, of bytes or words of the
big integer.

The bytes API are constant-time and do not allocate:
- BigInt or octet-string: unmarshal, fromUint
- Machine sized integers: fromUint

If you decide to use the internal hex or decimal API, you SHOULD ensure that the data is well-formatted:
- Only ['0'..'9'] for decimal
- Only ['0'..'9'], ['A'..'F'], ['a'..'b'] for hexadecimal
  An hexadecimal string may start with "0x".

There is no input validation as those are used for configuration, prototyping, research and debugging purposes.
If the data is too big for the specified BigInt size, the result is undefined.

The internal API is may be constant-time (temporarily) and may allocate.

The hexadecimal API allocates:
- `toHex` is constant-time
- `appendHex` is constant-time
- `fromHex` is constant-time, it is intended for debugging or
  (compile-time) configuration. It does not allocate.
  In particular it scans spaces and underscores and checks if the string
  starts with '0x'.

The decimal API allocates:
- `toDecimal` is constant-time and allocates
- `fromDecimal` is constant-time and does not allocate.

## Avoiding secret mistakes

Constantine deliberately doesn't define a `$` proc to make directly printing a compiler error or to make the datatype replaced by `...`.

It is recommented that you wrap your own types as distinct type and you can go the extra mile of disabling associated proc:

```
type SecretKey = distinct BigInt[256]

func toHex*(sk: SecretKey): string {.error: "Someone is about to make a big mistake.".}
func toDecimal*(sk: SecretKey): string {.error: "Someone is about to make a big mistake.".}
func `$`*(sk: SecretKey): string {.error: "Someone is about to make a big mistake.".}
```

Alternatively you can also overload with  dummy procedures:

```
type SecretKey = distinct BigInt[256]

func toHex*(sk: SecretKey): string = "<secret>"
func toDecimal*(sk: SecretKey): string = "<smoke screen>"
func `$`*(sk: SecretKey): string = "<camouflage>"
```

## References

### Normative references

- Standards for Efficient Cryptography Group (SECG),\
  "SEC 1: Elliptic Curve Cryptography", May 2009,\
  http://www.secg.org/sec1-v2.pdf

### Algorithms

#### Continued fractions

Continued fractions are used to convert

`size_in_bits <=> size_in_decimal`

for constant-time buffer preallocation when converting to decimal.

- https://en.wikipedia.org/wiki/Continued_fraction
