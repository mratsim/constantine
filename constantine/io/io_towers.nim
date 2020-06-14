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
  ../config/curves,
  ../arithmetic/finite_fields,
  ../towers

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func appendHex*(accum: var string, f: Fp2 or Fp6 or Fp12, order: static Endianness = bigEndian) =
  ## Hex accumulator
  accum.add static($f.typeof.genericHead() & '(')
  for fieldName, fieldValue in fieldPairs(f):
    when fieldName != "c0":
      accum.add ", "
    accum.add fieldName & ": "
    accum.appendHex(fieldValue, order)
  accum.add ")"

func toHex*(f: Fp2 or Fp6 or Fp12, order: static Endianness = bigEndian): string =
  ## Stringify a tower field element to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result.appendHex(f, order)
