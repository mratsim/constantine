# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times],
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/towers,
  ../constantine/io/[io_bigints, io_ec],
  ../constantine/elliptic/[ec_shortweierstrass_projective, ec_scalar_mul, ec_endomorphism_accel],
  # Test utilities
  ./support/ec_reference_scalar_mult

echo "\n------------------------------------------------------\n"

proc test(
       id: int,
       EC: typedesc[ECP_ShortW_Proj],
       Px, Py: string,
       scalar: string,
       Qx, Qy: string
     ) =

  test "test " & $id:
    var P: EC
    let pOK = P.fromHex(Px, Py)
    doAssert pOK

    var Q: EC
    let qOK = Q.fromHex(Qx, Qy)

    let exponent = BigInt[EC.F.C.getCurveOrderBitwidth()].fromHex(scalar)

    var
      impl = P
      reference = P
      endo = P
      endoW = P

    impl.scalarMulGeneric(exponent)
    reference.unsafe_ECmul_double_add(exponent)
    endo.scalarMulEndo(exponent)
    endoW.scalarMulGLV_m2w2(exponent)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    doAssert: bool(Q == endo)
    doAssert: bool(Q == endoW)

suite "Scalar Multiplication (cofactor cleared): BLS12_377 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bls12_377.sage
  test(
    id = 0,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "4e7e6dfa01ed0ceb6e66708b07cb5c6cd30a42eeb13d7b76f8d103a0a4d491450be6f526fc12f15209b792220c041e",
    Py = "c782515159b7e7b9371e0e0caa387951317e993b1625d91869d4346621058a0960ef1b8b6eabb33cd5719694908a05",
    scalar = "cf815cb4d44d3d691b7c82a40b4b70caa9b0e8fe9586648abf3f1e2e639ca1b",
    Qx = "4a1203db4af8f0efc18c7ceb24999eb6e0dbdfc8f44a9edd5ba2f9eced38e81ecae287ab1c184eea8e8753d1178604",
    Qy = "f7509cdce5de473e37f36c69d93ff1b2ab04c3ae25a3b5e41f2c138cdcc69ed5eaf4ac95a7a857eef336ebac19bcd3"
  )

  test(
    id = 1,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "13d735b28405253dcc0bc60bcdc13633475ffc187d38a9b97655b0d0fa1d56c4548f11ea0a795391ee85c953aaf9b83",
    Py = "1693101123fd13a20f9c0569c52c29507ba1c8b6dd412660bc82e7974022f1a10f9137b4ba59d3f0aab67027cefec19",
    scalar = "913aa7b9fa2f940b70b6dcf538cc08da1a369809ab86a8ee49cead0ed6bfef6",
    Qx = "10e0e8582ec3456f7569473892c23997d004f2542d914fa75db8f1798ed8ce505836e8b7af5cf1503e14d85fadd65ee",
    Qy = "d5151ae60e43100e20aad7eaf8659e690e8034910d7717078031520fcbf6f9a00b22c6a9894aec88c9182f13335639"
  )

  test(
    id = 2,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "6dd2211113cada09d3b96848cbf21ed14f6fc238b581c0afd49aa776980101e4ee279a256ce8f1428d3ed3f70afd85",
    Py = "3b406b4433a3f44f8e196012f50c520e876412fbcae2651916f133c1fd3899c79f676e1abba01d84bab7ad100c9295",
    scalar = "4cf47669aeb0f30b6c6c5aa02808a87dc787fba22da32875e614a54a50b6a0c",
    Qx = "3caf55e1f82d746df2bf47defbee127a3e6f7e79a9575929704b25489ffb801dbce07999acbddfd79352b0633a2708",
    Qy = "3fc275c136b07456f0b6ee814508876037add5e95357fae6b4195744ba5ccccaf93581e34feb2babe652a9a704731b"
  )

  test(
    id = 3,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "18648abbe3261f93cbf679777eac66e419035041a967d1e6a0f0afdb92810d7122e0984f1d6efc8fe518500464ee803",
    Py = "7b6f518d4d06309aad4d60d29118310b6c8b17c7bf5db2251f4701b13b89a8c0f04bb5d0386785e55ffbbd7ecc445e",
    scalar = "69498486a06c18f836a8e9ed507bbb563d6d03545e03e08f628e8fbd2e5d098",
    Qx = "6a871d872673879fd23ec8c150f8d63e8130dc60343fc0c2ec9ff1b02e769e20eeec0288102ccec6ff2f6ac6973b4",
    Qy = "cd95a31afa4f0bbcc063a1585fec4a6c51812b2baaee42a04525fd55b3a9db3bdb7cbc77f7cd32f42d2e0eb26ddfa2"
  )

  test(
    id = 4,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "745e9944549522486f3446676cc62fb666682e10c661a13b8110b42cb9a37676b6f33a46f9495f4fafb342d5809db5",
    Py = "bc595854bc42ccec60dd9ec573608d736aa59996cef1c2e8f6c5d424f525a6f3e3d4beeedfac6b959dbd71ced95b13",
    scalar = "6e08d8714102a5aa3e9f46e33c70a759c27253c7b0196c3e46c7cb42671197e",
    Qx = "18a967a80785de8ec6ac9d98cffa06a8c633b5fa0f36431a32f7bd955946edc3d55f79bfdf5335db405560a6cbe2415",
    Qy = "4552ff2eb6ade0c6b33c3603460d9d62099201d842c9883b33b7ed1147cb17268338a77a9417776ddbd774e91a8d2"
  )

  test(
    id = 5,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "f7b56cf212a8906ed77a758164c0bd05ce1fbd3ee3c4357e7a09b3aedc748a29ace254f1f6df35b8cb74361060337f",
    Py = "2640ef641d20fea19b28947833e53faceeafa57a8761b807049f3d707d70c01f1c69a57edd993d301a64517bf47f77",
    scalar = "a5c46d7a52938fed7f3093d5867f65361dc8b48c83bd7db490c26736196e20e",
    Qx = "434f024c4afd7b9a44375011d663af0ae0fe79442e9caf36518e053bb13d49998ec1d2da4bc1c4a812812119b3221f",
    Qy = "32c959e2a678cf93f77e621fdf887454a5f9cb7a67f29065669f48234c25e321ceb5758dfba987431a0c2caec94616"
  )

  test(
    id = 6,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "43b387c12e4cc91fb1a5593b7671356dceb0fe6e6ac666d5bac94f2a44c8db54976b649a678aae038b21144de04e23",
    Py = "1a6366a50f1f9ba64eef73d82bec86177bf184be048a9d66326ccb0122203569ddcb8cf74445cadaff7f47a66d1b1a2",
    scalar = "bddd07231bc7fe89ee4a859a00ea1f9d236be9e7fd561303d566904c1b0a07c",
    Qx = "8ddb7a959483b51a1471de988146b7d5b166f660734b4d55166c5a23d781e923261927b1012dce73b822bb6e56bfd2",
    Qy = "dc7178bf5597ef31209a5b0409fc42c64b81260a0046a562ca08c7a9dc67b444c25e94fb97b9a6bb4c137cadd81021"
  )

  test(
    id = 7,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "6984c9385a67081f97b3d33444077466cca1d0442a4da8c083a0957578e0b21011435b126a5ab143da9da1cf5b216f",
    Py = "18a87c7f5f6c5a8101773e63956b9addd4becf5177acc560d548e5331638121934842fdc9f654b3f456a7df5a2e471a",
    scalar = "b72c41a6ffaff0aacb5d62e3dcb16acfec66b6a9639e19d3128fd43c18e7dbe",
    Qx = "19279201c3c7a9d50b546aa99d3e1a6625fe2a7bc64a09625b683534638b9e87b9102d4dba6684956b6be7668a658c6",
    Qy = "195f15ad1edc05f8b289c7eee7bd8f78116a2d5ba8b83643d9e7cb2cdc6550bcf8c2145008e900ca9cba4d5040e9f4"
  )

  test(
    id = 8,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "efc34595823e7333616f7768bc82f407268df6f029bf4c94d15f1785dc7ccc08f22e7301dfc48dadc0ea383c8bb3e",
    Py = "2459bd9f71977ef122d2102e8bfd07a5737066075058cfa8bcaa9f9690ed065919c844363ceaea6f9bb650906a535f",
    scalar = "8f90f6ab0ffa6e4acc601b44c062745f2935b3dc153d0da07977470080d5c18",
    Qx = "35d08b33e02579581905941975c8b1cc5be1c9670a7f7ef390daa363b0abd3571a802d8c27f156fba40573094f6c7a",
    Qy = "111ba3bdfa4260dc2b636479edb1fcf2fc9478aa722da0118908e1db1551cf7e131c8521b2f3708ef670684dbe8d181"
  )

  test(
    id = 9,
    EC = ECP_ShortW_Proj[Fp[BLS12_377]],
    Px = "3eec93c2a9c5fd03f0de5ede2fdac9e361090fbaea38e4a0f1828745f1d14a057d9fd7c46b9168bd95a45a182a3a62",
    Py = "e912dc7e95f90d91e3274ec5639edacb88be1b092c47c13d31a29ecd579885cc09f197f8207d23b2260ab10c94d5f5",
    scalar = "203300e949aff816d084a388f07c74b9152bb11b523543afd65c805a389980",
    Qx = "8c23ae9c51e7c92c6a59f0ed07a59f148b4d79394fc026931c264612041eedd3782e4f249bbfad1799212788c1a00d",
    Qy = "191628b702ebef397bb7c52102ee4522f864ff594b24dc385ece081e8066bcde20aa5c7dfd00fb1f3cea221b3ad4ea2"
  )


proc test(
       id: int,
       EC: typedesc[ECP_ShortW_Proj],
       Px0, Px1, Py0, Py1: string,
       scalar: string,
       Qx0, Qx1, Qy0, Qy1: string
     ) =

  test "test " & $id:
    var P: EC
    let pOK = P.fromHex(Px0, Px1, Py0, Py1)
    doAssert pOK

    var Q: EC
    let qOK = Q.fromHex(Qx0, Qx1, Qy0, Qy1)

    let exponent = BigInt[EC.F.C.getCurveOrderBitwidth()].fromHex(scalar)

    var
      impl = P
      reference = P
      endo = P

    impl.scalarMulGeneric(exponent)
    reference.unsafe_ECmul_double_add(exponent)
    endo.scalarMulEndo(exponent)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    doAssert: bool(Q == endo)

suite "Scalar Multiplication G2: BLS12-381 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bls12_377.sage
  test(
    id = 0,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "267401f3ef554fe74ae131d56a10edf14ae40192654901b4618d2bf7af22e77c2a9b79e407348dbd4aad13ca73b33a",
    Px1 = "12dcca838f46a3e0418e5dd8b978362757a16bfd78f0b77f4a1916ace353938389ae3ea228d0eb5020a0aaa58884aec",
    Py0 = "11799118d2e054aabd9f74c0843fecbdc1c0d56f61c61c5854c2507ae2416e48a6b2cd3bc8bf7495a4d3d8270eafe2b",
    Py1 = "823b9f8fb9f8297734a14359fa2c2a0de275e7e638197eaaaa7cff28f9cb3101bdabb570016672455f1ecae625e294",
    scalar = "9d432eb58ec68bbc09d10961451d99c7796fb2f795eca603d6feaf3e2a1634b",
    Qx0 = "12cfcb50345d43271d2a20e8208789c8ca82f2b8732fae4e7cccd87eb0883741d5e77166971c38c54170bf7635ca2f3",
    Qx1 = "17467c786368f2f6eabd78f1c24aa668eae9cd00f6045bfd86b1b3c40966f023a71927026ae5a1281b432ac980d2b6b",
    Qy0 = "6f5f1068b6e6a8fafd96894d8b0a8548acee24319d8e2d8b6e6982b1ced8970d9fe33155e74b33d6c2a7835196ca9",
    Qy1 = "dc3c7c91c712f9a2631d2b5e49497d8cdf2ea4b30859b43edd716e84cd6a8b61e63cf708d263a7845913cdfb9c7f3b"
  )

  test(
    id = 1,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "3a3055d6a46901c1b2227a0e334ffa9f654e62a6d3608f3a672e5816f9e9b04c0e668c3e9f8c807b269422afdc7de9",
    Px1 = "25803bd55f37b254865d5fc7ac9843fb306c2eb09d34ee0c4ecb705b5e10f6911f07fd707a2e28681a421f45b1a4d",
    Py0 = "15a0594a3c9dddc535472c4827aa443774a06f77bec2d20837c6574aa5fac35a279bac756531fa75f979a7a97f297d6",
    Py1 = "15e8c3e013cbc64110f075295f39a4f85c9591a52b8e4903047b1f4b44bb5216b6339788c82fd90e82b1027756e7987",
    scalar = "a0067f5b4294fbacd24730fed25c936a08b5f1a77824149ad6c2ce476518d17",
    Qx0 = "6280dbf019f8d94acac4a39213e03f221be732849b45437edef7617460e83f972883c20791a86670a8a4c6c0125629",
    Qx1 = "ab3a185addbd6c7db907170d75bd2f1997666e93d8cedbef9e10a103110d4ea09d9a889f505d7026e5c498b0355c1",
    Qy0 = "1a6dd15b4c2bd6bd97858e5a75ac4365f8becaa885c4e3267d0ae256655cd057061d61b2b9acbd10bdf678a9c1e7f8c",
    Qy1 = "16204b5825eec903cb7798cb62ccadb9004032d72bb815958fcd2f613c77e147656449fdaa210994338978676ad6b0e"
  )

  test(
    id = 2,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "18ebf549cd24a64badff4ec177205be121757b68589020434aba816756d2e6fa95fdb389c8639d4bf77575122e1c04e",
    Px1 = "11cd0f0976658a6f2ec113034428ef1605befdaa5642944f5c4e571b24fc166c368c30473e25ab148209be4c0b4e37",
    Py0 = "1190d818317495201732feb2cfc8f507adac6273debff46bb6aea4a3f3e3fe7d28d893c90b21a6f28d2fbc72d9fc528",
    Py1 = "df5fcb2daa302a5c64aeef96835e0a6b39f5d7bf0e70cc10401f966745a6b3fa682b7e5b45d9295e744e1dd7855fd4",
    scalar = "7a49802ba58c87c30b631b2f90a3b876c7143e09b542c9c14706bddf9bd4117",
    Qx0 = "6cdff80576d8695a646f915caba5bc6748eee1707bb0d4ebcabaf8d236b780aef6a953a07f48ef4696f02db4906c71",
    Qx1 = "6b64ca5f0d46702e7e9e7beb1993b698c9b3e9991f545241d5fd44a27dc692d5f5a4c2fe6871af0653128f960307d4",
    Qy0 = "cfad02b664495d42d1c6b598306229c67bcf76cc923abb13ae038c90e959a7611161a98d607729577d55ec18bf1e74",
    Qy1 = "e433d9dd7d47d94e9f61a5bc27a688c63efa05408d6fd40a5c4e2711a37d011dc80f5dbaaafd939a07235c770feead"
  )

  test(
    id = 3,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "52b54c30c1dcadbcb698d0cb7fd65de1eb8f7590c7afe46e019bdc9e0ef8bc4c060339220d3615e4b1f2b12ffa6d83",
    Px1 = "dd53b483c2ab1aaa7ed22ef619b5e979237ae95476436f2c51c8b70da39a4e54a989f10f6d12ee098154911aa052f6",
    Py0 = "2a8c96662a7c76cb7d8ca6571a5b99abfd2d7343dd668425e5fa4a8c880b313b70f09a15a825fac63ae7065c0c51d",
    Py1 = "7bd93bb9d5bfdd15636a34a13385e9abbc1088ecc02c86cbc733122ccbbb657ec8d75e47102ce46d35a9612c01fc3d",
    scalar = "e0c564e69ad68343fd4ec3d4dafdf6a92f44c13fc70a9aad95d10b2c96ee747",
    Qx0 = "126f6039b7031b73a7f926bd443ace416f62e56f03864d660bbe1f1a2a994672d408f9936293f367d3fb5d8e275ad40",
    Qx1 = "1654a2c26479ace1eb68e279eceac6aa10680549b09f42d288767f6296c98ba4299fa6df37a946b88823a5deebc231c",
    Qy0 = "23026839059191f71e2abcf582234aa2ce4b4225c3d503e8fc6c119df1168192e894f33ed48bc571e5527365dd92b5",
    Qy1 = "11f8fcce53f5e3211290e6c72736eb1c9d2e159dd243f3e493c430f0411864e109af09a3b9379c4b332815e012caa80"
  )

  test(
    id = 4,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "fb6dd822e327a60c9e55d760c4f5d26783617a06f868835c2f46e902108eaca5d60fd64c0a0c8a6dc12f9352dfef33",
    Px1 = "85e97eef3b4e42a93b8421644e9334f4543a25a36ccd41d448c385146baf3b1efbaeac49c202b04cdbf8b50f3fd962",
    Py0 = "8db78b315a524f17ac3d69333604e6bc8aa0b2f138f9adf7edb19f49c847eda6b64df9fe2576b7687e7b55cb5f0bd0",
    Py1 = "d4a0c7e5e7aaacab0e0e60c6c49624971a161de4f0daa7968f80998fb7b4761b1196964b26fefa9337fd133784e3d9",
    scalar = "1abce9e9c079c686864304d479d68087db33f9edb3f7b2e4655fe0c1da4993f",
    Qx0 = "1238814ea497bc1b65ba1c0fbfc394427b10b2d8783bf6a04e01505bc165b577cb2366c19c24c555235ff9b16e7233a",
    Qx1 = "b156205cad5d2d97d24c45fe218cd412f47248f26d579fb368af5ba2d80b8c95e2a68f4c84540a8b78b2f0a33a48a4",
    Qy0 = "12154ce4a569b39ccfe464a7559b8baf03d3fb6462e67dc0c4ae79a3c33b7756e0c558eff64f9558ebd6500086684f8",
    Qy1 = "74571a18fc091f4d77cc7d363bf7a34ab4d0dca86c160b261b383e416f68fa553d7b8b8f6317c8e340ce454daffb5f"
  )

  test(
    id = 5,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "b56e23f2558c3c124f024952e1858067223541f51a8885d161133beb7bf8d64f22163769e604afbf7fbfb02e1fcb43",
    Px1 = "e10c4366d667b40488a9ae32daf3e2a5cc8ddf25ed407afe1a38b855f3ac4f7ea20455924e71369eed07114613b633",
    Py0 = "f42d3ab4716d10384bcdfec38cba997c2bafb8d8de32a47225a3e2d2835be1ad02a63323d3dd4145db21e3cbf5cc7a",
    Py1 = "15f48a901f3dfd3b812a455f1297e8311c4608869ea02d3d16e9aafdf610d7e72f34b02830de8cc0d0f4e909af5827d",
    scalar = "401e70df8ccaa504da72b1d649c067f3b752156dcea5b48dcb601710ab0baa3",
    Qx0 = "949099ea1ece1be6fa3f3537e8ba39587b40003fb409a4beb831bb1d9d999b7c621b9a1ced3223f710e0bd05f4a018",
    Qx1 = "cdfc0d47788bca3672126e0facc05c19a4fb24a43eee32c8e08a6e5152f6af1d7c2efa48907046f90a721ed28fcf7",
    Qy0 = "11d608a01cfe1a40806b9951f85a7bb1b6df6e4c4e2c7c50c17e8fad6ed397a430aff9b4742408367d6536fe503692a",
    Qy1 = "19c25d8a782b9d8d9f067d345fd03afe50439c82f99a06abca790f2fae944677d8095d2e276fcb7a75cfb2cbccf89d7"
  )

  test(
    id = 6,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "137001541ab8a479362ee39f818fc38788231e5288ceea5ebe0c08d0bbca3be9519aa415bde98428df26d361b7311ea",
    Px1 = "411b1a4f0abb9fd255a7ae26ac39c1f2c88a48f82c7623b6f225aec9755206e27084b23cbc98f31399405a6599dc54",
    Py0 = "833ef097986116cab669c4fddff9b831535d100644f732fb0da0a2dce17d69beaeed67230dd66392e840679afbae1e",
    Py1 = "f63e809bd55617c31570d686dbc9b94b3cb96c154f9983181cb913a0671c0c16143332087e44a0283ebf01eea6d73b",
    scalar = "10697220c755c800861d377c55b22ae48c25dc144e1fa7a1e5bbdf82993aa33c",
    Qx0 = "10fc7772bb2bc946e3ff659c01a0452ebf5dd1472bd1aa71e198597fd05361bf0d173817f91fcb8a1b96b46c35d2675",
    Qx1 = "d7b00ddf32f9d8e549c05dd605931ef737d8a4bc62795f73044482957b8093b1cdad0f55c7d4edf6f59594a13f9b67",
    Qy0 = "148756a592dec0bf2fda41ac219c4a891ef427665ba1cf47b58bed4996cf8937fb07929c041f10e8a55b2238944fd30",
    Qy1 = "e4a240f5c32dab76575ace4d035cbd1e2b87d7585fee7bfde9c88e918a7ad2cd8eb4982acfacfac58c33c8a54ddac7"
  )

  test(
    id = 7,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "1580ffccc21b057dfe4831f950cbb8f1436f999df657404ecec20225a929a5d56920e8662abc426de23402643087308",
    Px1 = "8bf8ff20713a9054aa1cce9635eb3d6ac8371fc052b747a8414595708ff9462d64a0a11ff2c1c5121f4ecc5f22df5e",
    Py0 = "e7a5f7df0cec03de25da415fdda485ecc1443b95352e47b23e5506b820c9bc9ea9c2d9e99dd48e1f74e1befe58ce80",
    Py1 = "12b5638a0f7e508016fddd2dae2d84736efa59c53f2a5d979b9a29fc7c9c406407bb5f5788bcea3529ac1a763c72e8b",
    scalar = "bd936c7066316d3f86b077419a0c0fb9867d4612208241fc004b548f1f54fad",
    Qx0 = "69e3411725062858ca7e5fc4d648037baf10e34ba6830ff0090e7188932112b9458c4f4b82f2f0f06c6501fcdaa86c",
    Qx1 = "127b75c55c90a872c1d749d05609d2499065ac3c9eb96bd6a9816bd7a2315795ddf40944baef1907676395df306860e",
    Qy0 = "13fd0e314159909d3091e382017b35ec21ee2004e9082cd24338817046ed2202ffed52e7714cf436b953f95f49f9856",
    Qy1 = "5a8ccdf4a1600fafcc86c646d83199c41cbfebf7a1fa2b1cb9c408352be46a33d0f411b175348f42382d170e17ec2b"
  )

  test(
    id = 8,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "10898a074b6931cc4ada152b64dd1c6b2bb47912e6502b9e88f638e489c144f8aa9b9f915bb428e082ec84676607f40",
    Px1 = "18484823648fe1699468e2d265cd2f2e381a0e67f35f8d192259e2a14573692b4e1fbdeed639e9b6eb0731be820b166",
    Py0 = "1840bc6fcb224efe00e32f827fa4f9694cd4186493089c66a936e912b50346b75542b6edbe51ba95c88d3b0fcac34ed",
    Py1 = "18cb4201510933776a28ff1c44d356ceab065880f5242d8cc7cdf86874568df679b20f34b6a216d0047d2e1c1a16b85",
    scalar = "bdb46c0eece9c8bac8a382def90b522b1d5197f09cf9f7cd98b710845ddb7b4",
    Qx0 = "102779766b0068b176e118348e4163e89e3171e6eaad0e47f00cad626f8db025ec3ea990363813882c3dcfcbb642240",
    Qx1 = "131eb563d2b0145eee52ee7586acd0254f103f02a20de3bf0202d1cffec2c3628501ec20f9f2ae5f461b59604afc04c",
    Qy0 = "1463527db149d2c76f30c082786edb3fe1a9c7f4e04f9496e7adb40aab89340d9792f7d75cf3f5f81b0a28f09625175",
    Qy1 = "f3190261db082c207ccd88a3ba762d2c0ba330548444afca03c8535ff11c7c90659a867dda3712a83f02ad184eb24a"
  )

  test(
    id = 9,
    EC = ECP_ShortW_Proj[Fp2[BLS12_377]],
    Px0 = "13c3a392307124afb5f219ba0f8062fa9b75654d3fff12bc924592d284af550f039b6ac58880d2c6fea146b3982f03c",
    Px1 = "188169bc937fcc20cc9c289adef30580188f64ecb126faadb5b888f31b813727ff7046d1a19b81abeea6609b8b208c6",
    Py0 = "2f9bde8fdd43c5f4de30f335a480dca3bf0858464d8368984406f10ddc1ecabb15fcfd11cebd4fef426e7ca9411221",
    Py1 = "25505653e199c354f2da8a13ed9de47f9b51a06ad2fa8826c4b8a9c61c6e75268807d7053e06bfc2899d1a3d6deeb4",
    scalar = "91c6249ee16ef94d0b905575982419a7cf31d125775e7ede5c0ab4f86defd33",
    Qx0 = "1967547943b197311a7d6723dcc37c3e649f173cec1c88ffca27df86518b3392ae0ee13dbca375c928b94d129226852",
    Qx1 = "18b793916195f2d7d2a47c3f8243e5bdc239e78a3eb26971dac01b5f4ce14081a06529ab66cda8e8d5537808223fd00",
    Qy0 = "a784902a14ad39adcfdc52bc30d8b8711b93dd869af2375a1f408ba8610b5c558bbebfe9f8f9875954780f4b4262c0",
    Qy1 = "fb1c766957c89e4d67747549f650070983e6c19d0208b7e65478e4dd4f72fc54fca450d96329182e3f00d16ae0f3a"
  )
