# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./io_bigints,
  ../config/common,
  ../arithmetic/finite_fields,
  ../primitives

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func fromUint*(dst: var Fp,
               src: SomeUnsignedInt) =
  ## Parse a regular unsigned integer
  ## and store it into a Fp
  let raw {.noinit.} = (type dst.mres).fromRawUint(cast[array[sizeof(src), byte]](src), cpuEndian)
  dst.fromBig(raw)

func fromInt*(dst: var Fp,
               src: SomeInteger) =
  ## Parse a regular signed integer
  ## and store it into a Fp
  ## A negative integer will be instantiated as a negated number (mod p)
  when src is SomeUnsignedInt:
    dst.fromUint(src)
  else:
    const msb_pos = src.sizeof * 8 - 1
    let isNeg = SecretBool((src shr msb_pos) and 1)

    let src = isNeg.mux(SecretWord -src, SecretWord src)
    let raw {.noinit.} = (type dst.mres).fromRawUint(cast[array[sizeof(src), byte]](src), cpuEndian)
    dst.fromBig(raw)

func exportRawUint*(dst: var openarray[byte],
                       src: Fp,
                       dstEndianness: static Endianness) =
  ## Serialize a finite field element to its canonical big-endian or little-endian
  ## representation
  ## With `bits` the number of bits of the field modulus
  ## a buffer of size "(bits + 7) div 8" at minimum is needed
  ## i.e. bits -> byte conversion rounded up
  ##
  ## If the buffer is bigger, output will be zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## I.e least significant bit is aligned to buffer boundary
  exportRawUint(dst, src.toBig(), dstEndianness)

func appendHex*(dst: var string, f: Fp, order: static Endianness = bigEndian) =
  ## Stringify a finite field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  dst.appendHex(f.toBig(), order)

func toHex*(f: Fp, order: static Endianness = bigEndian): string =
  ## Stringify a finite field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result.appendHex(f, order)

func fromHex*(dst: var Fp, hexString: string) {.raises: [ValueError].}=
  ## Convert a hex string to a element of Fp
  let raw {.noinit.} = fromHex(dst.mres.typeof, hexString)
  dst.fromBig(raw)

func fromHex*(T: type Fp, hexString: string): T {.noInit, raises: [ValueError].}=
  ## Convert a hex string to a element of Fp
  result.fromHex(hexString)
