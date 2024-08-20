import
  std/[os, unittest, strutils, json],
  constantine/proof_systems/constraint_systems/zkey_binary_parser,
  constantine/named/algebras,
  constantine/platforms/abstractions,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/[arithmetic, extension_fields],
  constantine/proof_systems/groth16_utils

## The two procs below are to serialize `ZkeyBin` and `Zkey` to JSON.
proc `%`(c: char): JsonNode = % ($c)
proc `%`(c: SecretWord): JsonNode = % (c.uint64)

const UpdateTestVectors = false
const RawVec = "groth16_files/t_zkey_bin.json"
const TypedVec = "groth16_files/t_zkey.json"

const TestDir = currentSourcePath.rsplit(DirSep, 1)[0]
suite "Zkey (.zkey) binary file parser":


  ## NOTE: We perform the check of whether we parse the `.zkey` binary file correctly
  ## by writing the Zkey types as JSON data. Ideally, we would explicitly check each
  ## field, but given the large number of fields, it would make for a pretty big
  ## test case. Given that the parsed data has been utilized for a successful Groth16
  ## proof, we consider the stored JSON files as 'correct'.
  test "Parse Moonmath 3-factorization `.zkey` file":
    const path = TestDir / "groth16_files/three_fac_final.zkey"
    let zkey = parseZkeyFile(path)

    let zj = % zkey

    when UpdateTestVectors:
      writeFile(RawVec, zj.pretty())
    block CheckRaw:
      check zkey.magic == ['z', 'k', 'e', 'y']
      check zkey.version == 1
      check zkey.header().proverType == 1
      check zkey.numberSections == 10

      # read expected test vector
      let exp = RawVec.readFile().parseJson()
      check zj == exp

    block CheckTyped:
      const T = BN254_Snarks
      # convert to 'typed' (unmarshalled) type
      let zkey = zkey.toZkey[:T]()

      let zj = % zkey
      when UpdateTestVectors:
        writeFile(TypedVec, zj.pretty())

      # read expected test vector
      let exp = TypedVec.readFile().parseJson()
      check zj == exp
