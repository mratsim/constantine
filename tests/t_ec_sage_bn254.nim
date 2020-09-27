# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/unittest,
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

suite "Scalar Multiplication G1: BN254 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bn254_snarks.sage
  test(
    id = 0,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "22d3af0f3ee310df7fc1a2a204369ac13eb4a48d969a27fcd2861506b2dc0cd7",
    Py = "1c994169687886ccd28dd587c29c307fb3cab55d796d73a5be0bbf9aab69912e",
    scalar = "e08a292f940cfb361cc82bc24ca564f51453708c9745a9cf8707b11c84bc448",
    Qx = "267c05cd49d681c5857124876748365313b9c285e783206f48513ce06d3df931",
    Qy = "2fa00719ce37465dbe7037f723ed5df08c76b9a27a4dd80d86c0ee5157349b96"
  )

  test(
    id = 1,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "2724750abe620fce759b6f18729e40f891a514160d477811a44b222372cc4ea3",
    Py = "105cdcbe363921790a56bf2696e73642447c60b814827ca4dba86c814912c98a",
    scalar = "2f5c2960850eabadab1e5595ff0bf841206885653e7f2024248b281a86744790",
    Qx = "57d2dcbc665fb93fd5119bb982c29700d025423d60a42b5fe17210fd5a868fd",
    Qy = "2abad564ff78fbc266dfb77bdd110b22271136b33ce5049fb3ca05107787abc"
  )

  test(
    id = 2,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "39bc19c41835082f86ca046b71875b051575072e4d6a4aeedac31eee34b07df",
    Py = "1fdbf42fc20421e1e775fd93ed1888d614f7e39067e7443f21b6a4817481c346",
    scalar = "29e140c33f706c0111443699b0b8396d8ead339a3d6f3c212b08749cf2a16f6b",
    Qx = "83895d1c7a2b15a5dfe9371983196591415182978e8ff0e83262e32d768c712",
    Qy = "2ed8b88e1cd08814ce1d1929d0e4bba6fb5897f915b3525cf12349256da95499"
  )

  test(
    id = 3,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "157a3e1ff9dabccced9746e19855a9438098be6d734f07d1c069aa1bd05b8d87",
    Py = "1c96bf3e48bc1a6635d93d4f1302a0eba39bd907c5d861f2a9d0c714ee60f04d",
    scalar = "29b05bd55963e262e0fa458c76297fb5be3ec1421fdb1354789f68fdce81dc2c",
    Qx = "196aeca74447934eeaba0f2263177fcb7eb239985814f8ef2d7bf08677108c9",
    Qy = "1f5aa4c7df4a9855113c63d8fd55c512c7e919b8ae0352e280bdb1009299c3b2"
  )

  test(
    id = 4,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "2f260967d4cd5d15f98c0a0a9d5abaae0c70d3b8d83e1e884586cd6ece395fe7",
    Py = "2a102c7aebdfaa999d5a99984148ada142f72f5d4158c10368a2e13dded886f6",
    scalar = "1796de74c1edac90d102e7c33f3fad94304eaff4a67a018cae678774d377f6cd",
    Qx = "28c73e276807863ecf4ae60b1353790f10f176ca8c55b3db774e33c569ef39d5",
    Qy = "c386e24828cead255ec7657698559b23a26fc9bd5db70a1fe20b48ecfbd6db9"
  )

  test(
    id = 5,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "1b4ccef57f4411360a02b8228e4251896c9492ff93a69ba3720da0cd46a04e83",
    Py = "1fabcb215bd7c06ead2e6b0167497efc2cdd3dbacf69bcb0244142fd63c1e405",
    scalar = "116741cd19dac61c5e77877fc6fef40f363b164b501dfbdbc09e17ea51d6beb0",
    Qx = "192ca2e120b0f5296baf7cc47bfebbbc74748c8847bbdbe485bcb796de2622aa",
    Qy = "8bc6b1aa4532c727be8fd21a8176d55bc721c727af327f601f7a8dff655b0b9"
  )

  test(
    id = 6,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "2807c88d6759280d6bd83a54d349a533d1a66dc32f72cab8114ab707f10e829b",
    Py = "dbf0d486aeed3d303880f324faa2605aa0219e35661bc88150470c7df1c0b61",
    scalar = "2a5976268563870739ced3e6efd8cf53887e8e4426803377095708509dd156ca",
    Qx = "2841f67de361436f64e582a134fe36ab7196334c758a07e732e1cf1ccb35a476",
    Qy = "21fb9b8311e53832044be5ff024f737aee474bc504c7c158fe760cc999da8612"
  )

  test(
    id = 7,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "2754a174a33a55f2a31573767e9bf5381b47dca1cbebc8b68dd4df58b3f1cc2",
    Py = "f222f59c8893ad87c581dacb3f8b6e7c20e7a13bc5fb6e24262a3436d663b1",
    scalar = "25d596bf6caf4565fbfd22d81f9cef40c8f89b1e5939f20caa1b28056e0e4f58",
    Qx = "2b48dd3ace8e403c2905f00cdf13814f0dbecb0c0465e6455fe390cc9730f5a",
    Qy = "fe65f0cd4ae0d2e459daa4163f32deed1250b5c384eb5aeb933162a41793d25"
  )

  test(
    id = 8,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "273bf6c679d8e880034590d16c007bbabc6c65ed870a263b5d1ce7375c18fd7",
    Py = "2904086cb9e33657999229b082558a74c19b2b619a0499afb2e21d804d8598ee",
    scalar = "67a499a389129f3902ba6140660c431a56811b53de01d043e924711bd341e53",
    Qx = "1d827e4569f17f068457ffc52f1c6ed7e2ec89b8b520efae48eff41827f79128",
    Qy = "be8c488bb9587bcb0faba916277974afe12511e54fbd749e27d3d7efd998713"
  )

  test(
    id = 9,
    EC = ECP_ShortW_Proj[Fp[BN254_Snarks]],
    Px = "ec892c09a5f1c68c1bfec7780a1ebd279739383f2698eeefbba745b3e717fd5",
    Py = "23d273a1b9750fe1d4ebd4b7c25f4a8d7d94f6662c436305cca8ff2cdbd3f736",
    scalar = "d2f09ceaa2638b7ac3d7d4aa9eff7a12e93dc85db0f9676e5f19fb86d6273e9",
    Qx = "305d7692b141962a4a92038adfacc0d2691e5589ed097a1c661cc48c84e2b64e",
    Qy = "bafa230a0f5cc2fa3cf07fa46312cb724fc944b097890fa60f2cf42a1be7963"
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
    var exponentCanonical: array[(exponent.bits+7) div 8, byte]
    exponentCanonical.exportRawUint(exponent, bigEndian)

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

suite "Scalar Multiplication G2: BN254 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bn254_snarks.sage
  test(
    id = 0,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "1dcee2242ae85da43d02d38032b85836660f9a0a8777ab66c84ffbbde3ac3b25",
    Px1 = "1e2eb4c305e3b6c36a4081888b7a953eb44804b8b5120306331f8c89a3bb950",
    Py0 = "1db75f495edd522cae161ceeb86ca466ca2efd80ef979028d7aa39679de675fd",
    Py1 = "b1b6edeb6a7689595098a58a916657dcc09f53f5fc1a1a64b34a2b80447692e",
    scalar = "3075e23caee5579e5c96f1ca7b206862c2cf3ce21d79182d58b140074b7bd34",
    Qx0 = "8d63bb4368f94f1629f33ef0c970b3a6fcec6979e423f54ce657f0493c08fde",
    Qx1 = "29d1af77bb890dcb27e685198f23dffd5ae5733bd6dd55757dcb44ce8c396742",
    Qy0 = "13c24efab7e517c2337ba9cbb8cfb2166666a44550fc4d314f4c81a4812fb8a",
    Qy1 = "c3ad1f7a175fa21e1d18595f8fc793688e1a33feda902805a52569ea7a787bb"
  )

  test(
    id = 1,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "5ed8c937273562944e0f1ebfb40e6511202188c1cabf588ed38735016d37b32",
    Px1 = "23f75e8322c4b540cd5b8fd144a89ab5206a040f498b7b59385770bc841cf012",
    Py0 = "2150beef17f5c22a65a4129390f47eece8f0c7d0c516790ea2632e7fd594ed8",
    Py1 = "78281fb396e2b923453fae943af96b57e8b283fc40b0be4be3a1750d0daf121",
    scalar = "1eac341ad699cba0cb13ae35b8215bfe0f34e931f8e51e33bf90d9849767bb",
    Qx0 = "1bb6e8c1be4d9da9ef294ab066c82bb6dd805efa0c73f289e25f5cc6fc4f12e4",
    Qx1 = "8ca44ff91e6484ecadc2a866ec64031e71c4a9d7a902f4280bef3db4dbf1bc9",
    Qy0 = "39d151a22c49d4c71c8258e9664ead46ddccd49c596056509d9f9e6055def62",
    Qy1 = "b37a08b453b96880f435d9fb2555960571a76e72a9d0d0ec622b055b7c97cdb"
  )

  test(
    id = 2,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "2ac4b3d0a70d6686c63d9d63cce1370eafd4dc67f616c13582c6c64f6670513e",
    Px1 = "f1daeb6a2581ba6c8027a645ab5c10e303db4aee85c70c8fe11f4c1adcc7029",
    Py0 = "25807ff21967759cab64844741d006e2aa0221d9836613b1239da1a167d15131",
    Py1 = "148dae725e508dbb43616972e2945f4868b2a193d828ed2efcf9c8a37b6b83f5",
    scalar = "b29535765163b5d5f2d01c8fcde010d11f3f0f250a2cc84b8bc13dd9083356c",
    Qx0 = "5f4b3a8a5fe74bf3f2ddc0bc2024f18c7958b2846dab1c602b8256a6035361a",
    Qx1 = "ba3dad609b1ba8c78cbbfb7fae2d2f9398ef02265e3b4c0f3c8c18d8d0e59d6",
    Qy0 = "2c226aee4621895d63df069c4b6951e2201ee1508d5d54e6ee860533b73b534a",
    Qy1 = "2aa5384592339bff0a6e4664c931c0ec9f5a3d2fb2fff87a52245c0d95d3d130"
  )

  test(
    id = 3,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "2a028c1328bb0abf252edfbf7133b84eef2a5f20163fe61685b4b54229ca585d",
    Px1 = "8f80ad79e8e7e79bbdc645d9f5b339c52dd99a901b90de2494492656f11a9d5",
    Py0 = "1f04320578e31ffa2e2b59ad8fcb1aba622b5f307ac540cf2ccdab07dec56503",
    Py1 = "2973900c0fdf651b64f5b1a990baec7c582e0743d501bdb991374776d6c73b28",
    scalar = "2c02275a71bb41c911faf48cab4f7ac7fc6672a5c15586185c8cff3203181da0",
    Qx0 = "2f39a0772a0bd75db3e6ec0745b18824118e534fdefec811d0a4ca2ca3ce7606",
    Qx1 = "23e1601a4338502dbc619a8bde251114272ca87662a851a56035c81d46877d81",
    Qy0 = "1f0ee85e7c590124f89319f2450f7b8421d9f6d6414fd3b5cc18d781b69b30c9",
    Qy1 = "29e4ff75afecaf732419409a5e0d8e94df6acec29fb5b298c7aad5ceef63e5f9"
  )

  test(
    id = 4,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "1132e63c444e1abce6fc4c39bdf5be5caad586837cbf5ca9d3891482bdefe77",
    Px1 = "22b71f598dab789f055fc9669ddf66f0d75f581af0e9e8863d7f95a51ef34862",
    Py0 = "58e39050f64c9948d7238b99ecaee947cb934688a6e9f483c5c36b6e07aa31b",
    Py1 = "2e64b920f498e12992f2a4ae3f9ced43f3f64705c9008169f3b930a760d055fb",
    scalar = "24c5b2ce21615dca82231f5fb0fc8d05aa07c6df4bb5aa7c2381ac7b61a6290c",
    Qx0 = "25a0637163a40813529e8a22a3e8be6db96f6dc1cdb8e1844729cad6be11668e",
    Qx1 = "16de42461c4db7f9f72eb28bb16da850a42fc153dec64baf021f67f5564f36d8",
    Qy0 = "27f2d743d3ce0c1f92c51110a6b9ca93a95693161f1d1cd85a0cf5a2492b4901",
    Qy1 = "2c5a8df4fe93e31e374595c0605b1a8b93bb429232cf40f45c847739790c191e"
  )

  test(
    id = 5,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "6a20c456e80e2bfe37d8631d41ffed31cba5d1c411e816d64014d0088d16554",
    Px1 = "9d1555c77222abd79e17e2806386c53aba9609375276e817f52f03dc3f75676",
    Py0 = "127e76f384726e56dfaa46e6fde6dc644f5fd494d056191059e2bebc525ce835",
    Py1 = "2d80f2570da62adc61d794ac17c251f9f9f3de2b45f39c8ede5a9e215e60363",
    scalar = "263e44e282fe22216cc054a39e40d4e38e71780bdc84563c340bdaaf4562534b",
    Qx0 = "6d7e15b98352e445d1bdacb48826e5a7e8cf854fb9bc18839b30a164a2a9c53",
    Qx1 = "12aa3294f6a9bb17f91d5875a5a1aa559c29b06134c6d165d83c8e9e02947568",
    Qy0 = "271b8b552e52bdd310c46e07327a18861c91a739da178be909f0a4fe53ae0d05",
    Qy1 = "1f4f200de96541e826f0bd536b1401e05e2a7c5a96c567b6dff21a21119bbf7"
  )

  test(
    id = 6,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "4c591d080257375d6189340185c6fe4c1fa796722d07e1bec0b17080b6b1154",
    Px1 = "241e2f2eb2a58afc2b5410d4ccbf75b53744ca1ac0bb28d7c60449f8d06204a4",
    Py0 = "eaddea52f2e884a5e2635965ca4146b12127fe8a8883e07def8e8720f410781",
    Py1 = "cc60dec6ad90e38c851924cf39ddd11b70eeb3fac95731eafd984e9aba2cae",
    scalar = "1471f378000d557f0c33c1f8c8313edd53422479440cbd0fdc4cc55f1163deec",
    Qx0 = "2a86b4867d7f63afdc09048210a3ef6d363c7896ccc1bb248f3aad4174e1f8fa",
    Qx1 = "84c200018461c84ef9ce6de2c691b95cc2c41edc87107331f107ac49de76656",
    Qy0 = "2ea1b6d71adb183d9a8dd319a21a679cb0b4e06bc96583d3a786f82b88b5e3ba",
    Qy1 = "834e2ff738dcb5e8db7e4dae9336dede51524313b476019ea29ebadbb4ba12d"
  )

  test(
    id = 7,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "115e772198e3f0003e31c0a1c48b6ac870d96020a4d634b7f14c15422d001cfe",
    Px1 = "1913447ff41836e0b6a3b01be670a2457e6119e02ae35903fb71be4369e269f7",
    Py0 = "14cb779c640aad2731b93b07c623c621a5585d0374f0394e5332f20ac28ca49d",
    Py1 = "13a4c4b67f5976431158be8137b5017127fdbc312dc49825dae218a9a7878817",
    scalar = "411315458c0c0cb27a058faf15dcbf2e467128f9c958d92de37902e1912f81",
    Qx0 = "243a8808a891428d01ef28a77d0766488a98272a5dd394b2992599ff522f264",
    Qx1 = "1baebf873402812e4345a8b1783fd25272c64d6194bd9f50b32b8e67ee737dc7",
    Qy0 = "1f1001ba8b8b27159568f72e80662e352adfc00c9341d8b4fb8ef6f75ff628d2",
    Qy1 = "169af215aa2456c6a65e13ac4df1ba1c982ca791058612679ef26dcb8fb0a989"
  )

  test(
    id = 8,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "13faa1f28e6bfe89765c284e67face6ce0a29006ebc1551d4243e754c59f88ad",
    Px1 = "640cebb80938dfcb998d84a8e5aafd47ffbcba0aa2f8c9b1c585baf119a8942",
    Py0 = "1de793a9ef8f4dea5dad12fb09ddefa07ce197d4d7389a29ad3d8c6484582afe",
    Py1 = "fc6e1f8bf75d1b7e48fdb6b2869c2de553663742c151b390cede6712da5a084",
    scalar = "111e6f761ce48e22970752bd56cab93d47caa252d52948367b21163591f7b7b1",
    Qx0 = "1c25702bf3b6f5fb453c6473b6dc2d67cd3cc21c65b589df1bfde254d50cffdd",
    Qx1 = "14d03eb2075d6b5995240cc54a01ebe50b43933863f0316760226fbfa3a0280",
    Qy0 = "1a075c9f2f6afa6e07e54b143a33c17e81d0ac8b91e0c8e0fdd5082bd6b9a72d",
    Qy1 = "8e5ef57bb0f95fb6538dfaeac677977e3f3d6f49142c09584d8ec5c2ccd9b2d"
  )

  test(
    id = 9,
    EC = ECP_ShortW_Proj[Fp2[BN254_Snarks]],
    Px0 = "2fc3da947b78ac524a57670cef36ca89f1dad71b337bc3c18305c582a59648ad",
    Px1 = "2f7cc845d8c1ef0613f919d8c47f3c62f83608a45b1e186748ac5dcccd4c6baf",
    Py0 = "18ddc4718a4161f72f8d188fc61a609a3d592e186a65f4158483b719ffb05b8f",
    Py1 = "45b9c3629ed709784db63ff090e2e891c5b5c6b2222cb6afc56638d7389d689",
    scalar = "6223903d4bc2adea7b0a0db92822b6c2638691e4388df93f567e11edd6f23",
    Qx0 = "9ec612ab0cf4a48e1c15d22284bce8e34619bfb9afb688a9a7930afcc1bd0f3",
    Qx1 = "d796e5f5ae1a15622d2284ada34166b9e7c717bd2ff9b2cf2c6e48c33db5ff2",
    Qy0 = "2a8ecb09a01cd2f89b316e7569331e9da3bfbd8a40114913b3e5477442c0e4ef",
    Qy1 = "282b14bc00df2dd1733e3187a9845ef3a123c17ce4f6154e5cad26c3b48d1b98"
  )
