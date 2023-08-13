# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./io_bigints,
  ../../platforms/abstractions,
  ../arithmetic/finite_fields

export Fp

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func fromUint*(dst: var FF,
               src: SomeUnsignedInt) =
  ## Parse a regular unsigned integer
  ## and store it into a Fp or Fr
  let raw {.noinit.} = (typeof dst.mres).unmarshal(cast[array[sizeof(src), byte]](src), cpuEndian)
  dst.fromBig(raw)

func fromInt*(dst: var FF,
               src: SomeInteger) =
  ## Parse a regular signed integer
  ## and store it into a Fp or Fr
  ## A negative integer will be instantiated as a negated number (mod p) or (mod r)
  when src is SomeUnsignedInt:
    dst.fromUint(src)
  else:
    const msb_pos = src.sizeof * 8 - 1
    let isNeg = SecretBool((src shr msb_pos) and 1)

    let src = isNeg.mux(SecretWord -src, SecretWord src)
    let raw {.noinit.} = (type dst.mres).unmarshal(cast[array[sizeof(src), byte]](src), cpuEndian)
    dst.fromBig(raw)
    dst.cneg(isNeg)

func marshal*(dst: var openarray[byte],
                       src: FF,
                       dstEndianness: static Endianness): bool {.discardable.} =
  ## Serialize a finite field element to its canonical big-endian or little-endian
  ## representation
  ## With `bits` the number of bits of the field modulus
  ## a buffer of size "(bits + 7) div 8" at minimum is needed
  ## i.e. bits -> byte conversion rounded up
  ##
  ## If the buffer is bigger, output will be zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## I.e least significant bit is aligned to buffer boundary
  marshal(dst, src.toBig(), dstEndianness)

func appendHex*(dst: var string, f: FF, order: static Endianness = bigEndian) =
  ## Stringify a finite field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  dst.appendHex(f.toBig(), order)

func toHex*(f: FF, order: static Endianness = bigEndian): string =
  ## Stringify a finite field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result.appendHex(f, order)

func fromHex*(dst: var FF, hexString: string) =
  ## Convert a hex string to a element of Fp or Fr
  ## Warning: protocols might want a specific function that checks
  ##          that the input is in [0, modulus) range
  # TODO: review API, should return bool
  let raw {.noinit.} = fromHex(dst.mres.typeof, hexString)
  dst.fromBig(raw)

func fromHex*(T: type FF, hexString: string): T {.noInit.}=
  ## Convert a hex string to a element of Fp
  ## Warning: protocols might want a specific function that checks
  ##          that the input is in [0, modulus) range
  result.fromHex(hexString)

func toDecimal*(f: FF): string =
  ## Convert to a decimal string.
  ##
  ## It is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.
  ##
  ## This function is NOT constant-time at the moment.
  f.toBig().toDecimal()

func fromDecimal*(dst: var FF, decimalString: string) =
  ## Convert a decimal string. The input must be packed
  ## with no spaces or underscores.
  ## This assumes that bits and decimal length are **public.**
  ##
  ## This function does approximate validation that the BigInt
  ## can hold the input string.
  ##
  ## It is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.
  ##
  ## Return true if conversion is successful
  ##
  ## Return false if an error occured:
  ## - There is not enough space in the BigInt
  ## - An invalid character was found
  # TODO: review API, should return bool
  let raw {.noinit.} = fromDecimal(dst.mres.typeof, decimalString)
  dst.fromBig(raw)

func fromDecimal*(T: type FF, hexString: string): T {.noInit.}=
  ## Convert a decimal string. The input must be packed
  ## with no spaces or underscores.
  ## This assumes that bits and decimal length are **public.**
  ##
  ## This function does approximate validation that the BigInt
  ## can hold the input string.
  ##
  ## It is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.
  ##
  ## This function may raise an exception if input is incorrect
  ## - There is not enough space in the BigInt
  ## - An invalid character was found
  result.fromDecimal(hexString)
