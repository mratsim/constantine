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
      endoW = P
      scratchSpace: array[1 shl 4, EC]

    impl.scalarMulGeneric(exponentCanonical, scratchSpace)
    reference.unsafe_ECmul_double_add(exponentCanonical)
    endo.scalarMulEndo(exponent)
    endoW.scalarMulGLV_m2w2(exponent)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    doAssert: bool(Q == endo)
    doAssert: bool(Q == endoW)

suite "Scalar Multiplication (cofactor cleared): BLS12_381 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bls12_381.sage
  test(
    id = 0,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "f9679bb02ee7f352fff6a6467a5e563ec8dd38c86a48abd9e8f7f241f1cdd29d54bc3ddea3a33b62e0d7ce22f3d244a",
    Py = "50189b992cf856846b30e52205ff9ef72dc081e9680726586231cbc29a81a162120082585f401e00382d5c86fb1083f",
    scalar = "f7e60a832eb77ac47374bc93251360d6c81c21add62767ff816caf11a20d8db",
    Qx = "c344f3bcc86df380186311fa502b7943a436a629380f8ee1960515522eedc58fe67ddd47615487668bcf12842c524d8",
    Qy = "189e0c154f2631ad26e24ca73d84fb60a21d385fe205df04cf9f2f6fc0c3aa72afe9fbea71a930fa71d9bbfddb2fa571"
  )

  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "17d71835ff84f150fabf5c77ac90bf7f6249143abd1f5d8a46a76f243d424d82e1e258fc7983ba8af97a2462adebe090",
    Py = "d3e108ee1332067cbe4f4193eae10381acb69f493b40e53d9dee59506b49c6564c9056494a7f987982eb4069512c1c6",
    scalar = "5f10367bdae7aa872d90b5ac209321ce5a15181ce22848d032a8d452055cbfd0",
    Qx = "21073bee733a07b15d83afcd4e6ee11b01e6137fd5ad4589c5045e12d79a9a9490a3ebc59f30633a60fc3635a3c1e51",
    Qy = "eb7a97a9d3dfff1667b8fa559bdcdf37c7767e6afb8ca93ad9dd44feb93761e10aa2c4c1a79728a21cd4a6f705398b5"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "f92c9572692e8f3d450483a7a9bb4694e3b54c9cd09441a4dd7f579b0a6984e47f8090c31c172b33d87f3de186d6b58",
    Py = "286ede4cb2ae19ead4932d5550c5d3ec8ce3a3ada5e1ed6d202e93dd1b16d3513f0f9b62adc6323f18e272a426ee955",
    scalar = "4c321d72220c098fc0fd52306de98f8be9446bf854cf1e4d8dbae62375d18faf",
    Qx = "4bb385e937582ae32aa7ba89632fcef2eace3f7b57309d979cf35298a430de9ef4d9ac5ba2335c1a4b6e7e5c38d0036",
    Qy = "1801154d3a7b0daea772345b7f72a4c88c9677743f267da63490dad4dece2ecc9ec02d4d4d063086ee5d356aa2db914e"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "ec23ff3435b8ebd5e8e0a879d432e11eb974161664b1341fd28f1ffc4c228bf6ada2ae4a565f18c9b66f67a7573502d",
    Py = "10c4b647be08db0b49b75320ae891f9f9c5d7bb7c798947e800d681d205d1b24b12e4dfa993d1bd16851b00356627cc1",
    scalar = "1738857afb76c55f615c2a20b44ca90dcb3267d804ec23fddea431dbee4eb37f",
    Qx = "dc7ae7801152918ee3c13590407b4242a80d0b855a0bf585d3dc30719601d2d5d9e01e99ae735003ecb7c20ef48265",
    Qy = "142c01a6aa390426a4ce2f36df43f86442732c35d4e05e5b67f3623832944f0ea5a29138624cb939330652a3cfb282b5"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "df127083c2a5ef2388b02af913c0e4002a52a82db9e5ecbf23ee4f557d3b61c91ebcfe9d4973070b46bc5ea6897bca1",
    Py = "318960aeea262ec23ffdd42ec1ba72ae6fa2186a1e2a0fc2659073fb7b5adfb50d581a4d998a94d1accf78b1b3a0163",
    scalar = "19c47811813444020c999a2b263940b5054cf45bb8ad8e086ff126bfcd5507e1",
    Qx = "5f93c42fd76a29063efa2ee92607e0b3ae7edc4e419b3914661e5162d6beaeb96a34d2007ff817bc102651f61dca8d1",
    Qy = "18dde8666bb1d0a379719d7d1b1512de809b70e49d9553303274ea872e56f7f39da551d6bcb7c57ae88ec7dc1fb354a4"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "101123de23c0f240c583c2368c4118dc942db219c55f58cf54acd500c1fcfa06f651ad75319ebf840cbdb6bddea7fde4",
    Py = "5268587d4b844b0708e0336d1bbf48da185aaf5b948eccc3b565d00a856dd55882b9bb31c52af0e275b168cb35eb7b0",
    scalar = "43ffcda71e45a3e90b7502d92b30a0b06c54c95a91aa21e0438677b1c2714ecb",
    Qx = "f9871b682c1c76c7f4f0a7ca57ad876c10dc108b65b76987264873278d9f54db95101c173aed06d07062efc7d47ca0c",
    Qy = "20d9628d611e72a4251a1f2357d4f53e68e4915383b6a0d126273d216b1a8c5e2cb7b2688ad702ef1682f4c5228fcd9"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "1457ba1bae6eb3afae3261941c65c93e3ae7d784907d15b8d559100da5e13fd29e4a4d6e3103b781a95237b7b2d80a8e",
    Py = "6a869a47cb48d01e7d29660932afd7617720262b55de5f430b8aa3d74f9fd2b9d3a07ce192425da58014764fc9532cd",
    scalar = "64ad0d6c36dba5368e71f0010aebf860288f54611e5aaf18082bae7a404ebfd8",
    Qx = "93e540e26190e161038d985d40f2ab897cbc2346be7d8f2b201a689b59d4020a8740e252606f2f79ba0e121ccc9976d",
    Qy = "10568d68f1b993aa1eded3869eda14e509f1cb4d8553bdf97feee175467cea4c0c1316fdb4e5a68440ad04b96b2d3bfc"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "2615f843e8fe68d4c337bcf83b2cf13cbae638edd0740f1eac520dc2146afa3b8d36c540878c1d207ef913634b1e593",
    Py = "1787d6eeeceb6e7793073f0bbe7bae522529c126b650c43d5d41e732c581a57df1bfb818061b7b4e6c9145da5df2c43e",
    scalar = "b0ac3d0e685583075aa46c03a00859dfbec24ccb36e2cae3806d82275adcc03",
    Qx = "d95ed29c2e15fd2205d83a71478341d6022deb93af4d49f704437678a72ce141d2f6043aa0e34e26f60d17e16b97053",
    Qy = "b37cbded112c84116b74ff311b10d148f3e203cb88d4a011b096c74cd2bfdb27255727de4aa8299ae10b32d661d48a7"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "10bc0c4e1ed87246a9d4d7d38546369f275a245f6e1d3b882e8c9a7f05bc6ee8ff97a96a54084c2bef15ed8bfefb1465",
    Py = "1782377e5f588576b5ab42fea224e88873dda957202f0c6d72ce8728c2d58dc654be77226fbda385d5f269354e4a176a",
    scalar = "23941bb3c3659423d6fdafb7cff52e0e02de0ac91e64c537c6203d64905b63d0",
    Qx = "83f1e7e8bd963c1ccd837dae7bc9336531aaf0aee717537a9a7e2712e220f74cdb73a99f331c0eb6b377be3dafc211f",
    Qy = "cd87773d072b1305dfc85c2983aecae2ab316e5e8f31306c32d58d6ce2e431b12685d18c58b6a35ad2113c5b689eeb"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp[BLS12_381]],
    Px = "be4f9f721d98a761a5562bd80ea06f369e9cbb7d33bbb2f0191d4b77d0fd2a10c4083b54157b525f36c522ca3a6ca09",
    Py = "166c315ecdd20acb3c5efcc7e038b17d0b37a06ffbf77873f15fc0cd091a1e4102a8b8bf5507919453759e744391b04d",
    scalar = "4203156dcf70582ea8cbd0388104f47fd5a18ae336b2fed8458e1e4e74d7baf5",
    Qx = "c72bc7087cd22993b7f6d2e49026abfde678a384073ed373b95df722b1ab658eb5ae42211e5528af606e38b59511bc6",
    Qy = "96d80593b42fe44e64793e490b1257af0aa26b36773aac93c3686fdb14975917cf60a1a19e32623218d0722dbb88a85"
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
    endo.scalarMulEndo(exponent)

    doAssert: bool(Q == reference)
    doAssert: bool(Q == impl)
    doAssert: bool(Q == endo)

suite "Scalar Multiplication G2: BLS12-381 implementation vs SageMath" & " [" & $WordBitwidth & "-bit mode]":
  # Generated via sage sage/testgen_bls12_381.sage
  test(
    id = 0,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "10fbddd49246ac4b0faa489e3474507ebc96a5da194b2f7a706fad6bf8435021e1598700088abfe0ae7343296c1b7f52",
    Px1 = "324102fa5bd71d9048c3c6a6c62d1f35195d7067bf00dc5eaedd14eecc688383446aba4e8fda059d3f619f00be7890",
    Py0 = "f3e974aafa7a3fb3a1209f3af4492c9d9c52f1ae738e1e08309dd0f438f131f8ddd8b934eb8ff2cb078b8c524c11fab",
    Py1 = "15e75704edffe7b975cf1d3f27f1dceb89d02e5660650195e0288e5d26c5e9087c241d1bd3263c991d10e2695d1611f1",
    scalar = "1f7bef2a74f3bf8ac0225a9edfa514bb5666b15e7be3e929059f2ef75f0035a6",
    Qx0 = "1328e4ac12458f9e0c22e925d2fc5593eaf0c126154b484de986895030f830262f54493edcc26aa39c5ab8e714b784b3",
    Qx1 = "14d375c704f9187984fe2d64d5517ce7c6eb09981cee68cd48370df21d7f4d0b19431347be3b9eae9d46605cb229e293",
    Qy0 = "1580cb4fceea4e71e222945825d4352c97a02d3118ffbd0e006e467b1ff6d4207acd2bb58a197894e9870cbd1bfb369c",
    Qy1 = "5df16d4223c040dffcd1912359cfae1f3a99e7f519b2aedaaeb6d77115c63acf309f9effc69d4d9a0d7de420dbf9f1a"
  )

  test(
    id = 1,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "4b472ab5d0995a22c95f0805eb459b147d2033b8c13c1c07c857a97e66952d4df3e3b5f346997cc7bd19886492fae83",
    Px1 = "12228345592511c7327176258097c70dffad1ff53b37163cbd4747d0085ed0bcfe90b9150d2f7e49580a42110b1d9c6b",
    Py0 = "19220ed4e423d3274a8e9a58624b8762d7831d6f65fcaf6718b933bf77a0c41d3bb713a2224dbc448cfc735101a5bb1e",
    Py1 = "1d4c7565e4831130ae0ddd95aaad4033e57daab2518b3f0d934c7abc7db8614adbf39beaef5ebb85d34f5add8a6d341",
    scalar = "b500f1fa8ffa8d1c0aa7d65054a9aaa0d9ed2fff83b40516def10b03cc80026",
    Qx0 = "aaf3fc4e3c92df5b76863d64d19d26213757173c1a8ef4beddbee7c22f5a6a00418527f83c9ab5b17797cd2212d3d73",
    Qx1 = "1643ce8e3a0f0997e949c04cb28aa77b7184033dd0056caee2488311e0a3567a0cd9d051ee531d6a83be8ac516c3f075",
    Qy0 = "12923eb157d8ee0a940e100408250beded20e4185cbec484431f705ab605c452122c66d6f08e1b06305677dc872a024f",
    Qy1 = "460b65406a6e3935dfd75977b12c02971d2673b9c23b032494e6684e08727f35da0407be6708e98cd309ff0c09be00d"
  )

  test(
    id = 2,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "11c9f03cd130f7b4d6675b902d9b4dddfa41577b7673c31a508760675ca083abedfe3f6c1c69eb46737d4877adb527c6",
    Px1 = "c64be8d22d478378784c4f38e386635a8ab606d2b35101ebecfe97b3bb5132d26e9a7ea9690d07a78a22f458045a8c5",
    Py0 = "6253c05b48fde95024644efd87cdf0cf15414c36c35625e383ea7b5ab839eaa783563918cd9e5e391ef1512a6ac28e0",
    Py1 = "2d214172d2a0326ed45b60945c424ac30f416fa8c6e11f243034a9de26f4aaa69c0d4cc8405227f26c6ee4085ea5bd4",
    scalar = "3638a1f09b542c9c14706bddf9bd411747489f3d398a5c286d28f3a950e33406",
    Qx0 = "a6e22837968f191d848297f60b511acf4cc375e53161e7869b8d98455375d8ee69367513b3439b6c4ee66f9232badbb",
    Qx1 = "10f95cc0c70943519c30c04a8625bb56c1656da634018b1e6e35786b610785f41978983c61e78d4be003074d7fd76660",
    Qy0 = "bae732b1dd39cb84c7e0649ed641f9d275bfc45721e3ac35d6cd35faa356235ce0b69fa0f2882d6d2762ed8846368d6",
    Qy1 = "bcab3bee59706e0f8c381d2a15a55ce6b2c38d1639b43852af2a62f1366d1cdb8433240cbb237750f2f3e0435b23141"
  )

  test(
    id = 3,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "5adc112fb04bf4ca642d5a7d7343ccd6b93546442d2fff5b9d32c15e456d54884cba49dd7f94ce4ddaad4018e55d0f2",
    Px1 = "5d1c5bbf5d7a833dc76ba206bfa99c281fc37941be050e18f8c6d267b2376b3634d8ad6eb951e52a6d096315abd17d6",
    Py0 = "15a959e54981fab9ac3c6f5bfd6fb60a50a916bd43d96a09922a54309b84812736581bfa728670cba864b08b9e391bb9",
    Py1 = "f5d6d74f1dd3d9c07451340b8f6990fe93a28fe5e176564eb920bf17eb02df8b6f1e626eda5542ff415f89d51943001",
    scalar = "6448f296d9b1a8d81319a0b789df04c587c6165776ccf39f50a354204aabe0da",
    Qx0 = "689e9532c287233d12c3d7196361a06479ecb762a8542f6ba4003a5863d5731f3a0cd3fe4e1405aa3c6f9bd87c08b26",
    Qx1 = "b74b46e87a05b7413282d63d63a2b1eeb23e8c482fa8097623888d4be2b90c7cdb49fcb93c74f2b98da15aa9382e285",
    Qy0 = "44250df4c1e38bfd7fef6c61649afe7ab5d5252b98589d71f1a64efac5ae8ecf0ccafa173acaafc30a0b2a1616b08e4",
    Qy1 = "173b324bb2e0596d0ab560c2a447a1867fea87c5712bd06f2503385b0e145509036c119440973396fc263a02838c8433"
  )

  test(
    id = 4,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "99f8b62e82892d323847f64ab2b422478d207b780fbb097cdca6a1a89e70ff09213dee8534eaf63dac9f7f7feff2548",
    Px1 = "12e7b53d802fa9cd897b5470614d57b1620bfe53f36158466f83e7cc6a6cccb1ac7557a8d5a2208c7c1366835c2cba59",
    Py0 = "115d6b7a8bc5628690ec750207b3252d4121c20c2106d0277cd41dee7b1d4ed1ff856883719bccb545054b9a745a53e2",
    Py1 = "4b55174d273b358a72687d52956af3e94d97db8d2cc508b2a4ec5b0c0b4073b8fcc52eadaea35e3eae9a441b3f86cbc",
    scalar = "150caebc321c53c0658c5cecb45e564620b57bfbad0f5d5a277be71a184937b7",
    Qx0 = "3f474d7fa1ff31949c7b61f1ff71a7ccd282201ef88ef12fcd1fd3fef6a3ca18d8bb31fa7e9f4abc713f37e02abef3",
    Qx1 = "cb94daed6079cbe5a628ae4c27e8ad31a17f14e68050e8ce1b03d5a3c0e6a6cc5a34b3115034349b2ebe8de6a2c441e",
    Qy0 = "15b09aac63ac527ad719ee2bcebda6bb646044d9060c4f72280d41186798912b6e29b2f7782744b8cdce927a9c1b9340",
    Qy1 = "5204820d6336aade860fb1cb983bcc66e10cfb352ea645b4cdf74e643e9fdf545609bd7181a67daac891f551a6ce566"
  )

  test(
    id = 5,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "7f56aa6111f341d6381090f058835b3d60200032b382108194188c40afe4225eb6fecaba734084283771923e004b5ca",
    Px1 = "18abca4d9eca6d3ef3c720ca6b27f824fdd12dcac72c167f0212f707fa22752f291c9c20a4b92417d05c64207b8e6da6",
    Py0 = "10e08fc323d2ef92c5fd9a0ba38e32e16068ac5a4a0f95b0390c2e8ad6caa446adebe16bbf628a0c2de007bfa1218317",
    Py1 = "6394379cc76d50b41865b619007de5a7cda3bb7ae6fc696bf2f83e2de562039dab890a9e2b4d61045bac606f224ba42",
    scalar = "138ecc47a9d5b6cf2a052731b8f016734614949862a9f2be703935a5e0cd43bd",
    Qx0 = "19ec61da69ffdbf79411f041276d4e9fe02df31caa79406135a7522a12965364bb3549b7310393208082465feca7c9eb",
    Qx1 = "457ddcc53f5338d34713a91ca4298896bfa7ede3b939cd1c8b320a4c9ba4c1038ac09740e5b428f5c15bdf18ca6af0b",
    Qy0 = "9e334e01a81dc6da2004d2f13eec7c15ba0ab8fb8a9628ce24a0de073b251f955ee758f5b0a298c4fadd641610c7fe0",
    Qy1 = "935bf9c37ed2ce17b9e5f8014816d8a1a3d8debfc72e39ea9121018f3a990561cfbc64c25621d16a921f458d7f40344"
  )

  test(
    id = 6,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "a8c5649d2df1bae84fd9e8bfcde5113937b3acea22d67ddfedaf1fb8de8c1ef4c70591cf505c24c31e54020c2c510c3",
    Px1 = "a0553f98229a6a067489c3ee204161c11e96f421b3e9c145dc3865b03e9d4ff6cab14c5b5308ecd31173f954463690c",
    Py0 = "b29d8dfe18dc41b4826c3a102c1bf8f306cb42433cc36ee38080f47a324c02a678f9daed0a2bc577c18b9865de029f0",
    Py1 = "558cdabf11e37c5c5e8abd668bbdd71bb3f07f320948ccaac8a207359fffe38424bfd9b1ef1d24b28b2fbb9f76faff1",
    scalar = "5668a2332db27199dcfb7cbdfca6317c2ff128db26d7df68483e0a095ec8e88f",
    Qx0 = "490e99b9a27cb49b9446a7bedb8c22ef802cfdc3609cbecd8de4e227fdb72aeafb27c53d74361008ce9ea806e25dc85",
    Qx1 = "1624f7ed9ca1fcfda7651608be2acb1d76cb37ab989c1aecf06a6401ee66afdddf283039496c2320dca4d720e8b8a337",
    Qy0 = "c6fef37a864fa1602824a2128d4a62e3221413e1ded862f11347576f43c27d69b1957385ad6ba7a9168c05e6fc2ab85",
    Qy1 = "11d4a696f8e366929fe0b7eae94702a89aef43725218f95e0bfe7d7abd726e884604838e4d7d670c9579431f9d8012e0"
  )

  test(
    id = 7,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "eb79d9e425feb105ec09ce60949721b12dac5e6721c8a6b505aa2d83270d2a3e6c6bcce16a1b510f6822504c5e86416",
    Px1 = "9f5d2dc403a2e96c3f59c7bb98a36cc8be68500510fd88b09f55938efd192d9653f4bcfd1451518c535e9d1996a924",
    Py0 = "114825899129828ee0b946811ff98a79af1b53c4511bc45a8e41a07a7d9600c824ed7c5cd608781d0a98a13e69b0c002",
    Py1 = "57600cfce779277faf31d1b18a39c752c179a76b301cbdc317263c7e8770df0d5896c9dec84958bf558c16b5ec5869c",
    scalar = "45b4bca2f783bba42b2d41a8d00f4c5f18a78738a5678fc3707523e7c62dafcb",
    Qx0 = "71bee2c58caace914434607aff9c1730af2da8bd78d1a44215d9c7cc422623e9b65ba1fc7207de9d0af96f8211eda2b",
    Qx1 = "80ea7a46f9352599f67bbbed1253b142422cb79af32b1a544e77ff02c25057396569182341e5492c4a520a756568a41",
    Qy0 = "73470439d1202c87e54d9de94121f5e36371fe527eca699f48caba867111707a250b2b0357e79a8263babb907c9f43a",
    Qy1 = "cf2f2cca752462c5fc2827b7871d517e50d7ecd819e0b9419f9b1e357874acca15c8f0a1f611aa243b9d21ce1962d3a"
  )

  test(
    id = 8,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "17ce8a849a475599245ad6b84cf5284cd15d6346ae52a833954ec50d5cf7f0be1cd8473fdc9dfd500d7f1d80bf6fa6ca",
    Px1 = "15d8128bc60c8e83846bf6748982a7188df6393a9379b2959fa7e1cb72f1c1da066fe3a6d927f97ecec3725fac65eb10",
    Py0 = "a05421595b36750e134b91500962201e9f57ac068732b9fb34ec50ff22f274d395d34d133e131e6dc7bc42d66149767",
    Py1 = "178cb2541ce0c60b8860d59762daa6a5b55a0ca034aa18b1fcc6deb23aaa093fb2a6129db0d58de044c4bbb23f1fa298",
    scalar = "6083671fcc66dc084ad73eba100830555fcfcc5eccaa6acb27cda0d3fa8d6f64",
    Qx0 = "175a067a5cca1e18c2c60c1ed84a2d0fdad20ad8e2b9b67a13d8a173d6c097bd2bb8fa6d83ff5ab3668d56d39f34cbe0",
    Qx1 = "14bdf8d62a088a6a71e5ea236bd3caa07934da726fc1f0b7ae462272c0778615734fac562a0293ae5da759dcfc78480c",
    Qy0 = "59ead353a2a4189dd9dc0d93ac86d0f3f8fd60bf3db10fd77e4295b1dfaeccb28aa481b1efce7198093a7f2e8ba3617",
    Qy1 = "a4661ce0260e251df9d2b01b5af29262e019b8ea12b3a0a2c4c125c09cadd906dcd8a25b7876e76892acfd74dfab8c5"
  )

  test(
    id = 9,
    EC = ECP_SWei_Proj[Fp2[BLS12_381]],
    Px0 = "13eb9e9906446be49345c08de406cd104d6bb9901ee12af0b80a8351027152d6f6d158d5a906e4a58c5602e97347cfd5",
    Px1 = "1218df3f2a9cd7685325a4a7bb6a3636a458a52ea7f1e1d73c2429acb74a2a9beb838c109541120b095118c90868eb0f",
    Py0 = "3ac16edac6898f11ff8ddb48fad6f59f4842cd427d72fa964171801be172b8ecd2fdffb4882d4aa6f1e730f6e53f8c5",
    Py1 = "b2d251295859b1be1854b1db06eae2ff8e3879d8ba5d9f86f4bb805c65696b48d0771cf10150983e322bdf9eb659af1",
    scalar = "644dc62869683f0c93f38eaef2ba6912569dc91ec2806e46b4a3dd6a4421dad1",
    Qx0 = "1888f703e7525e4ac29788eb6e3afde14e4c8b36f74a3058ab7e991630cdb8332fb164766db6d14186ac7fa2e593f513",
    Qx1 = "1496076ec35db3760a3cfe22a1759b01ac89b7ae21ccb9c4d7553a7881f4a610ef88a56b2e5a027ab49507fd710dd9ea",
    Qy0 = "1357e8db4a105bf81a94e9b9130a892b1ec78d564f77b2717451cce777c16a409cd19f450247c75882f1b84678d7c46d",
    Qy1 = "14dd91161426cd5d831914706ee9f427512a789f4953f82538f3fb17553840eae31c992de2ed91a6695d291b5ef4c204"
  )
