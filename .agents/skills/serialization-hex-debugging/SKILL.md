---
name: serialization-hex-debugging
description: Constantine serialization and hex debugging conventions. Use when serializing cryptographic types, parsing bytes, debugging values with toHex, or working with BLS12-381, Banderwagon, or ECDSA codecs.
license: MIT
metadata:
  audience: developers
  language: nim
---

## What I do

Cover serialization patterns and debugging practices in Constantine library.

## Serialization Conventions

### Status Codes

Serialization functions return status codes, never exceptions:

```nim
type
  CttCodecScalarStatus* = enum
    cttCodecScalar_Success
    cttCodecScalar_Zero
    cttCodecScalar_ScalarLargerThanCurveOrder

  CttCodecEccStatus* = enum
    cttCodecEcc_Success
    cttCodecEcc_InvalidEncoding
    cttCodecEcc_CoordinateGreaterThanOrEqualModulus
    cttCodecEcc_PointNotOnCurve
    cttCodecEcc_PointNotInSubgroup
    cttCodecEcc_PointAtInfinity
```

### Parsing Functions (bytes → internal)

- `unmarshal(dst: var BigInt, src: openArray[byte], endianness)` - returns bool
- `deserialize_*` - for cryptographic types, returns status code
- `fromBytes`, `fromHex` - alternative names
- `fromUint*(dst: var FF, src: SomeUnsignedInt)` - parse small unsigned integers into field elements

### Serialization Functions (internal → bytes)

- `marshal(dst: var openArray[byte], src, endianness)` - returns bool
- `serialize_*` - for cryptographic types
- `toBytes`, `toHex` - alternative names

### BLS12-381 Serialization Functions

From `constantine/serialization/codecs_bls12_381.nim`:

```nim
# Scalar (Fr) - 32 bytes
func serialize_scalar*(dst: var array[32, byte], scalar: Fr[BLS12_381].getBigInt()): CttCodecScalarStatus
func deserialize_scalar*(dst: var Fr[BLS12_381].getBigInt(), src: array[32, byte]): CttCodecScalarStatus

# G1 Point (compressed) - 48 bytes
func serialize_g1_compressed*(dst: var array[48, byte], g1P: EC_ShortW_Aff[Fp[BLS12_381], G1]): CttCodecEccStatus
func deserialize_g1_compressed*(dst: var EC_ShortW_Aff[Fp[BLS12_381], G1], src: array[48, byte]): CttCodecEccStatus
func deserialize_g1_compressed_unchecked*(dst: var EC_ShortW_Aff[Fp[BLS12_381], G1], src: array[48, byte]): CttCodecEccStatus

# G2 Point (compressed) - 96 bytes
func serialize_g2_compressed*(dst: var array[96, byte], g2P: EC_ShortW_Aff[Fp2[BLS12_381], G2]): CttCodecEccStatus
func deserialize_g2_compressed*(dst: var EC_ShortW_Aff[Fp2[BLS12_381], G2], src: array[96, byte]): CttCodecEccStatus
func deserialize_g2_compressed_unchecked*(dst: var EC_ShortW_Aff[Fp2[BLS12_381], G2], src: array[96, byte]): CttCodecEccStatus

# Validation (expensive, can be cached)
func validate_scalar*(scalar: Fr[BLS12_381].getBigInt()): CttCodecScalarStatus
func validate_g1*(g1P: EC_ShortW_Aff[Fp[BLS12_381], G1]): CttCodecEccStatus
func validate_g2*(g2P: EC_ShortW_Aff[Fp2[BLS12_381], G2]): CttCodecEccStatus
```

### Banderwagon Serialization Functions

From `constantine/serialization/codecs_banderwagon.nim`:

```nim
# Scalar - 32 bytes (big-endian)
func serialize_scalar*(dst: var array[32, byte], scalar: Fr[Banderwagon].getBigInt(), order: static Endianness = bigEndian): CttCodecScalarStatus
func serialize_fr*(dst: var array[32, byte], scalar: Fr[Banderwagon], order: static Endianness = bigEndian): CttCodecScalarStatus
func deserialize_scalar*(dst: var Fr[Banderwagon].getBigInt(), src: array[32, byte], order: static Endianness = bigEndian): CttCodecScalarStatus
func deserialize_fr*(dst: var Fr[Banderwagon], src: array[32, byte], order: static Endianness = bigEndian): CttCodecScalarStatus

# Point (compressed) - 32 bytes
func serialize*(dst: var array[32, byte], P: EC_TwEdw_Aff[Fp[Banderwagon]]): CttCodecEccStatus
func serializeUncompressed*(dst: var array[64, byte], P: EC_TwEdw_Aff[Fp[Banderwagon]]): CttCodecEccStatus
func deserialize_unchecked_vartime*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus
func deserialize_vartime*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus
func deserializeUncompressed*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[64, byte]): CttCodecEccStatus
func deserializeUncompressed_unchecked*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[64, byte]): CttCodecEccStatus

# Batch serialization
func serializeBatch_vartime*(dst: ptr UncheckedArray[array[32, byte]], points: ptr UncheckedArray[EC_TwEdw_Prj[Fp[Banderwagon]]], N: int): CttCodecEccStatus
func serializeBatchUncompressed_vartime*(dst: ptr UncheckedArray[array[64, byte]], points: ptr UncheckedArray[EC_TwEdw_Prj[Fp[Banderwagon]]], N: int): CttCodecEccStatus
```

### ECDSA Serialization Functions

From `constantine/serialization/codecs_ecdsa.nim`:

```nim
# ASN.1 DER signature (generic over curve)
type DerSignature*[N: static int] = object
  data*: array[N, byte]
  len*: int

proc toDER*[Name: static Algebra; N: static int](derSig: var DerSignature[N], r, s: Fr[Name])
proc fromDER*(r, s: var array[32, byte], derSig: DerSignature)
proc fromRawDER*(r, s: var array[32, byte], sig: openArray[byte]): bool
```

### Generic Codecs

From `constantine/serialization/codecs.nim`:

```nim
# Hex conversion
func toHex*(bytes: openarray[byte]): string
func fromHex*(dst: var openArray[byte], hex: openArray[char])
func paddedFromHex*(output: var openArray[byte], hexStr: openArray[char], order: static[Endianness])

# Base64
func base64_decode*(dst: var openArray[byte], src: openArray[char]): int
```

### Limbs I/O

From `constantine/serialization/io_limbs.nim`:

```nim
# Low-level limbs serialization
func unmarshal*(dst: var openArray[T], src: openarray[byte], wordBitWidth: static int, srcEndianness: static Endianness): bool
func marshal*(dst: var openArray[byte], src: openArray[T], wordBitWidth: static int, dstEndianness: static Endianness): bool
```

### Working with Small Integers

When you need to set a field element or BigInt to a small constant value (0, 1, 2, etc.), use `fromUint` or `setUint`:

```nim
# For field elements (Fp, Fr)
from constantine/math/io/io_fields import fromUint
var x: Fr[BLS12_381]
x.fromUint(1)           # Set to 1
x.fromUint(42)          # Set to 42

# For BigInts
from constantine/math/arithmetic/bigints import setUint
var big: BigInt[256]
big.setUint(1)          # Set to 1 (in-place)
big.setUint(42)         # Set to 42

# Also available as fromUint for BigInt
let big2 = BigInt[256].fromUint(123)
```

### Endianness

- Ethereum spec v1.6.1+ uses **big-endian** (`KZG_ENDIANNESS = 'big'`) for field/scalar elements
  - Note: This changed from little-endian in spec v1.3.0
  - Reference: https://github.com/ethereum/consensus-specs/blob/v1.6.1/specs/deneb/polynomial-commitments.md#constants
- BLS12-381 uses **big-endian** for serialization (Zcash format)
- Banderwagon uses **big-endian**
- Big-endian is common for byte serialization in other contexts
- Always specify explicitly: `marshal(dst, src, bigEndian)`

### Byte Manipulation Utilities

From `constantine/serialization/endians.nim`:

```nim
# Low-level byte conversion (compile-time safe)
template toByte*(x: SomeUnsignedInt): byte

# Convert unsigned int to bytes
func toBytes*(num: SomeUnsignedInt, endianness: static Endianness): array[sizeof(num), byte]

# Read unsigned int from bytes (multiple overloads)
func fromBytes*(T: type SomeUnsignedInt, bytes: array[sizeof(T), byte], endianness: static Endianness): T
func fromBytes*(T: type SomeUnsignedInt, bytes: openArray[byte], offset: int, endianness: static Endianness): T
func fromBytes*(T: type SomeUnsignedInt, bytes: ptr UncheckedArray[byte], offset: int, endianness: static Endianness): T

# Write integer into raw binary blob
# - blobFrom: The whole array is interpreted as little-endian or big-endian (blobEndianness)
# - dumpRawInt: The array is little-endian by convention, but words inside are endian-aware (wordEndianness)
func blobFrom*(dst: var openArray[byte], src: SomeUnsignedInt, startIdx: int, endian: static Endianness)
func dumpRawInt*(dst: var openArray[byte], src: SomeUnsignedInt, cursor: int, endian: static Endianness)
```

**Key difference:**
- `blobFrom(blobEndianness)`: The entire byte array is interpreted as either little-endian or big-endian.
- `dumpRawInt(wordEndianness)`: The array is little-endian by convention, but the individual words are written with the specified endianness.

### Example Pattern

```nim
func bytes_to_bls_field*(dst: var Fr[BLS12_381], src: array[32, byte]): CttCodecScalarStatus =
  var scalar {.noInit.}: Fr[BLS12_381].getBigInt()
  let status = scalar.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  dst.fromBig(scalar)
  return cttCodecScalar_Success
```

## Debugging

### IO Modules

For debugging, use the IO modules:

- `constantine/math/io/io_fields.nim` - Fp/Fr serialization
- `constantine/math/io/io_ec.nim` - Elliptic curve points
- `constantine/math/io/io_bigints.nim` - BigInt serialization
- `constantine/math/io/io_extfields.nim` - Extension fields (Fp2, Fp4, etc.)

### Key Functions

```nim
# Hex output (for debugging only, not constant-time)
func toHex*(f: FF): string
func toHex*(P: EC_ShortW_Aff): string

# Marshal to byte array
func marshal*(dst: var openArray[byte], src: FF, endianness): bool

# From hex string
func fromHex*(dst: var FF, hexString: string)
```

### Required Imports for debug toHex Functions

| Type | Import |
|------|--------|
| Field elements (Fp, Fr) | `constantine/math/io/io_fields` |
| Elliptic curve points | `constantine/math/io/io_ec` |
| BigInts | `constantine/math/io/io_bigints` |
| Extension fields (Fp2, Fp4...) | `constantine/math/io/io_extfields` |

### Debug Echo

Use `debugEcho` instead of `echo` to avoid side-effect warnings in `func` procedures:

```nim
# Bad - echo has side effects
echo "Value: ", value

# Good - debugEcho is allowed in debug code
debugEcho "Value: ", value.toHex()
```

### Complex Debug Blocks

For complex debugging that can't use `debugEcho`, wrap in `{.cast(noSideEffect).}`:

```nim
{.cast(noSideEffect).}:
  block:
    # Complex debug code here
    # Can use echo, print, etc.
    echo "Debug info: ", someVar
```

## No seq/strings in crypto code

Serialization in hot paths must avoid heap allocation:
- Never use `seq[byte]` or `string`
- Use fixed-size arrays or `openArray`
- Use `transcript.update(data)` instead of building a seq
