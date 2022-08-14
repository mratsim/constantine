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
  ../../platforms/primitives,
  ../arithmetic/finite_fields,
  ../extension_fields/towers

export towers

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

proc spaces*(num: int): string =
  result = newString(num)
  for i in 0 ..< num:
    result[i] = ' '

func appendHex*(accum: var string, f: ExtensionField, indent = 0, order: static Endianness = bigEndian) =
  ## Hex accumulator
  accum.add static($f.typeof.genericHead() & '(')
  staticFor i, 0, f.coords.len:
    when i != 0:
      accum.add ", "
    accum.add "\n" & spaces(indent+2) & "c" & $i & ": "
    when f is Fp2:
      accum.appendHex(f.coords[i], order)
    else:
      accum.appendHex(f.coords[i], indent+2, order)
  accum.add ")"

func toHex*(f: ExtensionField, indent = 0, order: static Endianness = bigEndian): string =
  ## Stringify a tower field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result.appendHex(f, indent, order)

func fromHex*(dst: var Fp2, c0, c1: string) =
  ## Convert 2 coordinates to an element of 𝔽p2
  ## with dst = c0 + β * c1
  ## β is the quadratic non-residue chosen to construct 𝔽p2
  dst.c0.fromHex(c0)
  dst.c1.fromHex(c1)

func fromHex*(T: typedesc[Fp2], c0, c1: string): T =
  ## Convert 2 coordinates to an element of 𝔽p2
  ## with dst = c0 + β * c1
  ## β is the quadratic non-residue chosen to construct 𝔽p2
  result.fromHex(c0, c1)

func fromHex*(dst: var Fp4,
              c0, c1, c2, c3: string) =
  ## Convert 4 coordinates to an element of 𝔽p4
  dst.c0.fromHex(c0, c1)
  dst.c1.fromHex(c2, c3)

func fromHex*(T: typedesc[Fp4],
              c0, c1, c2: string,
              c3, c4, c5: string): T =
  ## Convert 4 coordinates to an element of 𝔽p4
  result.fromHex(c0, c1, c2, c3)

func fromHex*(dst: var Fp6,
              c0, c1, c2: string,
              c3, c4, c5: string) =
  ## Convert 6 coordinates to an element of 𝔽p6
  dst.c0.fromHex(c0, c1)
  dst.c1.fromHex(c2, c3)
  dst.c2.fromHex(c4, c5)

func fromHex*(T: typedesc[Fp6],
              c0, c1, c2: string,
              c3, c4, c5: string): T =
  ## Convert 6 coordinates to an element of 𝔽p6
  result.fromHex(c0, c1, c2, c3, c4, c5)

func fromHex*(dst: var Fp12,
              c0, c1, c2, c3: string,
              c4, c5, c6, c7: string,
              c8, c9, c10, c11: string) =
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
              c8, c9, c10, c11: string): T =
  ## Convert 12 coordinates to an element of 𝔽p12
  result.fromHex(c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11)

func fromUint*(a: var ExtensionField, src: SomeUnsignedInt) =
  ## Set ``a`` to the bigint value int eh extension field
  a.coords[0].fromUint(src)
  staticFor i, 1, a.coords.len:
    a.coords[i].setZero()

func fromInt*(a: var ExtensionField, src: SomeInteger) =
  ## Parse a regular signed integer
  ## and store it into a Fp^n
  ## A negative integer will be instantiated as a negated number (mod p^n)
  a.coords[0].fromInt(src)
  staticFor i, 1, a.coords.len:
    a.coords[i].setZero()
