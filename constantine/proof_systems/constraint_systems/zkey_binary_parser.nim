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
  ../../named/algebras, # Fr, Fp
  ../../math/extension_fields, # Fp2
  ../../math/elliptic/[ec_shortweierstrass_affine], # EC types
  ../groth16_utils # to unmarshal data

from std / sequtils import filterIt
from std / strutils import endsWith

## Note on the parsing logic:
##
## A Zkey file is first parsed into the `ZkeyBin` type. This data type
## tries to mostly match the binary format of the `.zkey` files.
## *HOWEVER*, there is no specification for `.zkey` files. *BUT*, if we
## assume the same general specification holds as for the R1CS binary
## files (for which
## https://github.com/iden3/r1csfile/blob/master/doc/r1cs_bin_format.md
## exists), we must assume that each section can appear in arbitrary
## order in the binary file. Thus, we use an approach with variant objects
## and simply a `seq[Section]` for the `ZkeyBin` type. We could either
## disregard "spec compliance" and just assume the section order is
## based on the section numbering (i.e. like the `ZkeySectionKind` enum
## values) or handle different orders during parsing.
##
## In the end, we have a curve specific "typed" `Zkey[T]` type, which
## does away with this approach anyhow.

type
  ZkeySectionKind* = enum # `kInvalid` used to indicate unset & to make the enum work as field discriminator
    kInvalid                = 0
    kHeader                 = 1
    kGroth16Header          = 2
    kIC                     = 3
    kCoeffs                 = 4
    kA                      = 5
    kB1                     = 6
    kB2                     = 7
    kC                      = 8
    kH                      = 9
    kContributions          = 10

  Header* = object
    proverType*: uint32 ## Must be `1` for Groth16

  Groth16Header_b* = object
    n8q*: uint32 # Size of base field in bytes (4 bytes, unsigned integer)
    q*: seq[byte] # Prime of the base field (n8q bytes)
    n8r*: uint32 # Size of scalar field in bytes (4 bytes, unsigned integer)
    r*: seq[byte] # Prime of the scalar field (n8r bytes)
    nVars*: uint32 # Total number of variables (4 bytes, unsigned integer)
    nPublic*: uint32 # Number of public variables (4 bytes, unsigned integer)
    domainSize*: uint32 # Size of the domain (4 bytes, unsigned integer)
    alpha1*: seq[byte] # alpha in G1 (2 * n8q bytes)
    beta1*: seq[byte] # beta in G1 (2 * n8q bytes)
    beta2*: seq[byte] # beta in G2 (4 * n8q bytes)
    gamma2*: seq[byte] # gamma in G2 (4 * n8q bytes)
    delta1*: seq[byte] # delta in G1 (2 * n8q bytes)
    delta2*: seq[byte] # delta in G2 (4 * n8q bytes)

  Groth16Header*[Name: static Algebra] = object
    n8q*: uint32 # Size of base field in bytes (4 bytes, unsigned integer)
    q*: seq[byte] # Prime of the base field (n8q bytes)
    n8r*: uint32 # Size of scalar field in bytes (4 bytes, unsigned integer)
    r*: seq[byte] # Prime of the scalar field (n8r bytes)
    nVars*: uint32 # Total number of variables (4 bytes, unsigned integer)
    nPublic*: uint32 # Number of public variables (4 bytes, unsigned integer)
    domainSize*: uint32 # Size of the domain (4 bytes, unsigned integer)
    alpha1*: EC_ShortW_Aff[Fp[Name], G1]
    beta1*: EC_ShortW_Aff[Fp[Name], G1]
    beta2*: EC_ShortW_Aff[Fp2[Name], G2]
    gamma2*: EC_ShortW_Aff[Fp2[Name], G2]
    delta1*: EC_ShortW_Aff[Fp[Name], G1]
    delta2*: EC_ShortW_Aff[Fp2[Name], G2]

  ## Generic section containing multiple points on one of the curves. Will be unmarshaled into
  ## points on the correct curve afterwars.
  DataSection* = object
    points*: seq[seq[byte]]

  # `_b` suffix for raw binary
  ## NOTE: Maybe a `Raw` suffix would be better
  IC_b* = DataSection
  A_b*  = DataSection
  B1_b* = DataSection
  B2_b* = DataSection
  C_b*  = DataSection
  H_b*  = DataSection

  IC*[Name : static Algebra] = seq[EC_ShortW_Aff[Fp[Name], G1]]
  A*[Name  : static Algebra] = seq[EC_ShortW_Aff[Fp[Name], G1]]
  B1*[Name : static Algebra] = seq[EC_ShortW_Aff[Fp[Name], G1]]
  B2*[Name : static Algebra] = seq[EC_ShortW_Aff[Fp2[Name], G2]]
  C*[Name  : static Algebra] = seq[EC_ShortW_Aff[Fp[Name], G1]]
  H*[Name  : static Algebra] = seq[EC_ShortW_Aff[Fp[Name], G1]]

  Coefficient_b* = object
    matrix*: uint32
    section*: uint32
    index*: uint32
    value*: seq[byte] # n8r bytes

  Coefficients_b* = object
    num*: uint32 # number of coefficients
    cs*: seq[Coefficient_b]

  Coefficient*[Name: static Algebra] = object
    matrix*: uint32
    section*: uint32
    index*: uint32
    value*: Fr[Name]

  Coefficients*[Name: static Algebra] = object
    num*: uint32 # number of coefficients
    cs*: seq[Coefficient[Name]]

  Contributions* = object
    hash*: array[64, byte] # hash of the circuit
    num*: uint32 # number of contributions
    # for each contribution has some data

  Section* = object
    size*: uint64 # NOTE: in the real file the section type is *FIRST* and then the size
                 # But we cannot map this with a variant type in Nim (without using different
                 # names for each variant branch)
    case sectionType*: ZkeySectionKind
    of kInvalid: discard
    of kHeader: header*: Header
    of kGroth16Header: g16h: Groth16Header_b
    of kIC: ic: IC_b
    of kCoeffs: coeffs: Coefficients_b
    of kA: a: A_b
    of kB1: b1: B1_b
    of kB2: b2: B2_b
    of kC: c: C_b
    of kH: h: H_b
    of kContributions: contr: Contributions

  ## `ZkeyBin` is binary compatible with a `.zkey` binary file. Meaning it follows the structure
  ## of the file (almost) exactly. The only difference is in the section header. The size comes
  ## *after* the kind, which we don't reproduce in `Section` above
  ZkeyBin* = object
    magic*: array[4, char]
    version*: uint32
    numberSections*: uint32
    sections*: seq[Section] # Note: Because of the unordered nature of the sections
                           # the `sections` seq won't follow the binary order of
                           # the data in the file. Instead, we first record (kind, file position)
                           # of each different section in the file and then parse them in increasing
                           # order of the section types

  ## `Zkey` is a "typed" version of the binary file, where all field elements have already been
  ## unmarshalled according to the encoding spec used by SnarkJS.
  Zkey*[Name: static Algebra] = object
    version*: uint32
    header*: Header
    g16h*: Groth16Header[Name]
    ic*: IC[Name]
    coeffs*: Coefficients[Name]
    A*: A[Name]
    B1*: B1[Name]
    B2*: B2[Name]
    C*: C[Name]
    H*: H[Name]
    contr*: Contributions

## NOTE: These are rather ugly, but a result of the parsing approach we use.
## See note at the top of the file.
func header*(zkey: ZkeyBin): Header =
  result = zkey.sections.filterIt(it.sectionType == kHeader)[0].header

func Afield*(zkey: ZkeyBin): A_b =
  result = zkey.sections.filterIt(it.sectionType == kA)[0].a

func B1field*(zkey: ZkeyBin): B1_b =
  result = zkey.sections.filterIt(it.sectionType == kB1)[0].b1

func B2field*(zkey: ZkeyBin): B2_b =
  result = zkey.sections.filterIt(it.sectionType == kB2)[0].b2

func Cfield*(zkey: ZkeyBin): C_b =
  result = zkey.sections.filterIt(it.sectionType == kC)[0].c

func Hfield*(zkey: ZkeyBin): H_b =
  result = zkey.sections.filterIt(it.sectionType == kH)[0].h

func coeffs*(zkey: ZkeyBin): Coefficients_b =
  result = zkey.sections.filterIt(it.sectionType == kCoeffs)[0].coeffs

func groth16Header*(zkey: ZkeyBin): Groth16Header_b =
  result = zkey.sections.filterIt(it.sectionType == kGroth16Header)[0].g16h

func icField*(zkey: ZkeyBin): IC_b =
  result = zkey.sections.filterIt(it.sectionType == kIC)[0].ic

func contributions*(zkey: ZkeyBin): Contributions =
  result = zkey.sections.filterIt(it.sectionType == kContributions)[0].contr

func to*[Name: static Algebra](coefs: Coefficients_b, _: typedesc[Coefficients[Name]]): Coefficients[Name] =
  result = Coefficients[Name](num: coefs.num,
                              cs: newSeq[Coefficient[Name]](coefs.num))
  for i in 0 ..< coefs.num:
    let
      m = coefs.cs[i].matrix
      c = coefs.cs[i].section
      s = coefs.cs[i].index
    result.cs[i] = Coefficient[Name](
      matrix: m, section: c, index: s,
      value: toFr[Name](coefs.cs[i].value, true)
    )

proc to*[Name: static Algebra](g16h: Groth16Header_b, _: typedesc[Groth16Header[Name]]): Groth16Header[Name] =
  let alpha1 = g16h.alpha1.toEcG1[:Name]()
  let beta1  = g16h.beta1.toEcG1[:Name]()
  let beta2  = g16h.beta2.toEcG2[:Name]()
  let gamma2 = g16h.gamma2.toEcG2[:Name]()
  let delta1 = g16h.delta1.toEcG1[:Name]()
  let delta2 = g16h.delta2.toEcG2[:Name]()

  result = Groth16Header[Name](
    n8q: g16h.n8q,
    q: g16h.q,
    n8r: g16h.n8r,
    r: g16h.r,
    nVars: g16h.nVars,
    nPublic: g16h.nPublic,
    domainSize: g16h.domainSize,
    alpha1: alpha1,
    beta1: beta1,
    beta2: beta2,
    gamma2: gamma2,
    delta1: delta1,
    delta2: delta2
  )

proc toZkey*[Name: static Algebra](zkey: ZkeyBin): Zkey[Name] =
  result = Zkey[Name](
    version: zkey.version,
    header: zkey.header(),
    g16h: zkey.groth16header().to(Groth16Header[Name]),
    ic: zkey.icField().points.asEC(Fp[Name]),
    coeffs: zkey.coeffs().to(Coefficients[Name]),
    A: zkey.AField().points.asEC(Fp[Name]),
    B1: zkey.B1Field().points.asEC(Fp[Name]),
    B2: zkey.B2Field().points.asEC2(Fp2[Name]),
    C: zkey.CField().points.asEC(Fp[Name]),
    H: zkey.HField().points.asEC(Fp[Name]),
    contr: zkey.contributions()
  )

proc initSection(kind: ZkeySectionKind, size: uint64): Section =
  result = Section(sectionType: kind, size: size)

template zkeySection(sectionSize, body: untyped): untyped =
  let startOffset = f.getFilePosition()

  body

  return sectionSize.int == f.getFilePosition() - startOffset

proc parseMagicHeader(f: File, mh: var array[4, char]): bool =
  result = f.readInto(mh)

proc parseSectionKind(f: File, v: var ZkeySectionKind): bool =
  var val: uint32
  result = f.parseInt(val, littleEndian)
  v = ZkeySectionKind(val.int)

proc parseHeader(f: File, h: var Header): bool =
  ?f.parseInt(h.proverType, littleEndian) # byte size of the prime number
  doAssert h.proverType == 1, "Prover type must be `1` for Groth16, found: " & $h.proverType
  result = true # would have returned before due to `?` otherwise

proc parseGroth16Header(f: File, g16h: var Groth16Header_b): bool =
  var buf: seq[byte]
  for field, v in fieldPairs(g16h):
    when typeof(v) is uint32:
      ?f.parseInt(v, littleEndian)
    elif typeof(v) is seq[byte]:
      when field == "q":
        doAssert g16h.n8q != 0, "Parsing failure, `n8q` not parsed."
        buf.setLen(g16h.n8q)
      elif field == "r":
        doAssert g16h.n8r != 0, "Parsing failure, `n8r` not parsed."
        buf.setLen(g16h.n8r)
      elif field.endsWith("1"): # 2 * n8q bytes
        doAssert g16h.n8q != 0, "Parsing failure, `n8q` not parsed."
        buf.setLen(2 * g16h.n8q)
      elif field.endsWith("2"): # 4 * n8q bytes
        doAssert g16h.n8q != 0, "Parsing failure, `n8q` not parsed."
        buf.setLen(4 * g16h.n8q)
      else:
        raiseAssert "Unsupported field: " & $field
      ?f.readInto(buf)
      v = buf
    else:
      raiseAssert "Unsupported type: " & $typeof(v)
  result = true

proc parseDataSection(f: File, d: var DataSection, sectionSize: uint64, elemSize: uint32): bool =
  ## Parses a generic data section, each `elemSize` in size
  let numElems = sectionSize div elemSize.uint64
  var buf = newSeq[byte](elemSize)
  d.points.setLen(numElems.int)
  for i in 0 ..< numElems:
    ?f.readInto(buf)
    d.points[i] = buf ## XXX: fix me
  result = true

proc parseDatasection(f: File, s: var Section, kind: ZkeySectionKind, size: uint64, zkey: var ZkeyBin): bool =
  let g16h = zkey.sections.filterIt(it.sectionType == kGroth16Header)[0].g16h ## XXX: fixme
  echo "Parsing data section: ", kind
  case kind
  of kIC:            ?f.parseDataSection(s.ic, size, 2 * g16h.n8q)
  of kA:             ?f.parseDataSection(s.a, size, 2 * g16h.n8q)
  of kB1:            ?f.parseDataSection(s.b1, size, 2 * g16h.n8q)
  of kB2:            ?f.parseDataSection(s.b2, size, 4 * g16h.n8q)
  of kC:             ?f.parseDataSection(s.c, size, 2 * g16h.n8q)
  of kH:             ?f.parseDataSection(s.h, size, 2 * g16h.n8q)
  else:
    raiseAssert "Not a data section: " & $kind
  result = true

proc parseCoefficient(f: File, s: var Coefficient_b, size: uint64): bool =
  ?f.parseInt(s.matrix, littleEndian)
  ?f.parseInt(s.section, littleEndian)
  ?f.parseInt(s.index, littleEndian)
  s.value = newSeq[byte](size)
  ?f.readInto(s.value)
  result = true

proc parseCoefficients(f: File, s: var Coefficients_b, zkey: ZkeyBin): bool =
  ?f.parseInt(s.num, littleEndian)
  let g16h = zkey.sections.filterIt(it.sectionType == kGroth16Header)[0].g16h ## XXX: fixme
  s.cs = newSeq[Coefficient_b](s.num)
  for i in 0 ..< s.num: # parse coefficients
    echo "Parsing coefficient with : ", g16h.n8r, " bytes"
    ?f.parseCoefficient(s.cs[i], g16h.n8r)
  result = true

proc parseContributions(f: File, s: var Contributions): bool =
  ?f.readInto(s.hash)
  ?f.parseInt(s.num, littleEndian)
  # XXX: parse individual contributions
  result = true

proc parseSection(f: File, s: var Section, kind: ZkeySectionKind, size: uint64, zkey: var ZkeyBin): bool =
  # NOTE: The `zkey` object is there to provide the header information to
  # the constraints section
  s = initSection(kind, size)
  case kind
  of kHeader:        ?f.parseHeader(s.header)
  of kGroth16Header: ?f.parseGroth16Header(s.g16h)
  of kIC, kA .. kH:  ?f.parseDataSection(s, kind, size, zkey)
  of kCoeffs:        ?f.parseCoefficients(s.coeffs, zkey)
  of kContributions: ?f.parseContributions(s.contr)
  else: raiseAssert "Invalid"

  result = true # would have returned otherwise due to `?`

proc parseSection(f: File, zkey: var ZkeyBin): Section =
  var kind: ZkeySectionKind
  var size: uint64
  doAssert f.parseSectionKind(kind), "Failed to read section type in section "
  echo "Got section kind::: ", kind

  doAssert f.parseInt(size, littleEndian), "Failed to read section size in section "

  result = initSection(kHeader, size)

  doAssert f.parseSection(result, kind, size, zkey), "Failed to parse section: " & $kind

proc parseZkeyFile*(path: string): ZkeyBin =
  var f = fileio.open(path, kRead)

  doAssert f.parseMagicHeader(result.magic), "Failed to read magic header"
  doAssert f.parseInt(result.version, littleEndian), "Failed to read version"
  doAssert f.parseInt(result.numberSections, littleEndian), "Failed to read number of sections"

  for i in 0 ..< result.numberSections:
    let s = parseSection(f, result)
    result.sections.add s

  fileio.close(f)
