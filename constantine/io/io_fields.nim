# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./io_bigints,
  ../config/curves,
  ../math/[bigints_checked, finite_fields]

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func fromUint*(dst: var Fq,
               src: SomeUnsignedInt) =
  ## Parse a regular unsigned integer
  ## and store it into a BigInt of size `bits`
  let raw = (type dst.mres).fromRawUint(cast[array[sizeof(src), byte]](src), cpuEndian)
  dst.mres.unsafeMontyResidue(raw, Fq.C.Mod.mres, Fq.C.getR2modP(), MontyNegInvModWord[Fq.C])

func serializeRawUint*(dst: var openarray[byte],
                       src: Fq,
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
  serializeRawUint(dst, src.toBig(), dstEndianness)

func toHex*(f: Fq, order: static Endianness = bigEndian): string =
  ## Stringify a finite field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result = f.toBig().toHex()
