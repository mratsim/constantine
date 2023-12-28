# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# This file implements serialization
# for Circom's Rank-1 (Quadratic) Constraint System
# described in r1cs_bin_format.md
#
# We do not harcode the prime or the bitsize at compile-time
# This is not in the critical path (bench?) and we don't want monomorphization code-bloat.
# furthermore converting to/from this format
# - should not need recompilation to allow CLI-tools
# - should allow parallelization, down to field -> raw bytes, before writing to file or inversely

import
  ../../serialization/[io_limbs, parsing],
  ../../platforms/[fileio, abstractions]

type
  R1csSectionKind = enum
    kHeader                 = 1
    kConstraints            = 2
    kWire2LabelId           = 3
    kCustomGatesList        = 4
    kGustomGatesApplication = 5

  Factor = tuple[index: int32, value: seq[BaseType]]
  LinComb = seq[Factor]
    # A struct-of-arrays (SoA) is more efficient than seq[Constraint] array-of-structs (AoS)
    # but at the moment we use a seq[BaseType] indirection for field elements
    # so data access will occur a cache-miss anyway.
    # And we optimize for simplicity, so we use the same format as .r1cs files.
    # For heavy processing, constraints/linear combinations should use an AoS data structure.
    #
    # Data-structure wise, this is a sparse vector
  Constraint = tuple[A, B, C: LinComb]
    # A .* B = C with .* pointwise/elementwise mul (Hadamard Product)

  R1csBin = object
    magic: array[4, char]
    version: uint32
    # ----  Header  ----
    fieldSize: int32 # Field size in bytes, MUST be a multiple of 8
    prime: seq[BaseType]
    # ---- Sections ----
    constraints: seq[Constraint]
    wireIdToLabelId: seq[int64]
    # ----  Plonk   ----
    customGatesList: R1csCustomGatesList
    customGatesApp: R1csCustomGatesApp

  R1csCustomGatesList = object
  R1csCustomGatesApp = object

proc parseLinComb(f: File, lincomb: var LinComb, fieldSize: int32): bool =
  ## Parse a linear combination, returns true on success
  ## This does not validate that the elements parsed are part of the field
  var nnz: int32
  ?f.parseInt(nnz, littleEndian) # Sparse vector, non-zero values
  lincomb.setLen(int(nnz))

  var last = low(int32)
  let len = fieldSize.ceilDiv_vartime(WordBitWidth)
  var buf = newSeq[byte](fieldSize)

  for i in 0 ..< nnz:
    ?f.parseInt(lincomb[i].index, littleEndian) # wireID of the factor
    ?(last < lincomb[i].index)                  # The factors MUST be sorted in ascending order.
    last = lincomb[i].index
    lincomb[i].value.setLen(len)                # many allocations
    ?f.readInto(buf)                            # value of the factor
    ?lincomb[i].value.unmarshal(buf, WordBitWidth, littleEndian)

  return true

proc parseConstraint(f: File, constraint: var Constraint, fieldSize: int32): bool =
  ?f.parseLinComb(constraint.A, fieldSize)
  ?f.parseLinComb(constraint.B, fieldSize)
  ?f.parseLinComb(constraint.C, fieldSize)
  return true

template r1csSection(body: untyped): untyped =
  var sectionSize: int64
  ?f.parseInt(sectionSize, littleEndian)
  let startOffset = f.getFilePosition()

  body

  return sectionSize == f.getFilePosition() - startOffset

proc parseConstraints(f: File, constraints: var seq[Constraint], numConstraints, fieldSize: int32): bool =
  r1csSection:
    constraints.setLen(numConstraints)
    for constraint in constraints.mitems():
      ?f.parseConstraint(constraint, fieldSize)

proc parseWireLabelMap(f: File, wireIdToLabelId: var seq[int64], numWires: int32): bool =
  r1csSection:
    wireIdToLabelId.setLen(numWires)
    for labelId in wireIdToLabelId.mitems():
      ?f.parseInt(labelId, littleEndian)
