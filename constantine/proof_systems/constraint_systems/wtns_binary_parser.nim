# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# This file implements serialization
#
import
  ../../serialization/[io_limbs, parsing],
  constantine/platforms/[fileio, abstractions],
  ../../named/algebras, # Fr
  ../groth16_utils

#[
The following is a rough spec of the witness files. Details may vary for different
curves (e.g. field witnesse elements may have different sizes).

Given that there is no specification for the `.wtns` file format, we assume it
is generally treated like the R1CS binary files. See the note at the top of
`zkey_binary_parser.nim` for more notes.

1. File Header:
   - Magic String:
     - Offset: 0 bytes
     - Length: 4 bytes
     - Content: ASCII string "wtns"
   - Version Number:
     - Offset: 4 bytes
     - Length: 4 bytes
     - Content: 32-bit unsigned integer indicating the format version (e.g., 2)
   - Section Count:
     - Offset: 8 bytes
     - Length: 4 bytes
     - Content: 32-bit unsigned integer indicating the number of sections (e.g., 1)

2. Witness Length:
   - Witness Count:
     - Offset: 12 bytes
     - Length: 8 bytes
     - Content: 64-bit unsigned integer indicating the number of witness elements

3. Witness Data:
   - Witness Elements:
     - Offset: 20 bytes
     - Length: 32 bytes per element
     - Content: Each witness element is a 256-bit (32 bytes) unsigned integer in Big Endian format
]#

from std / sequtils import filterIt
from std / strutils import endsWith

type
  WtnsSectionKind* = enum # `kInvalid` used to indicate unset & to make the enum work as field discriminator
    kInvalid = 0
    kHeader  = 1
    kData    = 2

  WitnessHeader* = object
    n8*: uint32 # field size in bytes
    r*: seq[byte] # prime order of the field
    num*: uint32 # number of witness elements

  Witness* = object
    data*: seq[byte] ## Important: The values are *not* Montgomery encoded

  Section* = object
    size*: uint64 # NOTE: in the real file the section type is *FIRST* and then the size
                 # But we cannot map this with a variant type in Nim (without using different
                 # names for each variant branch)
    case sectionType*: WtnsSectionKind
    of kInvalid: discard
    of kHeader: header*: WitnessHeader
    of kData: wtns*: seq[Witness]

  ## `WtnsBin` is binary compatible with an Witness binary file. Meaning it follows the structure
  ## of the file (almost) exactly. The only difference is in the section header. The size comes
  ## *after* the kind, which we don't reproduce in `Section` above
  WtnsBin* = object
    magic*: array[4, char] # "wtns"
    version*: uint32
    numberSections*: uint32
    sections*: seq[Section] # Note: Because of the unordered nature of the sections
                           # the `sections` seq won't follow the binary order of
                           # the data in the file. Instead, we first record (kind, file position)
                           # of each different section in the file and then parse them in increasing
                           # order of the section types

  Wtns*[Name: static Algebra] = object
    version*: uint32
    header*: WitnessHeader
    witnesses*: seq[Fr[Name]]

func header*(wtns: WtnsBin): WitnessHeader =
  result = wtns.sections.filterIt(it.sectionType == kHeader)[0].header

func witnesses*(wtns: WtnsBin): seq[Witness] =
  result = wtns.sections.filterIt(it.sectionType == kData)[0].wtns

proc getWitnesses[Name: static Algebra](witnesses: seq[Witness]): seq[Fr[Name]] =
  result = newSeq[Fr[Name]](witnesses.len)
  for i, w in witnesses:
    result[i] = toFr[Name](w.data, isMont = false) ## Important: Witness does *not* store numbers in Montgomery rep

proc toWtns*[Name: static Algebra](wtns: WtnsBin): Wtns[Name] =
  result = Wtns[Name](
    version: wtns.version,
    header: wtns.header(),
    witnesses: wtns.witnesses().getWitnesses[:Name]()
  )

proc initSection(kind: WtnsSectionKind, size: uint64): Section =
  result = Section(sectionType: kind, size: size)

template wtnsSection(sectionSize, body: untyped): untyped =
  let startOffset = f.getFilePosition()

  body

  return sectionSize.int == f.getFilePosition() - startOffset

proc parseMagicHeader(f: File, mh: var array[4, char]): bool =
  result = f.readInto(mh)

proc parseSectionKind(f: File, v: var WtnsSectionKind): bool =
  var val: uint32
  result = f.parseInt(val, littleEndian)
  v = WtnsSectionKind(val.int)

proc parseWitnessHeader(f: File, h: var WitnessHeader): bool =
  ?f.parseInt(h.n8, littleEndian) # byte size of the prime number
  h.r.setLen(h.n8)
  ?f.readInto(h.r)
  ?f.parseInt(h.num, littleEndian)
  result = true # would have returned before due to `?` otherwise

proc parseWitnesses(f: File, s: var seq[Witness], sectionSize: uint64, elemSize: uint32): bool =
  ## Parses the witnesses
  let numElems = sectionSize div elemSize.uint64
  var buf = newSeq[byte](elemSize)
  s.setLen(numElems)
  for i in 0 ..< numElems:
    ?f.readInto(buf)
    s[i] = Witness(data: buf) ## XXX: fix me
  result = true

proc parseWitnesses(f: File, s: var Section, size: uint64, wtns: WtnsBin): bool =
  let h = wtns.sections.filterIt(it.sectionType == kHeader)[0].header ## XXX: fixme
  result = parseWitnesses(f, s.wtns, size, h.n8)

proc parseSection(f: File, s: var Section, kind: WtnsSectionKind, size: uint64, wtns: var WtnsBin): bool =
  # NOTE: The `wtns` object is there to provide the header information to
  # the constraints section
  s = initSection(kind, size)
  case kind
  of kHeader: ?f.parseWitnessHeader(s.header)
  of kData:   ?f.parseWitnesses(s, size, wtns)
  else: raiseAssert "Invalid"

  result = true # would have returned otherwise due to `?`

proc parseSection(f: File, wtns: var WtnsBin): Section =
  var kind: WtnsSectionKind
  var size: uint64
  doAssert f.parseSectionKind(kind), "Failed to read section type in section "
  doAssert f.parseInt(size, littleEndian), "Failed to read section size in section "

  result = initSection(kHeader, size)

  doAssert f.parseSection(result, kind, size, wtns), "Failed to parse section: " & $kind

proc parseWtnsFile*(path: string): WtnsBin =
  var f = fileio.open(path, kRead)

  doAssert f.parseMagicHeader(result.magic), "Failed to read magic header"
  doAssert f.parseInt(result.version, littleEndian), "Failed to read version"
  doAssert f.parseInt(result.numberSections, littleEndian), "Failed to read number of sections"

  for i in 0 ..< result.numberSections:
    let s = parseSection(f, result)
    result.sections.add s

  fileio.close(f)
