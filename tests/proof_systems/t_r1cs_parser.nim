import
  std/[os, unittest, strutils],
  constantine/proof_systems/constraint_systems/r1cs_circom_parser


const TestDir = currentSourcePath.rsplit(DirSep, 1)[0]
suite "R1CS binary file parser":

  test "Parse basic example R1CS file":
    # Note: The example test file used here is from:
    # https://github.com/iden3/r1csfile/tree/master/test/testutils
    const path = TestDir / "r1cs_test_files/example.r1cs"
    let r1cs = parseR1csFile(path)

    # For expected data see also the JS test case in the repo where the example
    # file is from:
    # https://github.com/iden3/r1csfile/blob/master/test/r1csfile.js
    # Note: The `value` fields of the `LinComb` `Factor` fields is here given in
    # raw bytes, same as the `prime` field of the `Header` in contrast to the JS
    # test. That's why the numbers "differ".
    let expFieldSize = 32'u32
    let expHeader = Section(
      size: 64, sectionType: kHeader,
      header: Header(fieldSize: expFieldSize,
                     prime: @[1, 0, 0, 240, 147, 245, 225, 67, 145, 112, 185,
                              121, 72, 232, 51, 40, 93, 88, 129, 129, 182, 69,
                              80, 184, 41, 160, 49, 225, 114, 78, 100, 48],
                     nWires: 7,
                     nPubOut: 1,
                     nPubIn: 2,
                     nPrvIn: 3,
                     nLabels: 1000,
                     nConstraints: 3
      )
    )

    template setVals(args: varargs[byte]): untyped =
      var res = newSeq[byte](expFieldSize)
      for i, x in @args:
        res[i] = x
      res
    let expABCs = @[(A: @[(index: int32 5, value: setVals 3),
                          (index: int32 6, value: setVals 8)],
                     B: @[(index: int32 0, value: setVals 2),
                          (index: int32 2, value: setVals 20),
                          (index: int32 3, value: setVals 12)],
                     C: @[(index: int32 0, value: setVals 5),
                          (index: int32 2, value: setVals 7)]),
                    (A: @[(index: int32 1, value: setVals 4),
                          (index: int32 4, value: setVals 8),
                          (index: int32 5, value: setVals 3)],
                     B: @[(index: int32 3, value: setVals 44),
                          (index: int32 6, value: setVals 6)],
                     C: @[]),
                    (A: @[(index: int32 6, value: setVals 4)],
                     B: @[(index: int32 0, value: setVals 6),
                          (index: int32 2, value: setVals 11),
                          (index: int32 3, value: setVals 5)],
                     C: @[(index: int32 6, value: setVals(88, 2))])]
    let expConstraints = Section(
      size: 648, sectionType: kConstraints,
      constraints: expABCs
    )
    let expW2lSection = Section(
      size: 56, sectionType: kWire2LabelId,
      w2l: Wire2Label(wireIds: @[uint64 0, 3, 10, 11, 12, 15, 324])
    )
    let expSections = @[expHeader, expConstraints, expW2lSection]
    let expected = R1csBin(magic: ['r', '1', 'c', 's'],
                           version: 1,
                           numberSections: 3,
                           sections: expSections)

    ## NOTE: Cannot do `==` because compiler doesn't auto generate `==` for variant objects
    check r1cs.magic == expected.magic
    check r1cs.version == expected.version
    check r1cs.numberSections == expected.numberSections
    check r1cs.sections.len == expected.sections.len
    for i in 0 ..< r1cs.sections.len:
      let s = r1cs.sections[i]
      let e = expected.sections[i]
      check s.sectionType == e.sectionType
      check s.size == e.size
      case s.sectionType:
      of kInvalid: discard
      of kHeader:                 check s.header == e.header
      of kConstraints:            check s.constraints == e.constraints
      of kWire2LabelId:           check s.w2l == e.w2l
      of kCustomGatesList:        check s.cGatesList == e.cGatesList
      of kCustomGatesApplication: check s.cGatesApp == e.cGatesApp
