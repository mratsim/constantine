import constantine/platforms/[fileio, abstractions]

proc parseMagicHeader*(f: File, mh: var array[4, char]): bool =
  ## Parses the magic header of the 3 types of binary files into `mh`
  result = f.readInto(mh)

proc parseSectionKind*[T](f: File, v: var T): bool =
  ## Parses a section kind `T` which should be one of
  ## `ZkeySectionKind`, `WtnsSectionKind` or `R1csSectionKind`
  var val: uint32
  result = f.parseInt(val, littleEndian)
  v = T(val.int)

template parseCheck*(sectionSize, body: untyped): untyped =
  let startOffset = f.getFilePosition()

  body

  return sectionSize.int == f.getFilePosition() - startOffset

proc parseSection*[S; T; U](f: File, sec: var S, bin: T, sectionKind: typedesc[U]): bool =
  ## Parses the section into `sec`.
  ## Note: not used for R1CS, because we already preparse the section headers to
  ## be able to parse the sections in the correct order.
  var kind: sectionKind # Zkey/Wtns SectionKind
  var size: uint64
  doAssert f.parseSectionKind[:sectionKind](kind), "Failed to read section type in section "
  doAssert f.parseInt(size, littleEndian), "Failed to read section size in section "

  mixin initSection
  mixin kHeader
  sec = initSection(kHeader, size)

  mixin parseSection
  result = f.parseSection(sec, kind, size, bin)
