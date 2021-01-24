# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


import
  # Standard library
  std/typetraits,
  # Internal
  ./io_bigints, ./io_fields,
  ../arithmetic/finite_fields,
  ../tower_field_extensions/tower_instantiation

export tower_instantiation

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func appendHex*(accum: var string, f: Fp2 or Fp4 or Fp6 or Fp12, order: static Endianness = bigEndian) =
  ## Hex accumulator
  accum.add static($f.typeof.genericHead() & '(')
  for fieldName, fieldValue in fieldPairs(f):
    when fieldName != "c0":
      accum.add ", "
    accum.add fieldName & ": "
    accum.appendHex(fieldValue, order)
  accum.add ")"

func toHex*(f: Fp2 or Fp4 or Fp6 or Fp12, order: static Endianness = bigEndian): string =
  ## Stringify a tower field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result.appendHex(f, order)

func fromHex*(dst: var Fp2, c0, c1: string) {.raises: [ValueError].}=
  ## Convert 2 coordinates to an element of 𝔽p2
  ## with dst = c0 + β * c1
  ## β is the quadratic non-residue chosen to construct 𝔽p2
  dst.c0.fromHex(c0)
  dst.c1.fromHex(c1)

func fromHex*(T: typedesc[Fp2], c0, c1: string): T {.raises: [ValueError].}=
  ## Convert 2 coordinates to an element of 𝔽p2
  ## with dst = c0 + β * c1
  ## β is the quadratic non-residue chosen to construct 𝔽p2
  result.fromHex(c0, c1)

func fromHex*(dst: var Fp4,
              c0, c1, c2, c3: string) {.raises: [ValueError].}=
  ## Convert 4 coordinates to an element of 𝔽p4
  dst.c0.fromHex(c0, c1)
  dst.c1.fromHex(c2, c3)

func fromHex*(T: typedesc[Fp4],
              c0, c1, c2: string,
              c3, c4, c5: string): T {.raises: [ValueError].}=
  ## Convert 4 coordinates to an element of 𝔽p4
  result.fromHex(c0, c1, c2, c3)

func fromHex*(dst: var Fp6,
              c0, c1, c2: string,
              c3, c4, c5: string) {.raises: [ValueError].}=
  ## Convert 6 coordinates to an element of 𝔽p6
  dst.c0.fromHex(c0, c1)
  dst.c1.fromHex(c2, c3)
  dst.c2.fromHex(c4, c5)

func fromHex*(T: typedesc[Fp6],
              c0, c1, c2: string,
              c3, c4, c5: string): T {.raises: [ValueError].}=
  ## Convert 6 coordinates to an element of 𝔽p6
  result.fromHex(c0, c1, c2, c3, c4, c5)

func fromHex*(dst: var Fp12,
              c0, c1, c2, c3: string,
              c4, c5, c6, c7: string,
              c8, c9, c10, c11: string) {.raises: [ValueError].}=
  ## Convert 12 coordinates to an element of 𝔽p12
  when dst.c0 is Fp6:
    dst.c0.fromHex(c0, c1, c2, c3, c4, c5)
    dst.c1.fromHex(c6, c7, c8, c9, c10, c11)
  else:
    dst.c0.fromHex(c0, c1, c2, c3)
    dst.c1.fromHex(c4, c5, c6, c7)
    dst.c2.fromHex(c8, c9, c10, c11)

func fromHex*(T: typedesc[Fp12],
              c0, c1, c2, c3: string,
              c4, c5, c6, c7: string,
              c8, c9, c10, c11: string): T {.raises: [ValueError].}=
  ## Convert 12 coordinates to an element of 𝔽p12
  result.fromHex(c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11)

func fromUint*(a: var ExtensionField, src: SomeUnsignedInt) =
  ## Set ``a`` to the bigint value int eh extension field
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      fA.fromUint(src)
    else:
      fA.setZero()

func fromInt*(a: var ExtensionField, src: SomeInteger) =
  ## Parse a regular signed integer
  ## and store it into a Fp^n
  ## A negative integer will be instantiated as a negated number (mod p^n)
  for fieldName, fA in fieldPairs(a):
    when fieldName == "c0":
      fA.fromInt(src)
    else:
      fA.setZero()
