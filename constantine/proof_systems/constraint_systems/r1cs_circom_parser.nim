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
  constantine/platforms/[fileio, abstractions]

# We use `sortedByIt` to sort the different sections in the file by their
# `R1csSectionKind`
from std / algorithm import sortedByIt

type
  R1csSectionKind* = enum # `kInvalid` used to indicate unset & to make the enum work as field discriminator
    kInvalid                = 0
    kHeader                 = 1
    kConstraints            = 2
    kWire2LabelId           = 3
    kCustomGatesList        = 4
    kCustomGatesApplication = 5

  # Note: We parse the `value` of the `Factor` into a `seq[byte]` to be platform
  # independent (32 vs 64bit), because `BaseType` depends on the platform
  Factor = tuple[index: int32, value: seq[byte]]
  LinComb* = seq[Factor]
    # A struct-of-arrays (SoA) is more efficient than seq[Constraint] array-of-structs (AoS)
    # but at the moment we use a seq[byte] indirection for field elements
    # so data access will occur a cache-miss anyway.
    # And we optimize for simplicity, so we use the same format as .r1cs files.
    # For heavy processing, constraints/linear combinations should use an AoS data structure.
    #
    # Data-structure wise, this is a sparse vector
  Constraint* = tuple[A, B, C: LinComb]
    # A .* B = C with .* pointwise/elementwise mul (Hadamard Product)

  #[
  Header section example
     ┏━━━━┳━━━━━━━━━━━━━━━━━┓
     ┃ 4  │   20 00 00 00   ┃               Field Size in bytes (fs)
     ┗━━━━┻━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
     ┃ fs │   010000f0 93f5e143 9170b979 48e83328 5d588181 b64550b8 29a031e1 724e6430 ┃  Prime size
     ┗━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━┓
     ┃ 32 │   01 00 00 00   ┃               nWires
     ┗━━━━┻━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━┓
     ┃ 32 │   01 00 00 00   ┃               nPubOut
     ┗━━━━┻━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━┓
     ┃ 32 │   01 00 00 00   ┃               nPubIn
     ┗━━━━┻━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━┓
     ┃ 32 │   01 00 00 00   ┃               nPrvIn
     ┗━━━━┻━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
     ┃ 64 │   01 00 00 00 00 00 00 00   ┃   nLabels
     ┗━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
     ┏━━━━┳━━━━━━━━━━━━━━━━━┓
     ┃ 32 │   01 00 00 00   ┃               mConstraints
     ┗━━━━┻━━━━━━━━━━━━━━━━━┛
  ]#
  Header* = object
    fieldSize*: uint32 # field size in bytes (fs)
    prime*: seq[byte] # XXX: What type to use with RT size info?
    nWires*: uint32
    nPubOut*: uint32
    nPubIn*: uint32
    nPrvIn*: uint32
    nLabels*: uint64
    nConstraints*: uint32

  #[
  Wire 2 Label section example
  ┏━━━━┳━━━━━━━━━━━━━━━━━━━┳━━━━┳━━━━━━━━━━━━━━━━━━━┓     ┏━━━━┳━━━━━━━━━━━━━━━━━━━┓
  ┃ 64  │ labelId of Wire_0      ┃ 64  │ labelId of Wire_1      ┃ ... ┃ 64 │      labelId of Wire_n ┃
  ┗━━━━┻━━━━━━━━━━━━━━━━━━━┻━━━━┻━━━━━━━━━━━━━━━━━━━┛     ┗━━━━┻━━━━━━━━━━━━━━━━━━━┛
  ]#
  Wire2Label* = object
    wireIds*: seq[uint64]

  Section* = object
    size*: uint64 # NOTE: in the real file the section type is *FIRST* and then the size
                 # But we cannot map this with a variant type in Nim (without using different
                 # names for each variant branch)
    case sectionType*: R1csSectionKind
    of kInvalid: discard
    of kHeader: header*: Header
    of kConstraints: constraints*: seq[Constraint]
    of kWire2LabelId: w2l*: Wire2Label
    of kCustomGatesList: cGatesList*: R1csCustomGatesList
    of kCustomGatesApplication: cGatesApp*: R1csCustomGatesApp

  ## `R1csBin` is binary compatible with an R1CS binary file. Meaning it follows the structure
  ## of the file (almost) exactly. The only difference is in the section header. The size comes
  ## *after* the kind, which we don't reproduce in `Section` above
  R1csBin* = object
    magic*: array[4, char]
    version*: uint32
    numberSections*: uint32
    sections*: seq[Section] # Note: Because of the unordered nature of the sections
                           # the `sections` seq won't follow the binary order of
                           # the data in the file. Instead, we first record (kind, file position)
                           # of each different section in the file and then parse them in increasing
                           # order of the section types

  R1csCustomGatesList* = object
  R1csCustomGatesApp* = object

  ## XXX: Make this a `R1CS[T]` which takes care of parsing the field elements
  ## NOTE: For the time being we don't actually use the parsed data
  R1CS* = object
    magic*: array[4, char]
    version*: uint32
    numberSections*: uint32
    header*: Header
    constraints*: seq[Constraint]
    w2l*: Wire2Label


proc toR1CS*(r1cs: R1csBin): R1CS =
  result = R1CS(magic: r1cs.magic,
                version: r1cs.version,
                numberSections: r1cs.numberSections)
  for s in r1cs.sections:
    case s.sectionType
    of kHeader: result.header = s.header
    of kConstraints: result.constraints = s.constraints
    of kWire2LabelId: result.w2l = s.w2l
    else:
      echo "Ignoring: ", s.sectionType

proc initSection(kind: R1csSectionKind, size: uint64): Section =
  result = Section(sectionType: kind, size: size)

proc parseLinComb(f: File, lincomb: var LinComb, fieldSize: int32): bool =
  ## Parse a linear combination, returns true on success
  ## This does not validate that the elements parsed are part of the field
  var nnz: int32
  ?f.parseInt(nnz, littleEndian) # Sparse vector, non-zero values
  lincomb.setLen(int(nnz))

  var last = low(int32)
  # fieldSize is in bytes!
  var buf = newSeq[byte](fieldSize)

  for i in 0 ..< nnz:
    ?f.parseInt(lincomb[i].index, littleEndian) # wireID of the factor
    ?(last < lincomb[i].index)                  # The factors MUST be sorted in ascending order.
    last = lincomb[i].index
    ?f.readInto(buf)                            # value of the factor
    lincomb[i].value = buf                      # copy!

  return true

proc parseConstraint(f: File, constraint: var Constraint, fieldSize: int32): bool =
  ?f.parseLinComb(constraint.A, fieldSize)
  ?f.parseLinComb(constraint.B, fieldSize)
  ?f.parseLinComb(constraint.C, fieldSize)
  return true

template r1csSection(sectionSize, body: untyped): untyped =
  let startOffset = f.getFilePosition()

  body

  return sectionSize.int == f.getFilePosition() - startOffset

proc parseConstraints(f: File, constraints: var seq[Constraint], sectionSize: uint64, numConstraints, fieldSize: int32): bool =
  r1csSection(sectionSize):
    constraints.setLen(numConstraints)
    for constraint in constraints.mitems():
      ?f.parseConstraint(constraint, fieldSize)

proc parseMagicHeader(f: File, mh: var array[4, char]): bool =
  result = f.readInto(mh)

proc parseSectionKind(f: File, v: var R1csSectionKind): bool =
  var val: uint32
  result = f.parseInt(val, littleEndian)
  v = R1csSectionKind(val.int)

proc parseHeader(f: File, h: var Header): bool =
  ?f.parseInt(h.fieldSize, littleEndian) # byte size of the prime number
  # allocate for the prime
  h.prime = newSeq[byte](h.fieldSize)
  ?f.readInto(h.prime)
  ?f.parseInt(h.nWires, littleEndian)
  ?f.parseInt(h.nPubOut, littleEndian)
  ?f.parseInt(h.nPubIn, littleEndian)
  ?f.parseInt(h.nPrvIn, littleEndian)
  ?f.parseInt(h.nLabels, littleEndian)
  ?f.parseInt(h.nConstraints, littleEndian)
  result = true # would have returned before due to `?` otherwise

proc parseWire2Label(f: File, v: var Wire2Label, sectionSize: uint64): bool =
  r1csSection(sectionSize):
    let numWires = sectionSize div 8
    v.wireIds.setLen(numWires)
    for labelId in v.wireIds.mitems():
      ?f.parseInt(labelId, littleEndian)

## TODO: to be written :)
proc parseCustomGatesList(f: File, v: var R1csCustomGatesList): bool = discard
proc parseCustomGatesApplication(f: File, v: var R1csCustomGatesApp): bool = discard

proc getNumConstraints(r1cs: R1csBin): int32 =
  ## Returns the number of constraints in the file, based on the header
  ## This means the header must have been parsed and is located in `sections[0]`.
  doAssert r1cs.sections[0].sectionType == kHeader
  result = r1cs.sections[0].header.nConstraints.int32

proc getFieldSize(r1cs: R1csBin): int32 =
  ## Returns the field size (size of the prime) in the file, based on the header
  ## This means the header must have been parsed and is located in `sections[0]`.
  doAssert r1cs.sections[0].sectionType == kHeader
  result = r1cs.sections[0].header.fieldSize.int32

proc parseSection(f: File, s: var Section, kind: R1csSectionKind, size: uint64, r1cs: R1csBin): bool =
  # NOTE: The `r1cs` object is there to provide the header information to
  # the constraints section
  s = initSection(kind, size)
  case kind
  of kHeader:                 ?f.parseHeader(s.header)
  of kConstraints:            ?f.parseConstraints(s.constraints, size, r1cs.getNumConstraints(), r1cs.getFieldSize())
  of kWire2LabelId:           ?f.parseWire2Label(s.w2l, size)
  of kCustomGatesList:        ?f.parseCustomGatesList(s.cGatesList)
  of kCustomGatesApplication: ?f.parseCustomGatesApplication(s.cGatesApp)
  of kInvalid: return false

  result = true # would have returned otherwise due to `?`

proc parseR1csFile*(path: string): R1csBin =
  var f = fileio.open(path, kRead)

  doAssert f.parseMagicHeader(result.magic), "Failed to read magic header"
  doAssert f.parseInt(result.version, littleEndian), "Failed to read version"
  doAssert f.parseInt(result.numberSections, littleEndian), "Failed to read number of sections"

  result.sections = newSeq[Section](result.numberSections)
  # 1. determine the section kind, size & file position for each section in the file
  var pos = newSeq[(R1csSectionKind, uint64, int64)](result.numberSections)
  let fp = f.getFilePosition()
  for i in 0 ..< result.numberSections:
    var kind: R1csSectionKind
    var size: uint64 # section size
    doAssert f.parseSectionKind(kind), "Failed to read section type in section " & $i
    doAssert f.parseInt(size, littleEndian), "Failed to read section size in section " & $i
    # compute position of next section
    pos[i] = (kind, size, f.getFilePosition())
    let np = f.getFilePosition() + size.int64 # compute beginning of next section header
    # set file pos to after
    doAssert f.setFilePosition(np) == 0, "Failed to set file position to " & $np

  # Sort the positions by the section type
  pos = pos.sortedByIt(it[0])
  doAssert pos[0][0] == kHeader, "No header present in the file"

  # 2. iterate the different kinds / positions & parse them
  for i, (kind, size, p) in pos: # set position to start of section & parse
    doAssert f.setFilePosition(p) == 0, "Failed to set file position to " & $p
    doAssert f.parseSection(result.sections[i], kind, size, result), "Failed to parse section " & $i
    if i == 0: # assert we read the header!
      doAssert kind == kHeader

  fileio.close(f)
