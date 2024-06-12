import
  std/[os, unittest, strutils],
  ../../constantine/proof_systems/constraint_systems/r1cs_circom_parser


suite "R1CS binary file parser":

  test "Parse basic example R1CS file":
    # Note: The example test file used here is from:
    # https://github.com/iden3/r1csfile/tree/master/test/testutils
    const path = "r1cs_test_files/example.r1cs"
    let r1cs = parseR1csFile(path)

    ## XXX: On 32bit systems `seq[BaseType]` should have twice as many elements
    ## in the `expABCs` below as `value` arguments!

    # For expected data see also the JS test case in the repo where the example
    # file is from:
    # https://github.com/iden3/r1csfile/blob/master/test/r1csfile.js
    let expHeader = Section(
      size: 64, sectionType: kHeader,
      header: Header(fieldSize: 32,
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
    let expABCs = @[(A: @[(index: int32 5, value: @[uint64 3, 0, 0, 0]),
                          (index: int32 6, value: @[uint64 8, 0, 0, 0])],
                     B: @[(index: int32 0, value: @[uint64 2, 0, 0, 0]),
                          (index: int32 2, value: @[uint64 20, 0, 0, 0]),
                          (index: int32 3, value: @[uint64 12, 0, 0, 0])],
                     C: @[(index: int32 0, value: @[uint64 5,0, 0, 0]),
                          (index: int32 2, value: @[uint64 7, 0, 0, 0])]),
                    (A: @[(index: int32 1, value: @[uint64 4, 0, 0, 0]),
                          (index: int32 4, value: @[uint64 8, 0, 0, 0]),
                          (index: int32 5, value: @[uint64 3, 0, 0, 0])],
                     B: @[(index: int32 3, value: @[uint64 44, 0, 0, 0]),
                          (index: int32 6, value: @[uint64 6, 0, 0, 0])],
                     C: @[]),
                    (A: @[(index: int32 6, value: @[uint64 4, 0, 0, 0])],
                     B: @[(index: int32 0, value: @[uint64 6, 0, 0, 0]),
                          (index: int32 2, value: @[uint64 11, 0, 0, 0]),
                          (index: int32 3, value: @[uint64 5, 0, 0, 0])],
                     C: @[(index: int32 6, value: @[uint64 600, 0, 0, 0])])]
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
