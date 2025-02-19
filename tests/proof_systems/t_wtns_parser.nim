import
  std/[os, unittest, strutils],
  constantine/proof_systems/constraint_systems/wtns_binary_parser,
  constantine/named/algebras,
  constantine/math/io/io_fields,
  constantine/math/arithmetic,
  constantine/proof_systems/groth16_utils

const TestDir = currentSourcePath.rsplit(DirSep, 1)[0]
suite "Witness (.wtns) binary file parser":

  test "Parse Moonmath 3-factorization `.wtns` file":
    const path = TestDir / "groth16_files/witness.wtns"
    let wtns = parseWtnsFile(path)

    block CheckRaw:
      check wtns.magic == ['w', 't', 'n', 's']
      check wtns.version == 2
      check wtns.numberSections == 2

      let expHeader = WitnessHeader(
        n8: 32,
        r: @[1, 0, 0, 240, 147, 245, 225, 67, 145, 112, 185, 121, 72, 232, 51, 40, 93, 88, 129, 129, 182, 69, 80, 184, 41, 160, 49, 225, 114, 78, 100, 48],
        num: 6
      )

      check wtns.sections.len == 2

      let h = wtns.sections[0]
      check h.size == 40
      check h.sectionType == kHeader
      check h.header == expHeader
      # check header `r` field is indeed field modulus
      let rb = toFr[BN254_Snarks](h.header.r)
      check rb.isZero().bool

      let w = wtns.sections[1]
      check w.size == 192
      check w.sectionType == kData

      func toWitness(s: seq[byte]): Witness = Witness(data: s)
      let expWtns = @[
        toWitness @[byte 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        toWitness @[byte 211, 12, 174, 248, 219, 66, 74, 118, 56, 33, 96, 120, 222, 127, 224, 3, 223, 23, 92, 96, 143, 206, 39, 36, 252, 6, 62, 238, 113, 252, 22, 21],
        toWitness @[byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 72, 69, 30, 210, 222, 206, 150, 0],
        toWitness @[byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 164, 14, 153, 21, 107, 162, 37],
        toWitness @[byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 192, 6, 137, 28, 241, 2, 204, 4],
        toWitness @[byte 192, 241, 127, 208, 49, 238, 224, 192, 158, 180, 48, 145, 210, 42, 166, 8, 7, 60, 29, 157, 205, 128, 142, 152, 99, 179, 236, 248, 41, 210, 204, 45]
      ]

      check w.wtns == expWtns

    block CheckTyped:
      const T = BN254_Snarks
      let wtns = wtns.toWtns[:T]()

      echo wtns

      let expW = @[
        Fr[T].fromHex("0x0000000000000000000000000000000000000000000000000000000000000001"),
        Fr[T].fromHex("0x1516fc71ee3e06fc2427ce8f605c17df03e07fde78602138764a42dbf8ae0cd3"),
        Fr[T].fromHex("0x0096ceded21e4548000000000000000000000000000000000000000000000000"),
        Fr[T].fromHex("0x25a26b15990ea400000000000000000000000000000000000000000000000000"),
        Fr[T].fromHex("0x04cc02f11c8906c0000000000000000000000000000000000000000000000000"),
        Fr[T].fromHex("0x2dccd229f8ecb363988e80cd9d1d3c0708a62ad29130b49ec0e0ee31d07ff1c0")
      ]

      for i, w in wtns.witnesses:
        check (w == expW[i]).bool
