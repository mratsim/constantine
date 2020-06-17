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
  ../constantine/elliptic/[ec_weierstrass_projective, ec_scalar_mul, ec_endomorphism_accel],
  # Test utilities
  ./support/ec_reference_scalar_mult

echo "\n------------------------------------------------------\n"

proc test(
       id: int,
       EC: typedesc[ECP_SWei_Proj],
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
    var exponentCanonical: array[(exponent.bits+7) div 8, byte]
    exponentCanonical.exportRawUint(exponent, bigEndian)

    var
      impl = P
      reference = P
      endo = P
      scratchSpace: array[1 shl 4, EC]

    impl.scalarMulGeneric(exponentCanonical, scratchSpace)
    reference.unsafe_ECmul_double_add(exponentCanonical)
    endo.scalarMulGLV(exponent)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    doAssert: bool(Q == endo)

suite "Scalar Multiplication G1: BN254 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bn254_snarks.sage
  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "22d3af0f3ee310df7fc1a2a204369ac13eb4a48d969a27fcd2861506b2dc0cd7",
    Py = "1c994169687886ccd28dd587c29c307fb3cab55d796d73a5be0bbf9aab69912e",
    scalar = "e08a292f940cfb361cc82bc24ca564f51453708c9745a9cf8707b11c84bc448",
    Qx = "267c05cd49d681c5857124876748365313b9c285e783206f48513ce06d3df931",
    Qy = "2fa00719ce37465dbe7037f723ed5df08c76b9a27a4dd80d86c0ee5157349b96"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2724750abe620fce759b6f18729e40f891a514160d477811a44b222372cc4ea3",
    Py = "105cdcbe363921790a56bf2696e73642447c60b814827ca4dba86c814912c98a",
    scalar = "2f5c2960850eabadab1e5595ff0bf841206885653e7f2024248b281a86744790",
    Qx = "57d2dcbc665fb93fd5119bb982c29700d025423d60a42b5fe17210fd5a868fd",
    Qy = "2abad564ff78fbc266dfb77bdd110b22271136b33ce5049fb3ca05107787abc"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "39bc19c41835082f86ca046b71875b051575072e4d6a4aeedac31eee34b07df",
    Py = "1fdbf42fc20421e1e775fd93ed1888d614f7e39067e7443f21b6a4817481c346",
    scalar = "29e140c33f706c0111443699b0b8396d8ead339a3d6f3c212b08749cf2a16f6b",
    Qx = "83895d1c7a2b15a5dfe9371983196591415182978e8ff0e83262e32d768c712",
    Qy = "2ed8b88e1cd08814ce1d1929d0e4bba6fb5897f915b3525cf12349256da95499"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "157a3e1ff9dabccced9746e19855a9438098be6d734f07d1c069aa1bd05b8d87",
    Py = "1c96bf3e48bc1a6635d93d4f1302a0eba39bd907c5d861f2a9d0c714ee60f04d",
    scalar = "29b05bd55963e262e0fa458c76297fb5be3ec1421fdb1354789f68fdce81dc2c",
    Qx = "196aeca74447934eeaba0f2263177fcb7eb239985814f8ef2d7bf08677108c9",
    Qy = "1f5aa4c7df4a9855113c63d8fd55c512c7e919b8ae0352e280bdb1009299c3b2"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2f260967d4cd5d15f98c0a0a9d5abaae0c70d3b8d83e1e884586cd6ece395fe7",
    Py = "2a102c7aebdfaa999d5a99984148ada142f72f5d4158c10368a2e13dded886f6",
    scalar = "1796de74c1edac90d102e7c33f3fad94304eaff4a67a018cae678774d377f6cd",
    Qx = "28c73e276807863ecf4ae60b1353790f10f176ca8c55b3db774e33c569ef39d5",
    Qy = "c386e24828cead255ec7657698559b23a26fc9bd5db70a1fe20b48ecfbd6db9"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "1b4ccef57f4411360a02b8228e4251896c9492ff93a69ba3720da0cd46a04e83",
    Py = "1fabcb215bd7c06ead2e6b0167497efc2cdd3dbacf69bcb0244142fd63c1e405",
    scalar = "116741cd19dac61c5e77877fc6fef40f363b164b501dfbdbc09e17ea51d6beb0",
    Qx = "192ca2e120b0f5296baf7cc47bfebbbc74748c8847bbdbe485bcb796de2622aa",
    Qy = "8bc6b1aa4532c727be8fd21a8176d55bc721c727af327f601f7a8dff655b0b9"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2807c88d6759280d6bd83a54d349a533d1a66dc32f72cab8114ab707f10e829b",
    Py = "dbf0d486aeed3d303880f324faa2605aa0219e35661bc88150470c7df1c0b61",
    scalar = "2a5976268563870739ced3e6efd8cf53887e8e4426803377095708509dd156ca",
    Qx = "2841f67de361436f64e582a134fe36ab7196334c758a07e732e1cf1ccb35a476",
    Qy = "21fb9b8311e53832044be5ff024f737aee474bc504c7c158fe760cc999da8612"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "2754a174a33a55f2a31573767e9bf5381b47dca1cbebc8b68dd4df58b3f1cc2",
    Py = "f222f59c8893ad87c581dacb3f8b6e7c20e7a13bc5fb6e24262a3436d663b1",
    scalar = "25d596bf6caf4565fbfd22d81f9cef40c8f89b1e5939f20caa1b28056e0e4f58",
    Qx = "2b48dd3ace8e403c2905f00cdf13814f0dbecb0c0465e6455fe390cc9730f5a",
    Qy = "fe65f0cd4ae0d2e459daa4163f32deed1250b5c384eb5aeb933162a41793d25"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "273bf6c679d8e880034590d16c007bbabc6c65ed870a263b5d1ce7375c18fd7",
    Py = "2904086cb9e33657999229b082558a74c19b2b619a0499afb2e21d804d8598ee",
    scalar = "67a499a389129f3902ba6140660c431a56811b53de01d043e924711bd341e53",
    Qx = "1d827e4569f17f068457ffc52f1c6ed7e2ec89b8b520efae48eff41827f79128",
    Qy = "be8c488bb9587bcb0faba916277974afe12511e54fbd749e27d3d7efd998713"
  )

  test(
    id = 10,
    EC = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Px = "ec892c09a5f1c68c1bfec7780a1ebd279739383f2698eeefbba745b3e717fd5",
    Py = "23d273a1b9750fe1d4ebd4b7c25f4a8d7d94f6662c436305cca8ff2cdbd3f736",
    scalar = "d2f09ceaa2638b7ac3d7d4aa9eff7a12e93dc85db0f9676e5f19fb86d6273e9",
    Qx = "305d7692b141962a4a92038adfacc0d2691e5589ed097a1c661cc48c84e2b64e",
    Qy = "bafa230a0f5cc2fa3cf07fa46312cb724fc944b097890fa60f2cf42a1be7963"
  )

proc test(
       id: int,
       EC: typedesc[ECP_SWei_Proj],
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
    var exponentCanonical: array[(exponent.bits+7) div 8, byte]
    exponentCanonical.exportRawUint(exponent, bigEndian)

    var
      impl = P
      reference = P
      endo = P
      scratchSpace: array[1 shl 4, EC]

    impl.scalarMulGeneric(exponentCanonical, scratchSpace)
    reference.unsafe_ECmul_double_add(exponentCanonical)
    # endo.scalarMulGLV(exponent) # TODO GLV+GLS on G2

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    # doAssert: bool(Q == endo)

suite "Scalar Multiplication G2: BN254 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bn254_snarks.sage
  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "d4ff42fc6d0febc88c9e1bc568d72c80c58438f6295dc598d798c1285f974ed",
    Px1 = "3845ad0148f76bdf14f752268eafb065c7272721784a8c6bd3a5fa736332b94",
    Py0 = "13fea1d73f8e06ea57a110f9156a8c876ba42251c7dcf9f203f90839bea3e462",
    Py1 = "1b722e9557c77e1a74a2ad7236b9b0194dbf80a5c03021ce55649e3082c0cbaf",
    scalar = "3075e23caee5579e5c96f1ca7b206862c2cf3ce21d79182d58b140074b7bd34",
    Qx0 = "1811e020b970e8c87c63acc020a27e99e97236f9dd01475ece959fb679c3e2d",
    Qx1 = "2e7c501387b25ab6fc9b45c8e0944d9685364f5c448b954f370ac80751a25de5",
    Qy0 = "8d73969c1c49878b450c829a7574d7df69fb0f44f158f1a84a8dda940453f30",
    Qy1 = "14eda105095dd606285a3b7a2aa9bd269b9193c22726d5a4d8708e02ae217807"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "c4bff378e0e78a9094bc8cb224ad7d89266c28d1289098f03226fa84e7905b0",
    Px1 = "208afbcdfa4243045ad02aea93f275c60e9f838d6a933e9ad5732235e93cec84",
    Py0 = "178fd343e358c869df8c3b2e2e90c68cb2352c1ce6a6e51516a2ccab5bc191e3",
    Py1 = "23d122142470d7a5b9a9b456dcd1898ab5130f2274e010a67c0b59d8a06c98a3",
    scalar = "1eac341ad699cba0cb13ae35b8215bfe0f34e931f8e51e33bf90d9849767bb",
    Qx0 = "7d2b09ccebc6ea3ab685a2938c3b594bd1e500eb2ab2a4e0337e7f6587026fb",
    Qx1 = "ac5a99b924aebdbe4ff277ff5c8e1a209059c646fcac221917fbcbf738039ca",
    Qy0 = "2be1aebafff712ffd677fe1ac78eb2e838fe3bfc0051afb4e1b446b9aecb5939",
    Qy1 = "16bf0803d6e1d68be0e3e10d25e358e1f89a28c211cdc61def5ef10ea3abec94"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "15dd63cf4d0c2d0e21368a72b93f72ed172c413782db489f5d7b4dfcdee061c7",
    Px1 = "26e5ca7f4b418fc9eb7d7b7f44ed1c4357fa71695ad59299d4404c55a295d64",
    Py0 = "df8c4bcbb5518b1ea51967f69f61b743be8e58bc9b597b398b51ca7820940af",
    Py1 = "8a36e75e7058969f4aef0724d9f6317b8b6028870f0e7412baece8073be3477",
    scalar = "b29535765163b5d5f2d01c8fcde010d11f3f0f250a2cc84b8bc13dd9083356c",
    Qx0 = "1c329c496b4cb95ee511277fd514a07fb98e313c61f256116d9c071ecc9d9a3a",
    Qx1 = "11d64f0b3301b18b969f58664801c0de67a295943034e5946b27065ac56581a0",
    Qy0 = "54787e9bdec726f06896ed90b12a346a2f92e44688b1663911931cd225a1cf3",
    Qy1 = "1303456cc596e033f1f32f2041bd83fabb8566744c0b4a358097270baa734a48"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "9a26b213edf4d6b8b8026e934436d2a99d5cc23a9153abdb101a9bc67ab0b74",
    Px1 = "1654d9658fb77c7836ef3b41431282834c348d922d424ec4205cc62599b1cff4",
    Py0 = "13359cc29af8ed4d2a8b3acdc2e1c257bb738a365b020075a0cf387fadc9ee96",
    Py1 = "16dd9e23d0e5a92a98c57eeb0438412185e602bfb87c464e088933fd418e83fb",
    scalar = "2c02275a71bb41c911faf48cab4f7ac7fc6672a5c15586185c8cff3203181da0",
    Qx0 = "263a3327dbcd1d29dc43c428f6f03638a146ae40e06974f2a2bdc97c2239adcc",
    Qx1 = "21d7f34d76f4b71b3e35138f219af27709c0337d1bcd3a680de34ad191a2ddab",
    Qy0 = "1b0f2d2d9be7fc91bec9dad3294159834e506cf0d24d319b8282bfde26aa4268",
    Qy1 = "1bceb12af58dd453e801b6036fad5cf63ee511b00c6b8c5cee7bb3846ef3eb05"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "1a4fb241cdcd2415acca073eaae81ea2e75fbe3122d91a113ee60d6a1f2a882c",
    Px1 = "1cfac3eb7f51ef5c90fe33469dd55b0641eaf4597cfde95f01fe8d0c16613599",
    Py0 = "112e05efd8fae9654a20c4a53cb31207176bb6ea7c5ed4c8464a9846e4c6bd56",
    Py1 = "2b9b15b98d8a2116ffea8886e9399fadf6998f89e2037c423d78c6145beaaed8",
    scalar = "24c5b2ce21615dca82231f5fb0fc8d05aa07c6df4bb5aa7c2381ac7b61a6290c",
    Qx0 = "27c16e9546b4383b7d7df55ccc33737866e1e9d12d4f5135bcdbc95514bc5b23",
    Qx1 = "2e451f8f8f5163dbbd1bf48dce686204511d8cea5bc504a4fcb13d76490589f2",
    Qy0 = "1c66b04bb04c139b5a6bd40a2a5b20706620b5b54aa69ffc9075dfe14fbbba70",
    Qy1 = "139f9a895e3e68e57a15b0d6cb01c4101317b4554e196f305f88212ce5cef640"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "249d33d9b24b0b9d72753345239bc59ae80557dfb0c86a1f86ec92e749c8722a",
    Px1 = "cfba4d7f339870b12f9f83eb31a791ae3333d1e984919f5a128f72377f70756",
    Py0 = "1cc869e4e50855a0c09d6da00687007702f5d8fd9c1b1abc17dc643d5dd40825",
    Py1 = "19a0e1f64ae604d4591905d73cbeae6e644ddda04628a035d941dd0f94e8a33",
    scalar = "263e44e282fe22216cc054a39e40d4e38e71780bdc84563c340bdaaf4562534b",
    Qx0 = "2534d84cba98b2aa589b912f5be6dca6f8bf5fc0538fb0a3bc126c109af36aa8",
    Qx1 = "13921f40b39312b5a62dd8c2b49f153c331c32fa1d1d5cf31e71e1111ffdc947",
    Qy0 = "2a61adb49770d50ccc0e84b3561746cd3672a292e4d8e2dc8cb0a48dfc678adc",
    Qy1 = "d2564831641fd45cd073146cc061b2811d1d1b56289887eeed4ce07827dd3cc"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "210e0d4ae81d5a5108ecc70c5ea0317455f6d5ae6853938a8fd832b055fb8d4d",
    Px1 = "d1a120ec549f63e2b67043d5c6a3b7a9a7682ebac87cfda91dcc696c425eee8",
    Py0 = "830c793ad790d61b9b0cbc83bc63869a1c6dc629e7d8c3bec7049ebe68fbad9",
    Py1 = "129a312b5e866a67ab15ba01fabbb533dd5a7fd5ba976cad0d0e44743d6efb15",
    scalar = "1471f378000d557f0c33c1f8c8313edd53422479440cbd0fdc4cc55f1163deec",
    Qx0 = "2c16f3ee75dcdad425ee694342de2ef1c4f07b29c1b5366173d93013ef426692",
    Qx1 = "3b7d1258cb99bb20857605d9cd5132c82189f98d78a267e80c583bf840c6eeb",
    Qy0 = "2afabef1030af27bc3ba6cc378b0f7dcb84a09cae301e580d9103daad28ba71f",
    Qy1 = "117a37aee6704e3fc36d0dba37822658350c48bde5a0968d9ecf45e346caff22"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "116f9cd5018206c9e0c20bfd684995d42941ba7d4eff87aec228d5fc593e8893",
    Px1 = "211a34b8228f4bc48f0849e2e721cdaeb416e5be421e942339b751c5edaed7e7",
    Py0 = "1a888b9355886760acab22c5f35de566d9f521e28cfde8ef5c6cd771b4c19716",
    Py1 = "4935e0ab136c85ede2a70c3a4a2429b10e1ee9b259d0ffc5ccd0cbcdcba1351",
    scalar = "411315458c0c0cb27a058faf15dcbf2e467128f9c958d92de37902e1912f81",
    Qx0 = "175bcd9b7ac109968b88118e93aac3e44446b8abb9e9a2d50eacc2475f245106",
    Qx1 = "295dd179211b165f3096be9c44248a525976d9f3757c56083a9f0f69cd9eb75",
    Qy0 = "f67730f5ced93a2a7dbcd57b073505b496a7eba5eb5b1f6170cfea145ce2f15",
    Qy1 = "903a6681d15626728d7e36af65fe5d96ae314433de84321410579cba5e5dbec"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "16181913b3c03bd61b7e3ba2e05541b492626046533440bced33420cb1d0cfc2",
    Px1 = "3d505402f6d6eab342473ed2b07313c5b02e2c63f2218e5773df0aa839ce9ba",
    Py0 = "8b40ff9ba82fbf42f02628600894d112640223759570e87bb721a93da0c2c22",
    Py1 = "2d8df108c6cb25384b748480f99b9c3e72c256839e227fb22eadc4148e6398eb",
    scalar = "111e6f761ce48e22970752bd56cab93d47caa252d52948367b21163591f7b7b1",
    Qx0 = "2a8ea2288308fd73ffa423dbe971e45e4cbadfc977d75cd4ea015adf80f25bac",
    Qx1 = "491f281ad2faf5b41cb5da93b114310222c6356469b7fb51a8166e8ccc4ab01",
    Qy0 = "386ae4175f00ba59c45b07f1f47fbeb0359e8fa52f70cc7396d58f2ef06abd9",
    Qy1 = "525877a41155f9dbd541f5833b0d1543a07089cb4a1842990d01dbb3068e8db"
  )

  test(
    id = 10,
    EC = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    Px0 = "1ea8eb841a242b478d5ed96da30eb78ac5588964dd0f3405b419747d44795ae8",
    Px1 = "ee64b54258e687fc9887ca2362b71c50539c881d43097a0578b58c487fd26ca",
    Py0 = "2ab3b56d071b0ca9934fc031e26dd0ef777b42018e9afa632ba5af8fec4ddeb8",
    Py1 = "cdf8de134912bb9e9b1e9deec26066028ef099def9c4f3e157cec48f5919295",
    scalar = "6223903d4bc2adea7b0a0db92822b6c2638691e4388df93f567e11edd6f23",
    Qx0 = "1f30a3adabf28b22f0ca4088fb9cd48688c7c360098d33d0a93800d5b22433db",
    Qx1 = "e436556e8cf709b4cceb314bf387326f824afdfdc13638dcd5212822543fb1d",
    Qy0 = "28329f3dff9158be7d166e6063ee6964f2d04810a46ef1e05732fa377b6302b4",
    Qy1 = "dea3c3263a5914c54be5abcbf9d1aad995dac6a82b88ff46f0a314e8a0c2925"
  )
